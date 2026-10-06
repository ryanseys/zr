require "ffi"
module PT
  extend FFI::Library
  ffi_lib FFI::Library::LIBC
  attach_function :pthread_main_np, [], :int
end
puts "worker: #{Thread.new { PT.pthread_main_np }.value}"
