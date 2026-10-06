# A library named by a CANDIDATE LIST is resolved with dlopen at the first
# call, so its functions go through libffi rather than a compile-time
# `extern`. A struct returned BY VALUE works on that tier too: libffi gets
# the struct's layout from the same field descriptor that a by-value
# ARGUMENT uses, so both directions agree on every tier. `div` and `ldiv`
# return their quotient/remainder pair by value on every libc.
require "ffi"

class Div < FFI::Struct
  layout :quot, :int, :rem, :int
end

class LDiv < FFI::Struct
  layout :quot, :long, :rem, :long
end

module L
  extend FFI::Library
  # The absent first candidate is what forces the runtime tier: the library
  # is only decidable once something tries to open it.
  ffi_lib ["/no/such/dir/libnothing.so", FFI::Library::LIBC]

  attach_function :div, [:int, :int], Div.by_value
  attach_function :ldiv, [:long, :long], LDiv.by_value
  attach_function :labs, [:long], :long
end

d = L.div(17, 5)
p d.class
p d[:quot]
p d[:rem]

l = L.ldiv(-17, 5)
p l[:quot]
p l[:rem]

# A scalar return on the same tier is unchanged.
p L.labs(-3)
puts "still running"
