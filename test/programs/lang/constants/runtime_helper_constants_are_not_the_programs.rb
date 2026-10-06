# The runtime's own helper constants are not ruby's, so the program can
# neither see nor reopen them. `class Formatter` at the toplevel makes a
# new class: it does not reopen the runtime's Kernel::Formatter, which
# `format` uses.
p defined?(Formatter), Kernel.const_defined?(:Formatter)
begin
  Kernel.const_get(:Formatter)
rescue NameError => e
  puts e.message
end

class Formatter
  def call(severity, time, progname, message) = "#{severity}: #{message}"
end
check = ->(host, port) { host == "example.com" && port == 443 }
p check.call("example.com", 443)
puts Formatter.new.call("INFO", nil, "app", "ready")
p format("%05.1f|%s", 3.14159, :x)

# A toplevel class or module looks at Object's own constants alone, as
# ruby does: a Kernel::Name of the same name stays apart.
module Kernel
  class Fmt
    def a = 1
  end
end

class Fmt
  def b = 2
end
p Fmt == Kernel::Fmt, Fmt.instance_methods(false)

# A private constant of a core class is the runtime's, so a subclass of
# that class still reads the program's toplevel constant.
OPTIMIZED = :mine
class Stack < Array
  def optimized = OPTIMIZED
  def small = defined?(SMALL_ARRAY_LEN)
end
p Stack.new.optimized, Stack.new.small

# A constant the program sets under that name is its own, and public.
class Array
  SMALL_ARRAY_LEN = 99
end
p Array::SMALL_ARRAY_LEN, [3, 1, 2].sort

# A private constant that ruby has too stays private and visible inside.
require "pathname"
begin
  Pathname::SEPARATOR_LIST
rescue NameError => e
  puts e.message
end
class Pathname
  p SEPARATOR_LIST
end
