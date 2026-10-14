# frozen_string_literal: true

require "test_helper"
require "prism"

# Onigmo's case fold is in the core (core/regexp/unicode_tables.rb) and
# in the kernel (kernel/onig_tables.rb), which String#downcase(:fold) and
# the engine read. This proves that the two hold the same data, by the
# literals in each file.
class UnicodeSourcesTest < Minitest::Test
  RUNTIME = File.join(ROOT, "lib/zr/runtime")

  def test_the_kernels_fold_rows_are_onigmos_case_fold
    assert_equal onigmo_fold, kernel_fold
  end

  private

  # `{ code => [folded codes] }` from Onigmo's CASE_FOLD: key, count, then
  # the codes, BER-packed.
  def onigmo_fold
    words = literal("core/regexp/unicode_tables.rb", :CASE_FOLD).unpack("w*")
    fold = {}
    fold[words.shift] = words.shift(words.shift) until words.empty?
    fold
  end

  # The same from zr_onig_fold_rows: a count, then rows of from, how
  # many, and three codes, each a little-endian u32.
  def kernel_fold
    definition = parse("kernel/onig_tables.rb").breadth_first_search { |node| node.is_a?(Prism::DefNode) && node.name == :zr_onig_fold_rows }
    bytes = definition.breadth_first_search { |node| node.is_a?(Prism::StringNode) }.unescaped
    count, *words = bytes.unpack("L<*")
    words.each_slice(5).first(count).to_h { |from, many, *codes| [from, codes.first(many)] }
  end

  # The value of the constant `name` in `file`: a literal, so it reads
  # with no runtime.
  def literal(file, name)
    write = parse(file).breadth_first_search { |node| node.is_a?(Prism::ConstantWriteNode) && node.name == name }
    eval(write.value.slice)
  end

  def parse(file) = Prism.parse_file(File.join(RUNTIME, file)).value
end
