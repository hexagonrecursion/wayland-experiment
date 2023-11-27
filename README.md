I experimented a bit with wayland in lua. Stopped half-way because I found out that what I wanted to do (detecting whether caps-lock is on when your window does not have keyboard focus) is not possible in wayland

All code exept for `str:gsub(".", function(char) return string.format("%02x", char:byte()) end)` is copyright hexagon-recursion. License: CC0 1.0 Universal
