# frozen_string_literal: true

require "test_helper"
require "zlib"
require_relative "../support/harness/kernel_jit"
require_relative "../support/harness/kernel_host"

# The kernel's checksums (lib/zr/runtime/kernel/zlib_check.rb), compiled and
# loaded into this ruby, give the same values as CRuby's zlib.
class ZlibCheckTest < Minitest::Test
  INPUTS = ["", "a", "hello, world", "\x00\xFF".b * 3000, (0..255).map(&:chr).join.b * 40].freeze

  def self.kernel
    @kernel ||= Zr::Harness::KernelJIT.new("zlib_check.rb", "zlib_tables.rb")
  end

  def test_crc32_is_zlibs
    INPUTS.each { |bytes| assert_equal Zlib.crc32(bytes), checksum("zr_crc32", 0, bytes), bytes[0, 16].inspect }
  end

  def test_adler32_is_zlibs
    INPUTS.each { |bytes| assert_equal Zlib.adler32(bytes), checksum("zr_adler32", 1, bytes), bytes[0, 16].inspect }
  end

  def test_crc32_continues_from_an_earlier_value
    first, second = "hello, ", "world"

    assert_equal Zlib.crc32(first + second), checksum("zr_crc32", Zlib.crc32(first), second)
  end

  def test_crc32_combine_is_zlibs
    a, b = "abc" * 100, "xyz" * 77
    combined = self.class.kernel.call("zr_crc32_combine", Zlib.crc32(a), Zlib.crc32(b), b.bytesize)

    assert_equal Zlib.crc32_combine(Zlib.crc32(a), Zlib.crc32(b), b.bytesize), combined
  end

  private

  # The kernel function `name` over `bytes`, starting from `initial`.
  def checksum(name, initial, bytes)
    buffer = Fiddle::Pointer.malloc([bytes.bytesize, 1].max, Fiddle::RUBY_FREE)
    buffer[0, bytes.bytesize] = bytes unless bytes.empty?
    self.class.kernel.call(name, initial, buffer.to_i, bytes.bytesize)
  end
end

# The same checks, with the kernel's Ruby run on CRuby (A7).
class ZlibCheckHostTest < ZlibCheckTest
  def self.kernel
    @kernel ||= Zr::Harness::KernelHost.new("zlib_check.rb", "zlib_tables.rb")
  end
end
