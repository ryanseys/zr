# io-console 0.9.4: IO::platform_tty, prepended to IO, gives tty? and
# isatty tty types. The Windows-only calls are not implemented here, and
# getpass reads to a newline whatever $/ is.
require "io/console"
require "stringio"
def t(label)
  p [label, yield]
rescue Exception => e
  p [label, e.class, e.message.gsub(/0x\h+/, "0x")]
end
r, w = IO.pipe
t(:ancestors) { IO.ancestors.take(2).map(&:inspect) }
t(:tty_arity) { [IO.instance_method(:tty?).arity, IO.instance_method(:isatty).owner.inspect] }
t(:tty_nil) { [r.tty?, r.tty?(nil), r.tty?(:any), r.isatty(:any, nil)] }
t(:tty_foo) { r.tty?(:foo) }
t(:tty_str) { r.tty?("any") }
t(:defined) { [IO.method_defined?(:console_input_events), IO.method_defined?(:pressed?), IO.method_defined?(:check_winsize_changed), r.respond_to?(:pressed?)] }
t(:cie) { r.console_input_events }
t(:pressed) { r.pressed?(1) }
t(:cwc) { r.check_winsize_changed }
$VERBOSE = nil
$/ = "x"
t(:getpass) { s = StringIO.new("pwxq\nz"); [s.getpass, s.string] }
$/ = "\n"
