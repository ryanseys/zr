# io/console 0.9.4: IO::Console::Mode reads and sets echo, min (VMIN) and
# time (VTIME, a Rational of tenths), clamped to a byte; an allocated
# mode is all zeros. IO::ConsoleMode and Mode::VERSION are its old,
# deprecated names.
require "io/console"
Warning[:deprecated] = true
p IO::Console::VERSION, IO::Console.constants.sort
p IO::ConsoleMode.equal?(IO::Console::Mode)
p IO::Console::Mode::VERSION == IO::Console::VERSION
m = IO::Console::Mode.allocate
p [m.echo?, m.echo, m.min, m.time]
m.min = 300
m.time = 0.55
p [m.min, m.time]
m.min = -5
m.time = 99
p [m.min, m.time]
p [(m.min = nil), m.min, (m.time = nil), m.time]
m.echo = true
p m.echo?
c = m.dup
c.echo = false
p [m.echo?, c.echo?]
r = m.raw(min: 7, time: 2)
p [r.min, r.time, r.echo?, m.min]
p IO::Console::Mode.instance_method(:echo) == IO::Console::Mode.instance_method(:echo?)
p(begin; m.min = "x"; rescue => e; e; end)
p(begin; STDOUT.console_mode = 1; rescue => e; e; end)
p(IO::Console::Mode.allocate.raw(min: -1).min)
p [IO.method_defined?(:input_pending?), IO.method_defined?(:hide_cursor)]
r, w = IO.pipe
p r.input_pending?
w << "ab"
p r.input_pending?
r.getc
p r.input_pending?
r.getc
p r.input_pending?
p w.hide_cursor.equal?(w), w.show_cursor.equal?(w)
w.close
p r.read
