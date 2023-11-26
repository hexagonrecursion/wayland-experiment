-- TODO: support WAYLAND_SOCKET 
-- TODO: support absolute paths in WAYLAND_SOCKET
-- TODO: what if XDG_RUNTIME_DIR is not set?
-- See https://wayland.freedesktop.org/docs/html/apb.html#Client-classwl__display_1af048371dfef7577bd39a3c04b78d0374 

local M = require 'posix.sys.socket'

-- Thanks https://stackoverflow.com/a/65477617/
function hex(str)
	local result = str:gsub(".", function(char) return string.format("%02x", char:byte()) end):gsub("........", "%1 ")
	return result
end

wl_display = {}
wl_display.__index = wl_display

function wl_display.new(o)
	o = o or {}
	setmetatable(o, wl_display)
	return o
end

function wl_display:sync()
	-- TODO: create a wl_callback class?
	local callback = {}
	return {self.id, 0, "new_id", callback}, callback
end
    
Wayland = {}
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
		local opcode = op_and_len & (1 << 16 - 1)
		if self.bytes_from_server:len() < len then break end
		table.insert(events, {object_id, opcode, self.bytes_from_server:sub(9, len)})
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

function create_socket()
	-- TODO: is this the best way of concatenating paths in lua?
	local socket_path = os.getenv("XDG_RUNTIME_DIR") .. "/" .. os.getenv("WAYLAND_DISPLAY")
	print(socket_path)
	-- TODO: how to close the socket?
	local socket = assert(M.socket(M.AF_UNIX, M.SOCK_STREAM, 0))
	print("socket() -> " .. socket)
	print("connect() -> " .. assert(M.connect(socket, {family = M.AF_UNIX, path = socket_path})) )
	return socket
end

function ping_the_server()
	local socket = create_socket()
	local wayland = Wayland.new()
	local display = wayland:get_wl_display()
	local request = display:sync()
	local bytes = wayland:to_server({request})
        print("send() -> " .. assert(M.send(socket, bytes)))
	
	while true do
		-- TODO: decide buffer size
		-- TODO: is wayland a steram protocol or datagram protocol?
		bytes = assert(M.recv(socket, 2 << 16))
		for _, event in ipairs(wayland:from_server(bytes)) do
			for _, v in ipairs(event) do
				if type(v) == "string" then
					print(hex(v))
				else
					print(v)
				end
			end
			print("-------------")
		end
	end
end

ping_the_server()
