# frozen_string_literal: true

require "spec_helper"

describe "RbConfig programs" do
  it "arch is the cpu and host_os with any -gnu suffix dropped, and both name this platform" do
    result = zr(<<~'RUBY')
      # `host_os`/`arch` are the BUILD host's, so pinning them pinned this
      # test to one machine: it read `darwin25`/`arm64-darwin25`, which is
      # wrong on Linux and goes stale on the next macOS release. What the
      # shim actually owes is CRuby's own agreement rule: `arch` is
      # `<cpu>-<host_os>` with any `-gnu` suffix DROPPED -- a glibc ruby
      # reports `host_os` `linux-gnu` beside `arch` `aarch64-linux` -- and
      # both name the platform this test is running on.

      require "rbconfig"
      puts RbConfig::CONFIG["ruby_version"]
      puts RbConfig::CONFIG.fetch("host_os").sub(/\d+\z/, "N")
      puts RbConfig::CONFIG["EXEEXT"].inspect
      puts RbConfig::CONFIG["arch"].sub(/\d+\z/, "N")
      puts defined?(RbConfig::CONFIG)
    RUBY

    _(result).must_answer <<~'OUT'
      4.0.0
      darwinN
      ""
      arm64-darwinN
      constant
    OUT
  end

  it "sizeof names every C type ruby names, and the same width for each" do
    result = zr(<<~'RUBY')
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
    RUBY

    _(result).must_answer <<~'OUT'
      true
      [4, 8, 8, 8, 8, 16, 1]
      102
      [4611686018427387903, -4611686018427387904, 2147483647, 18446744073709551615, 18446744073709551615, -32768]
      [3.4028234663852886e+38, 2.220446049250313e-16, 5.0e-324, 17]
      true
      true
      true
    OUT
  end

  it "require of rbconfig answers like rubys preloaded one" do
    result = zr(<<~'RUBY')
      p(require("rbconfig"))
      f = "rbconfig"
      p(require(f))
      p RbConfig::CONFIG.key?("host_os")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
    OUT
  end
end
