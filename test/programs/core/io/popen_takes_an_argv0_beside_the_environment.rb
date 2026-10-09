# IO.popen([env, [cmd, argv0], ...]): the child runs cmd with argv0 as its
# $0. macOS only: on Alpine, sh is BusyBox, which picks the applet that
# runs from argv0.
p IO.popen([{ "X" => "4" }, ["sh", "argv0"], "-c", "echo $X $0"], &:read)
