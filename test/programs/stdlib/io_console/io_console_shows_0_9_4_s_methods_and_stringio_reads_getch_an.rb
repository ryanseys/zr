# io/console 0.9.4, the version ruby loads: hide_cursor, show_cursor and
# input_pending? but no console_input_events (Windows only), and an
# IO::Console::Mode with echo, min and time. IO::generic_readable is no
# constant name, and StringIO's getch and getpass read through getc and
# gets.
require "io/console"
require "stringio"
p %i[hide_cursor show_cursor input_pending? console_input_events].map { |name| IO.method_defined?(name) }
p IO::Console::Mode.instance_methods(false).sort, IO::Console::Mode.private_instance_methods(false)
p (IO::Console::Mode.new rescue $!)
p IO.constants.include?(:generic_readable), IO.private_methods(false).sort
p StringIO.ancestors.take(3)
s = StringIO.new("pw\nzz")
p s.getpass("P: "), s.string, s.pos
s = StringIO.new("ab")
p s.getch, (s.getch(1) rescue $!)
s = StringIO.new("x")
p s.getpass, s.getpass, (s.getpass(1) rescue $!), (s.getpass("a\0") rescue $!), (s.getpass(1, 2) rescue $!)
