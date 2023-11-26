-- TODO: support WAYLAND_SOCKET 
-- TODO: support absolute paths in WAYLAND_SOCKET
-- TODO: what if XDG_RUNTIME_DIR is not set?
-- See https://wayland.freedesktop.org/docs/html/apb.html#Client-classwl__display_1af048371dfef7577bd39a3c04b78d0374 

local M = require 'posix.sys.socket'

-- Thanks https://stackoverflow.com/a/65477617/
function hex(str)
	return str:gsub(".", function(char) return string.format("%02x", char:byte()) end):gsub("........", "%1 ")
end

wl_display = {}
wl_display.__index = wl_display

function wl_display.new(o)
	o = o or {}
	setmetatable(o, wl_display)
	return o
end

function wl_display:sync()
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
			payload = payload .. string.pack("I4", req[i+1].id)
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

function decode(message)
	local format = "I4I4"
	assert(message:len() >= string.packsize(format), "no header")
	local object_id, op_and_len = string.unpack(format, message)
	local len = op_and_len >> 16
	local opcode = op_and_len & (1 << 16 - 1)
	assert(message:len() >= len, "too short")
	return object_id, opcode, message:sub(9, len)
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

	local i, o, p = decode(assert(M.recv(socket, 12)))
	print(string.format("got event: object %d opcode %d %q", i, o, hex(p)))
	local i, o, p = decode(assert(M.recv(socket, 12)))
	print(string.format("got event: object %d opcode %d %q", i, o, hex(p)))
end

ping_the_server()
