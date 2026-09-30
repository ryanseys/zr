# Every FFI integer type accepts its whole C range in both directions: a
# :ulong/:uint64/:size_t argument or return reaches 2**64-1 (a Bignum), a
# :long/:int64 reaches -2**63, and a value outside the C type raises the
# gem's own RangeError -- which names the converter (:long is not :int64).
require "ffi"

module L
  extend FFI::Library
  ffi_lib FFI::Library::LIBC
  attach_function :strtoull, [:string, :pointer, :int], :ulong
  attach_function :strtoll, [:string, :pointer, :int], :long
  attach_function :strnlen_ulong, :strnlen, [:string, :ulong], :ulong
  attach_function :strnlen_u64, :strnlen, [:string, :uint64], :uint64
  attach_function :strnlen_size_t, :strnlen, [:string, :size_t], :size_t
  attach_function :strnlen_long, :strnlen, [:string, :long], :long
  attach_function :strnlen_i64, :strnlen, [:string, :int64], :int64
  attach_function :strnlen_u32, :strnlen, [:string, :uint32], :uint32
  attach_function :strnlen_i8, :strnlen, [:string, :int8], :int8
  attach_function :llabs, [:long_long], :long_long
  attach_function :labs, [:long], :long
  attach_function :abs, [:int], :int
  attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
end

# Returns above i64::MAX and at i64::MIN.

# Arguments at both ends of every 64-bit spelling; a negative wraps for an
# unsigned type, exactly as NUM2ULONG does.

# Variadic arguments promote but keep their own converter.
buf = FFI::MemoryPointer.new(:char, 128)
L.snprintf(buf, 128, "%llu %lld %u %d", :ulong, 2**64 - 1, :long, -2**63, :uint32, 2**32 - 1, :int32, -2**31)
L.snprintf(buf, 128, "%llu %u %d", :uint64, 2**64 - 1, :uint8, -1, :int8, 200)

# A pointer round-trips the full unsigned range.
mp = FFI::MemoryPointer.new(:uint64, 3)
mp.put_uint64(0, 2**64 - 1)
mp.write_ulong(2**64 - 1)
mp.put_array_of_uint64(0, [2**64 - 1, 1, 2**63])

# A callback receives and returns the full range.
f = FFI::Function.new(:ulong, [:ulong]) { |x| p [:cb, x]; x }
g = FFI::Function.new(:long, [:long]) { |x| x }
h = FFI::Function.new(:int, [:int8]) { |x| x }

# A struct field goes through the same converters.
class S < FFI::Struct
  layout :a, :ulong, :b, :long, :c, :uint64
end
s = S.new
s[:a] = 2**64 - 1
s[:b] = -2**63
s[:c] = 2**64 - 1
p [s[:a], s[:b], s[:c]]
p S.layout.fields.map { |fld| fld.type }

