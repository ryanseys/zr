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
p L.strnlen_ulong("abc", 2**64 - 1)
p L.strnlen_u64("abc", 2**64 - 1)
p L.strnlen_size_t("abc", 2**64 - 1)
p L.strnlen_ulong("abc", -1)
p L.strnlen_long("abc", 2**63 - 1)
p L.strnlen_i64("abc", 2**63 - 1)
p L.llabs(-2**63 + 1)
p L.labs(-2**63 + 1)
p L.strnlen_u32("abc", 2**32 - 1)
p L.strnlen_u32("abc", -1)
p L.strnlen_i8("abc", 2.9)

