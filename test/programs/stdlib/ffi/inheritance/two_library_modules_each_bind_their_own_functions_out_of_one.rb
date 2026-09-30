# Two library modules each bind their own functions out of libm.
require "ffi"

module MathA
  extend FFI::Library
  ffi_lib "m"
  attach_function :fabs, [:double], :double
end

module MathB
  extend FFI::Library
  ffi_lib "m"
  attach_function :cos, [:double], :double
end

puts MathA.fabs(-1.5)
puts MathB.cos(0.0)
