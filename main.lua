local _ENV = setmetatable(
	{},
	{	__index=function(_, k) return assert(_ENV[k], "undefined variable") end,
		__newindex=function() assert(false, "_ENV is read-only") end
	}
)

local M = require 'posix.sys.socket'

local DEBUG = true

-- Thanks https://stackoverflow.com/a/65477617/
local function hex(str)
	local result = str:gsub(".", function(char) return string.format("%02x", char:byte()) end):gsub("........", "%1 ")
	return result
end

--[=====[ 

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
	local o = {}
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
	local events = {}
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


local function ping_the_server()
	local socket = create_socket()
	local wayland = Wayland.new()
	local display = wayland:get_wl_display()

	local request, registry = display:get_registry()
	local bytes = wayland:to_server({request})
	print("C -> S", hex(bytes))
	assert(M.send(socket, bytes))
	
	while true do
		-- TODO: decide buffer size
		bytes = assert(M.recv(socket, 2 << 16))
		if not bytes or #bytes == 0 then
			break -- end of file
		end
		print("S -> C", hex(bytes))
		for _, event in ipairs(wayland:from_server(bytes)) do
			print("event", table.unpack(event))
		end
	end
end

--]=====]

local function create_socket()
	-- TODO: support WAYLAND_SOCKET 
	-- TODO: support absolute paths in WAYLAND_SOCKET
	-- TODO: what if XDG_RUNTIME_DIR is not set?
	-- See https://wayland.freedesktop.org/docs/html/apb.html#Client-classwl__display_1af048371dfef7577bd39a3c04b78d0374 
	
	-- TODO: is this the best way of concatenating paths in lua?
	local socket_path = os.getenv("XDG_RUNTIME_DIR") .. "/" .. os.getenv("WAYLAND_DISPLAY")
	local socket = assert(M.socket(M.AF_UNIX, M.SOCK_STREAM, 0))
	assert(M.connect(socket, {family = M.AF_UNIX, path = socket_path}))
	return socket
end

local function encode(object_id, op, ...)
	local opcode, format  = table.unpack(op)
	local op_and_len = format:packsize() << 16 | opcode
	if DEBUG then print("encode:", opcode, format:packsize(), op_and_len, ...) end
	return format:pack(object_id, op_and_len, ...)
end

local function create_caps_lock_watcher()
	-- constants
	local wl_display_id = 1
	local wl_display_get_registry = {1, "I4 I4 I4"}
	local wl_display_error = "!4 I4 I4 I4 I4 s4XI4"
	local wl_registry_id = 2
	local wl_registry_global = "!4 I4 I4 I4 s4XI4 I4"
	local wl_registry_bind = {0, "I4 I4 I4 I4"}

	-- variables
	local handlers = {}
	local caps_lock = {"maybe or maybe not"}
	local from_server = ""
	-- TODO: the docs contain scary warnings about doing id allocation wrong. check out what the reference implementation does
	local last_used_id = 2
	
	local function on_error(...)
		print(...)
		return ""
	end

	local function on_global(_, _, name, interface, version)
		assert(type(name) == "number")
		-- if DEBUG then print(name, interface, version) end
		-- TODO: check version?
		if interface ~= "wl_seat\0" then return "" end
		if DEBUG then print("on_global:", name, interface, version) end
		last_used_id = last_used_id + 1
		return encode(wl_registry_id, wl_registry_bind, name, last_used_id)
	end

	local function parse(bytes)
		from_server = from_server .. bytes
		local to_server = ""
		while true do
			if #from_server < ("I4I4"):packsize() then break end
			local object_id, op_and_len = ("I4I4"):unpack(from_server)
			local len = op_and_len >> 16
			local opcode = op_and_len & ((1 << 16) - 1)
			if #from_server < len then break end
			local format, fn = table.unpack((handlers[object_id] or {})[opcode] or {})
			if format then
				-- TODO: string.unpack may throw or parse too many or too few bytes
				-- TODO: optimize
				to_server = to_server .. fn(format:unpack(from_server))
			end
			-- TODO: optimize
			from_server = from_server:sub(len + 1)
		end
		return to_server, caps_lock
	end

	handlers[wl_display_id] = {[0] = {wl_display_error, on_error}}
	handlers[wl_registry_id] = {[0] = {wl_registry_global, on_global}}
	local to_server = encode(wl_display_id, wl_display_get_registry, wl_registry_id)
	return to_server, parse
end

local function app()
	-- TODO: how to close the socket?
	local socket = assert(create_socket())
	local to_server, parse = create_caps_lock_watcher()
	local caps_lock
	while true do
		if DEBUG then print("C -> S", hex(to_server)) end
		assert(M.send(socket, to_server))
		-- TODO: decide buffer size
		local from_server = assert(M.recv(socket, 2 << 16))
		if #from_server == 0 then
			break -- end of file
		end
		if DEBUG then print("S -> C", hex(from_server)) end
		to_server, caps_lock = assert(parse(from_server))
		print(table.unpack(caps_lock))
	end
end

app()
