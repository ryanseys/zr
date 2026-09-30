# ruby builds rbconfig/sizeof as a C extension out of its own
# limits.h, float.h and stdint.h. zr compiles no C, so the file
# here derives the table from the target's C ABI: the pointer
# family follows the width of a pointer, and every integer limit
# follows the width of its type.
require "rbconfig/sizeof"
p RbConfig::SIZEOF.keys == %w[int short long long\ long __int128 off_t void* float double time_t clock_t
                              size_t ptrdiff_t dev_t int8_t uint8_t int16_t uint16_t int32_t uint32_t
                              int64_t uint64_t int128_t uint128_t intptr_t uintptr_t ssize_t
                              int_least8_t int_least16_t int_least32_t int_least64_t
                              int_fast8_t int_fast16_t int_fast32_t int_fast64_t intmax_t sig_atomic_t
                              wchar_t wint_t wctrans_t wctype_t _Bool long\ double
                              float\ _Complex double\ _Complex long\ double\ _Complex]
p RbConfig::SIZEOF.values_at("int", "long", "void*", "size_t", "long long", "__int128", "_Bool")
p RbConfig::LIMITS.size
p RbConfig::LIMITS.values_at("FIXNUM_MAX", "FIXNUM_MIN", "INT_MAX", "ULONG_MAX", "SIZE_MAX", "INT_FAST16_MIN")
p RbConfig::LIMITS.values_at("FLT_MAX", "DBL_EPSILON", "DBL_TRUE_MIN", "DECIMAL_DIG")
p RbConfig::SIZEOF.frozen?, RbConfig::LIMITS.frozen?, RbConfig::SIZEOF.keys.first.frozen?
