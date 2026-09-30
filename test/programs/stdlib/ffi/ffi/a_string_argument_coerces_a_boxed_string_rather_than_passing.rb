# An FFI :string arg call site gets a value of no single type (an ivar that
# a mixed-type initializer sets). The call must pass the String's bytes to
# C. libc's atoi(const char *) exercises the :string coercion through a
# real, always-available external function.
require "ffi"

class Sink
  attr_accessor :body
  def initialize(flag)
    @body = flag ? "42" : 7
  end
end

module Lib
  extend FFI::Library
  ffi_lib FFI::Library::LIBC
  attach_function :atoi, [:string], :int
end

s = Sink.new(true)
puts Lib.atoi(s.body)
