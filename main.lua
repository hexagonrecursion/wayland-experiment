-- TODO: support WAYLAND_SOCKET 
-- TODO: support absolute paths in WAYLAND_SOCKET
-- TODO: what if XDG_RUNTIME_DIR is not set?
-- See https://wayland.freedesktop.org/docs/html/apb.html#Client-classwl__display_1af048371dfef7577bd39a3c04b78d0374 

function print_socket_name()
	-- TODO: is this the best way of concatenating paths in lua?
	local socket_path = os.getenv("XDG_RUNTIME_DIR") .. "/" .. os.getenv("WAYLAND_DISPLAY")
	print(socket_path)
end

print_socket_name()

