# An FFI numeric arg (:int) call site gets a value of no single type (an ivar
# that a mixed-type initializer sets). The call must pass the Integer
# value to C.
require "ffi"

class Sink
  attr_accessor :n
  def initialize(flag)
    @n = flag ? 42 : "fallback"
  end
end

module Lib
  extend FFI::Library
  ffi_lib FFI::Library::LIBC
  attach_function :abs, [:int], :int
end

s = Sink.new(true)
puts Lib.abs(s.n)
