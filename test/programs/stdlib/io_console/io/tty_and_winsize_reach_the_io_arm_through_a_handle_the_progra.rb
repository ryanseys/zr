# IO#tty? and IO#winsize on a handle of no single known type.
#
# The handle comes out of a container, or from a parameter that gets values
# of different types. The call must still reach the IO method, not raise
# NoMethodError for a value that IS an IO.
#
# What is pinned is reachability, not any particular terminal geometry: the
# test runs with stdout redirected to a file, so it must not depend on a tty
# existing. winsize is only asserted to answer WITHOUT NoMethodError, because
# a non-tty answer can differ (CRuby raises Errno::ENOTTY).
require "io/console"

def winsize_reachable?(stream)
  size = stream.winsize
  size.is_a?(Array)
rescue NoMethodError
  false          # the bug: an IO that claims not to know the method
rescue StandardError
  true           # ENOTTY and friends: reached the method, no tty to measure
end

File.write("/tmp/sp_ttyws.txt", "x")

# A block parameter over a literal array: the shape that regressed.
[STDOUT].each { |s| p s.tty?.class }

# A file handle out of a container answers false, not NoMethodError.
File.open("/tmp/sp_ttyws.txt") do |f|
  [f].each { |s| p s.tty? }
  handles = [f, f]
  p handles[0].tty?
  p handles.first.tty?
  [f].each { |s| p winsize_reachable?(s) }
end

# Two call sites that disagree degrade the parameter to poly. The IO site
# must keep working: this is what silently broke a winsize probe that also
# accepted IO.console's (untyped) result.
def probe_tty(stream)
  stream.tty?
rescue NoMethodError
  :no_method
end

def untyped
  IO.console
rescue StandardError
  nil
end

File.open("/tmp/sp_ttyws.txt") do |f|
  p probe_tty(f)
  p winsize_reachable?(f)
end
other = untyped
p probe_tty(other).equal?(:no_method) == false || other.nil?

# isatty is the same method under its second name.
File.open("/tmp/sp_ttyws.txt") do |f|
  [f].each { |s| p s.isatty }
end

File.delete("/tmp/sp_ttyws.txt")
