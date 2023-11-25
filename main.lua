-- TODO: support WAYLAND_SOCKET 
-- TODO: support absolute paths in WAYLAND_SOCKET
-- TODO: what if XDG_RUNTIME_DIR is not set?
-- See https://wayland.freedesktop.org/docs/html/apb.html#Client-classwl__display_1af048371dfef7577bd39a3c04b78d0374 

local M = require 'posix.sys.socket'

-- Thanks https://stackoverflow.com/a/65477617/
function hex(str)
	return str:gsub(".", function(char) return string.format("%02x", char:byte()) end):gsub("........", "%1 ")
end

function encode(object_id, opcode, payload)
	-- TODO: check: is object_id in wayland packet header unsigned?
	-- TODO: check: is opcode in wayland packet header unsigned?
	-- TODO: check: does lua work fine with 32 bit unsigned integers?
	local format = "I4I4c" .. payload:len()
	local op_and_len = string.packsize(format) << 16 | opcode 
	return string.pack(format, object_id, op_and_len, payload) 
end

function decode(message)
	local format = "I4I4"
	if message:len() < string.packsize(format) then
		print("no header") -- DEBUG
		return nil
	end
	local object_id, op_and_len = string.unpack(format, message)
	local len = op_and_len >> 16
	local opcode = op_and_len & (1 << 16 - 1)
	if message:len() < len then
		print("too small") -- DEBUG
		return nil
	end
	return object_id, opcode, message:sub(9, len)
end

function ping_the_server()
	-- TODO: is this the best way of concatenating paths in lua?
	local socket_path = os.getenv("XDG_RUNTIME_DIR") .. "/" .. os.getenv("WAYLAND_DISPLAY")
	print(socket_path)
	-- TODO: how to close the socket?
	local s = assert(M.socket(M.AF_UNIX, M.SOCK_STREAM, 0))
	print("socket() -> " .. s)
	print("connect() -> " .. assert(M.connect(s, {family = M.AF_UNIX, path = socket_path})) )
	-- TODO: this assumes "host's byte-order" is little-endian. How to detect byte order in lua?
	local wl_display_sync = encode(1, 0, "\x02\x00\x00\x00")
        print("send() -> " .. assert(M.send(s, wl_display_sync)))
	local i, o, p = decode(assert(M.recv(s, 12)))
	print(string.format("got event: object %d opcode %d %q", i, o, hex(p)))
	local i, o, p = decode(assert(M.recv(s, 12)))
	print(string.format("got event: object %d opcode %d %q", i, o, hex(p)))
end

ping_the_server()
