# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/kernel_jit"
require_relative "../support/harness/kernel_host"

# The kernel's long products (lib/zr/runtime/kernel/big_words.rb),
# compiled and loaded into this ruby, give CRuby's products: by the
# schoolbook below BIG_KARATSUBA words, by Karatsuba's splits from it,
# for factors of equal and of unequal length.
class BigWordsTest < Minitest::Test
  BITS = 30
  # The kernel's BIG_KARATSUBA.
  SPLIT = Integer(File.read(File.join(Zr::Paths::RUNTIME, "kernel/big_words.rb"))[/^  BIG_KARATSUBA = (\d+)$/, 1])
  # Lengths in words around each place where the method changes: below
  # and at the split, a half that no longer splits, and lengths that
  # split again more than once.
  SIZES = [[1, 1], [SPLIT - 1, SPLIT - 1], [SPLIT, SPLIT], [SPLIT + 1, SPLIT], [(2 * SPLIT) + 1, SPLIT], [(2 * SPLIT) + 1, (2 * SPLIT) + 1],
           [(5 * SPLIT) + 3, (5 * SPLIT) + 3], [(5 * SPLIT) + 3, SPLIT + 7], [300, 45], [640, 639]].freeze

  def self.kernel
    @kernel ||= Zr::Harness::KernelJIT.new("big_words.rb")
  end

  def sizes = SIZES

  def test_products_of_mixed_words_are_cruby_products
    sizes.each do |n, m|
      x = mixed(n, 3)
      y = mixed(m, 7)
      assert_equal x * y, product(x, y), "#{n} x #{m} words"
    end
  end

  # Every word all ones carries at each step; a power of two has one bit.
  def test_products_of_all_ones_and_powers_of_two_are_cruby_products
    sizes.each do |n, m|
      ones = (1 << (BITS * n)) - 1
      power = 1 << ((BITS * m) - 1)
      assert_equal ones * ones, product(ones, ones), "#{n} words of ones squared"
      assert_equal ones * power, product(ones, power), "#{n} words of ones by 2**#{(BITS * m) - 1}"
    end
  end

  def test_the_work_block_grows_with_the_longer_factor
    assert_equal (8 * 100) + 256, self.class.kernel.call("zr_big_kara_work", 100)
  end

  private

  # A value of exactly `n` words with no simple pattern.
  def mixed(n, seed) = (seed**((BITS * n) / Math.log2(seed)).floor) | (1 << ((BITS * n) - 1))

  # `x * y` from zr_big_kara, `x` the longer, over Fiddle buffers.
  def product(x, y)
    x, y = y, x if words(x).size < words(y).size
    xw = words(x)
    yw = words(y)
    out = buffer(xw.size + yw.size)
    work = buffer(self.class.kernel.call("zr_big_kara_work", xw.size))
    self.class.kernel.call("zr_big_kara", out.to_i, filled(xw).to_i, xw.size, filled(yw).to_i, yw.size, work.to_i)
    out[0, (xw.size + yw.size) * 8].unpack("Q<*").reverse.inject(0) { |acc, word| (acc << BITS) | word }
  end

  def words(n) = n.digits(1 << BITS)

  def filled(words) = buffer(words.size).tap { |b| b[0, words.size * 8] = words.pack("Q<*") }

  def buffer(n) = Fiddle::Pointer.malloc(n * 8, Fiddle::RUBY_FREE)
end

# The same products, with the kernel's Ruby run on CRuby (`Machine::Host`),
# over the shorter lengths: the host runs each word operation as a call.
class BigWordsHostTest < BigWordsTest
  def self.kernel
    @kernel ||= Zr::Harness::KernelHost.new("big_words.rb")
  end

  def sizes = SIZES.select { |n, m| n * m <= 6_000 }
end
