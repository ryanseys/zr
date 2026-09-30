# An attached strlen binding returns the length of its argument.
require "ffi"

module Pathy
  extend FFI::Library
  ffi_lib FFI::Library::LIBC
  attach_function :strlen, [:string], :size_t
end

puts Pathy.strlen("hello")
puts Pathy.strlen("")
