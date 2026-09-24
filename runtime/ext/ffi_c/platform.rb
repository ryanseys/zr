# frozen_string_literal: true

# Platform.c: the byte order, and the size and alignment in bits of the
# C types the platform has.
module FFI
  module Platform
    BYTE_ORDER = 1234
    LITTLE_ENDIAN = 1234
    BIG_ENDIAN = 4321

    { INT8: [1, 1], INT16: [2, 2], INT32: [4, 4], INT64: [8, 8], LONG: [8, 8], FLOAT: [4, 4], DOUBLE: [8, 8],
      LONG_DOUBLE: [8, 8], ADDRESS: [8, 8] }.each do |name, (size, alignment)|
      const_set(:"#{name}_ALIGN", alignment * 8)
      const_set(:"#{name}_SIZE", size * 8)
    end
  end
end
