-- TODO: support WAYLAND_SOCKET 
-- TODO: support absolute paths in WAYLAND_SOCKET
-- TODO: what if XDG_RUNTIME_DIR is not set?
-- See https://wayland.freedesktop.org/docs/html/apb.html#Client-classwl__display_1af048371dfef7577bd39a3c04b78d0374 

local M = require 'posix.sys.socket'

-- Thanks https://stackoverflow.com/a/65477617/
function hex(str)
	return str:gsub(".", function(char) return string.format("%02x", char:byte()) end)
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
        print("send() -> " .. assert(M.send(s, "\x01\x00\x00\x00\x00\x00\x0c\x00\x02\x00\x00\x00")))
	print("message: ", hex(assert(M.recv(s, 12))))
	print("message: ", hex(assert(M.recv(s, 12))))
end

ping_the_server()
