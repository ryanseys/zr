# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/kernel_jit"
require_relative "../support/harness/kernel_host"

# WASI has no libm in a zr module, so the WASI layer defines frexp and
# ldexp itself (lib/zr/runtime/kernel/os/wasi/libm.rb). Compiled for this host,
# they give the same values as CRuby's Math.frexp and Math.ldexp.
class WasiLibmTest < Minitest::Test
  VALUES = [1.0, -1.0, 0.5, 3.0, 44.7815, -2.675, 1.0e20, 1.0e-300, 5.0e-324, -2.2250738585072014e-308,
            Float::MAX, Float::MIN, Float::EPSILON].freeze

  def self.kernel = @kernel ||= Zr::Harness::KernelJIT.new("os/wasi/libm.rb")

  def test_frexp_is_crubys
    VALUES.each do |x|
      assert_equal Math.frexp(x), frexp(x), x.inspect
    end
  end

  def test_frexp_returns_zero_infinity_and_nan_unchanged
    assert_equal [0.0, 0], frexp(0.0)
    assert_equal [Float::INFINITY, 0], frexp(Float::INFINITY)
    assert_predicate frexp(Float::NAN).first, :nan?
  end

  def test_ldexp_is_crubys
    VALUES.product([0, 1, -1, 52, -52, 1023, -1022, -1074, 1100, -1100, 2000, -2000]).each do |x, n|
      want = Math.ldexp(x, n)
      got = self.class.kernel.call("ldexp", x, n)

      assert_equal [want].pack("G"), [got].pack("G"), "ldexp(#{x}, #{n})"
    end
  end

  private

  def frexp(x)
    e = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
    m = self.class.kernel.call("frexp", x, e.to_i)
    [m, e[0, 4].unpack1("l")]
  end
end

# The same checks, with the kernel's Ruby run on CRuby (A7).
class WasiLibmHostTest < WasiLibmTest
  def self.kernel = @kernel ||= Zr::Harness::KernelHost.new("os/wasi/libm.rb")
end
