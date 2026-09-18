# frozen_string_literal: true

# `rbconfig/sizeof`, which ruby builds as a C extension out of its own
# <limits.h>, <float.h> and <stdint.h>. ze0 compiles no C, so the facts
# come from the target the program was built for instead: every target
# here is one C ABI, and `RUBY_PLATFORM` names which. A gem reads these
# to size a buffer or to bound an integer, and both answers follow from
# the width of a pointer.
module RbConfig
  # The widths that do not move: C fixes them, or every ABI ze0 emits
  # for agrees on them.
  sizeof = {
    "int" => 4, "short" => 2, "long long" => 8, "__int128" => 16, "off_t" => 8,
    "float" => 4, "double" => 8, "time_t" => 8, "clock_t" => 8, "dev_t" => 4,
    "int8_t" => 1, "uint8_t" => 1, "int16_t" => 2, "uint16_t" => 2,
    "int32_t" => 4, "uint32_t" => 4, "int64_t" => 8, "uint64_t" => 8,
    "int128_t" => 16, "uint128_t" => 16,
    "int_least8_t" => 1, "int_least16_t" => 2, "int_least32_t" => 4, "int_least64_t" => 8,
    "int_fast8_t" => 1, "int_fast16_t" => 2, "int_fast32_t" => 4, "int_fast64_t" => 8,
    "intmax_t" => 8, "sig_atomic_t" => 4,
    "wchar_t" => 4, "wint_t" => 4, "wctrans_t" => 4, "wctype_t" => 4,
    "_Bool" => 1, "long double" => 8,
    "float _Complex" => 8, "double _Complex" => 16, "long double _Complex" => 16
  }

  # The pointer family. wasm32 is an ILP32 ABI, where a pointer, a
  # `long` and a `size_t` are four bytes; every other target ze0 emits
  # for is LP64.
  pointer = RUBY_PLATFORM.start_with?("wasm32") ? 4 : 8
  %w[long void* size_t ptrdiff_t intptr_t uintptr_t ssize_t].each { |name| sizeof[name] = pointer }

  # In the order the C extension writes them, so a program that prints
  # the table prints ruby's.
  ORDER = %w[
    int short long long\ long __int128 off_t void* float double time_t clock_t size_t ptrdiff_t dev_t
    int8_t uint8_t int16_t uint16_t int32_t uint32_t int64_t uint64_t int128_t uint128_t
    intptr_t uintptr_t ssize_t
    int_least8_t int_least16_t int_least32_t int_least64_t
    int_fast8_t int_fast16_t int_fast32_t int_fast64_t
    intmax_t sig_atomic_t wchar_t wint_t wctrans_t wctype_t _Bool long\ double
    float\ _Complex double\ _Complex long\ double\ _Complex
  ].freeze
  private_constant :ORDER

  SIZEOF = ORDER.to_h { |name| [name, sizeof.fetch(name)] }.freeze

  # A signed type of `bytes` holds -2**(n-1) .. 2**(n-1)-1, and an
  # unsigned one 0 .. 2**n-1. Every integer limit follows, so the table
  # is derived rather than written down.
  signed = ->(bytes) { [(1 << ((bytes * 8) - 1)) - 1, -(1 << ((bytes * 8) - 1))] }
  unsigned = ->(bytes) { (1 << (bytes * 8)) - 1 }

  limits = {}
  # A Fixnum here is a tagged 63-bit machine word on every target, two
  # bits of which are the tag, so its range is the same everywhere.
  limits["FIXNUM_MAX"], limits["FIXNUM_MIN"] = signed[8].map { |n| n >> 1 }
  limits["CHAR_MAX"], limits["CHAR_MIN"] = signed[1]
  limits["SCHAR_MAX"], limits["SCHAR_MIN"] = signed[1]
  limits["UCHAR_MAX"] = unsigned[1]
  limits["WCHAR_MAX"], limits["WCHAR_MIN"] = signed[SIZEOF["wchar_t"]]
  limits["SHRT_MAX"], limits["SHRT_MIN"] = signed[SIZEOF["short"]]
  limits["USHRT_MAX"] = unsigned[SIZEOF["short"]]
  limits["INT_MAX"], limits["INT_MIN"] = signed[SIZEOF["int"]]
  limits["UINT_MAX"] = unsigned[SIZEOF["int"]]
  limits["LONG_MAX"], limits["LONG_MIN"] = signed[SIZEOF["long"]]
  limits["ULONG_MAX"] = unsigned[SIZEOF["long"]]
  limits["LLONG_MAX"], limits["LLONG_MIN"] = signed[SIZEOF["long long"]]
  limits["ULLONG_MAX"] = unsigned[SIZEOF["long long"]]
  { 8 => 1, 16 => 2, 32 => 4, 64 => 8 }.each do |bits, bytes|
    max, min = signed[bytes]
    limits["INT#{bits}_MAX"], limits["INT#{bits}_MIN"] = max, min
    limits["UINT#{bits}_MAX"] = unsigned[bytes]
    %w[LEAST FAST].each do |kind|
      width = SIZEOF["int_#{kind.downcase}#{bits}_t"]
      wide_max, wide_min = signed[width]
      limits["INT_#{kind}#{bits}_MAX"], limits["INT_#{kind}#{bits}_MIN"] = wide_max, wide_min
      limits["UINT_#{kind}#{bits}_MAX"] = unsigned[width]
    end
  end
  limits["INTMAX_MAX"], limits["INTMAX_MIN"] = signed[SIZEOF["intmax_t"]]
  limits["UINTMAX_MAX"] = unsigned[SIZEOF["intmax_t"]]
  limits["INTPTR_MAX"], limits["INTPTR_MIN"] = signed[SIZEOF["intptr_t"]]
  limits["UINTPTR_MAX"] = unsigned[SIZEOF["uintptr_t"]]
  limits["SIZE_MAX"] = unsigned[SIZEOF["size_t"]]
  limits["PTRDIFF_MAX"], limits["PTRDIFF_MIN"] = signed[SIZEOF["ptrdiff_t"]]

  # The float limits are IEEE 754's, which every target ze0 emits for
  # keeps: `float` is binary32, `double` and `long double` binary64.
  limits.update(
    "FLT_RADIX" => 2, "FLT_ROUNDS" => 1, "FLT_EVAL_METHOD" => 0,
    "FLT_MANT_DIG" => 24, "DBL_MANT_DIG" => 53, "LDBL_MANT_DIG" => 53,
    "FLT_DIG" => 6, "DBL_DIG" => 15, "LDBL_DIG" => 15,
    "FLT_MIN_EXP" => -125, "DBL_MIN_EXP" => -1021, "LDBL_MIN_EXP" => -1021,
    "FLT_MIN_10_EXP" => -37, "DBL_MIN_10_EXP" => -307, "LDBL_MIN_10_EXP" => -307,
    "FLT_MAX_EXP" => 128, "DBL_MAX_EXP" => 1024, "LDBL_MAX_EXP" => 1024,
    "FLT_MAX_10_EXP" => 38, "DBL_MAX_10_EXP" => 308, "LDBL_MAX_10_EXP" => 308,
    "FLT_DECIMAL_DIG" => 9, "DBL_DECIMAL_DIG" => 17, "LDBL_DECIMAL_DIG" => 17,
    "DECIMAL_DIG" => 17,
    "FLT_HAS_SUBNORM" => 1, "DBL_HAS_SUBNORM" => 1, "LDBL_HAS_SUBNORM" => 1,
    "FLT_MAX" => 3.4028234663852886e+38, "DBL_MAX" => Float::MAX,
    "FLT_EPSILON" => 1.1920928955078125e-07, "DBL_EPSILON" => Float::EPSILON,
    "FLT_MIN" => 1.1754943508222875e-38, "DBL_MIN" => Float::MIN,
    "FLT_TRUE_MIN" => 1.401298464324817e-45, "DBL_TRUE_MIN" => 5.0e-324
  )

  LIMITS = limits.freeze
end
