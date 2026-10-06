# printf writes to $stdout when its first argument is a String, and
# else to the first argument, with its own `write` and no `$\`.
require "stringio"
io = StringIO.new
printf(io, "%d-%s\n", 5, "x")
Kernel.printf(io, "%05.1f", 3.14159)
p io.string
$\ = "!"
printf("%s\n", "no separator")
$\ = nil
o = Object.new
def o.write(*s) = (print "[#{s.join}]"; 3)
printf(o, "%x", 255)
puts
p printf
