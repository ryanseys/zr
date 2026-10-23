# A read that finds nothing leaves no end-of-file mark behind, as CRuby
# keeps none: a getch that timed out on a terminal, or a ^D, reads on
# after. getpass chomps the default separator, whatever $/ is.
require "io/console"
require "pty"
def t(label)
  print label, ": "
  p yield
rescue Exception => e
  p [e.class, e.message]
end
m, s = PTY.open
# What the terminal echoes. Linux echoes input later, on a work queue,
# where macOS echoes during the write, so the test reads each echo before
# a getch turns echo off; the prompt row prints all of it.
echo = +""
echoed = ->(text) { echo << m.readpartial(100) until echo.end_with?(text) }
# A thread types only once echo is off: the getch or getpass that reads
# its input has started.
type = ->(text) { Thread.new { sleep 0.01 while s.echo?; m.print(text); m.flush } }
t("getch min 0") { s.getch(min: 0) }
t("getch min 0 time") { s.getch(min: 0, time: 0.1) }
m.print("ab"); m.flush
echoed.("ab")
t("getch min 1 time 1") { s.getch(min: 1, time: 1) }
t("getch time 1") { s.getch(time: 1) }
m.print("xy"); m.flush
echoed.("xy")
t("getch min 2") { s.getch(min: 2) }
t("raw min/time") { s.raw(min: 0, time: 0.1) { s.getc } }
th = type.("z")
t("getch waits") { s.getch }
th.join
old = $/
$/ = "."
th = type.("asdf\n")
t("getpass with $/ = '.'") { s.getpass("> ") }
th.join
# The echo of the newline can come in a second read on Linux.
t("prompt") do
  echoed.("\n")
  echo
end
$/ = old
t("cursor") do
  th = Thread.new { m.readpartial(10).then { |q| m.print("\e[12;34R"); m.flush; q } }
  c = s.cursor
  [c, th.value]
end
t("cursor short reply") do
  th = Thread.new { m.readpartial(10).then { |q| m.print("\e[12R"); m.flush; q } }
  c = s.cursor
  [c, th.value]
end
t("^D then more") do
  th = Thread.new { sleep 0.05; m.write("\C-d"); sleep 0.05; m.write("more\n") }
  [s.gets, s.gets].tap { th.join }
end
r, w = IO.pipe
w.write("a")
t("pipe read") { [r.read(1), r.read_nonblock(1, exception: false)] }
w.write("b")
t("pipe after empty read") { r.read(1) }
w.close
t("pipe at the end") { [r.read, r.read, r.gets, r.eof?, (r.readpartial(1) rescue $!.class)] }
