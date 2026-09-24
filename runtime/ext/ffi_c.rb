# frozen_string_literal: true

# ffi_c: the ffi gem's C half, in ruby over the kernel's calls
# (runtime/kernel/ffi.rb), which reach libffi. lib/ffi.rb, as the gem ships
# it, requires this first and then reopens what it defines. The files
# follow the order Init_ffi_c defines things in, and each stands for the
# C files it names.
module FFI
end

require_relative "ffi_c/native"
require_relative "ffi_c/type"
require_relative "ffi_c/last_error"
require_relative "ffi_c/platform"
require_relative "ffi_c/abstract_memory"
require_relative "ffi_c/pointer"
require_relative "ffi_c/function"
require_relative "ffi_c/buffer"
require_relative "ffi_c/struct"
require_relative "ffi_c/dynamic_library"
require_relative "ffi_c/variadic"
