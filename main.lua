local M = require 'posix.sys.socket'
local function DEBUG(...) end
local function DEBUG(...) print(...) end

-- Thanks https://stackoverflow.com/a/65477617/
local function hex(str)
	local result = str:gsub(".", function(char) return string.format("%02x", char:byte()) end):gsub("........", "%1 ")
	return result
end

local function mk_wl_clas(name, events)
	local cls = {events = {}}
	for k, v in ipairs(events) do
		cls.events[k - 1] = v
	end
	cls.__index = cls
	function cls:__tostring ()
		return string.format("%s<%d>", name, self.id)
	end
	function cls.new(o)
		o = o or {}
		setmetatable(o, cls)
		return o
	end
	return cls
end

-- TODO: add missing events
local wl_display = mk_wl_clas("wl_display", {{"error", "!4 I4 I4 s4 XI4"}, {"delete_id", "I4"}})
local wl_callback = mk_wl_clas("wl_callback", {{"done", "I4"}})
local wl_registry = mk_wl_clas("wl_registry", {{"global", "!4 I4 s4 XI4 I4"}})

function wl_display:sync()
	local callback = wl_callback.new()
	return {self.id, 0, "new_id", callback}, callback
end

function wl_display:get_registry()
	local r = wl_registry.new()
	return {self.id, 1, "new_id", r}, r
end
    
local Wayland = {}
Wayland.__index = Wayland

function Wayland.new()
	o = {}
	o.bytes_from_server = ""
	o.object_by_id = {
		[1] = wl_display.new({id = 1})
	}
	-- TODO: the docs contain scary warnings about doing id allocation wrong. check out what the reference implementation does
	o.next_free_id = 2
	setmetatable(o, Wayland)
	return o
end

-- Append `bytes` to buffer, return an array of events
function Wayland:from_server(bytes)
	self.bytes_from_server = self.bytes_from_server .. bytes
	local format = "I4I4"
	events = {}
	while true do
		if self.bytes_from_server:len() < string.packsize(format) then break end
		local object_id, op_and_len = string.unpack(format, self.bytes_from_server)
		local len = op_and_len >> 16
		local opcode = op_and_len & ((1 << 16) - 1)
		if self.bytes_from_server:len() < len then break end
		local obj = assert(self.object_by_id[object_id], "server sent event from unknown object "..object_id)
		local opname = "unknown event "..opcode
		local arg_format = ""
		if obj.events[opcode] then
			opname = assert(obj.events[opcode][1])
			arg_format = assert(obj.events[opcode][2])
		end
		-- TODO: string.unpack may error
		local one_event = {obj, opname, string.unpack(arg_format, self.bytes_from_server:sub(9, len))}
		table.remove(one_event) -- the last return of string.unpack is length
		table.insert(events, one_event)
		-- TODO: optimize
		self.bytes_from_server = self.bytes_from_server:sub(len + 1)
	end
	return events
end

-- Encode an array of requests
function Wayland:to_server(requests)
	-- TODO: check: is object_id in wayland packet header unsigned?
	-- TODO: check: is opcode in wayland packet header unsigned?
	-- TODO: check: does lua work fine with 32 bit unsigned integers?
	assert(#requests == 1, "multiple requests are not supported yet")	
	local req = requests[1] -- TODO: handle many

	local object_id = req[1]
	local opcode = req[2]
	-- TODO: optimize
	local payload = ""
	for i = 3, #req, 2 do
		if req[i] == "new_id" then
			req[i+1].id = self.next_free_id
			self.object_by_id[req[i+1].id] = req[i+1]
			payload = payload .. string.pack("I4", req[i+1].id)
			self.next_free_id = 1 + self.next_free_id
		else
			assert(nil, "unknown type "..req[i])
		end
	end
	local format = "I4I4c" .. payload:len()
	local op_and_len = string.packsize(format) << 16 | opcode 
	return string.pack(format, object_id, op_and_len, payload) 
end

function Wayland:get_wl_display()
	return self.object_by_id[1]
end

local function create_socket()
	-- TODO: support WAYLAND_SOCKET 
	-- TODO: support absolute paths in WAYLAND_SOCKET
	-- TODO: what if XDG_RUNTIME_DIR is not set?
	-- See https://wayland.freedesktop.org/docs/html/apb.html#Client-classwl__display_1af048371dfef7577bd39a3c04b78d0374 
	
	-- TODO: is this the best way of concatenating paths in lua?
	local socket_path = os.getenv("XDG_RUNTIME_DIR") .. "/" .. os.getenv("WAYLAND_DISPLAY")
	-- TODO: how to close the socket?
	local socket = assert(M.socket(M.AF_UNIX, M.SOCK_STREAM, 0))
	assert(M.connect(socket, {family = M.AF_UNIX, path = socket_path}))
	return socket
end

local function ping_the_server()
	local socket = create_socket()
	local wayland = Wayland.new()
	local display = wayland:get_wl_display()

	local request, registry = display:get_registry()
	local bytes = wayland:to_server({request})
	DEBUG("C -> S", hex(bytes))
	assert(M.send(socket, bytes))
	
	while true do
		-- TODO: decide buffer size
		-- TODO: is wayland a steram protocol or datagram protocol?
		bytes = assert(M.recv(socket, 2 << 16))
		if not bytes or #bytes == 0 then
			break -- end of file
		end
		DEBUG("S -> C", hex(bytes))
		for _, event in ipairs(wayland:from_server(bytes)) do
			DEBUG("event", table.unpack(event))
		end
	end
end

ping_the_server()
