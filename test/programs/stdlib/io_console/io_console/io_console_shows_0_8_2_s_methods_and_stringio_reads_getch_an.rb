# io/console 0.8.2, the version ruby loads: no hide_cursor, show_cursor,
# input_pending? or console_input_events, and a ConsoleMode with only
# echo=, raw and raw!. IO::generic_readable is no constant name, and
# StringIO's getch and getpass read through getc and gets.
require "io/console"
require "stringio"
p %i[hide_cursor show_cursor input_pending? console_input_events].map { |name| IO.method_defined?(name) }
p IO::ConsoleMode.instance_methods(false).sort, IO::ConsoleMode.private_instance_methods(false)
p (IO::ConsoleMode.new rescue $!)
p IO.constants.include?(:generic_readable), IO.private_methods(false).sort
p StringIO.ancestors.take(3)
s = StringIO.new("pw\nzz")
p s.getpass("P: "), s.string, s.pos
s = StringIO.new("ab")
p s.getch, (s.getch(1) rescue $!)
s = StringIO.new("x")
p s.getpass, s.getpass, (s.getpass(1) rescue $!), (s.getpass("a\0") rescue $!), (s.getpass(1, 2) rescue $!)
