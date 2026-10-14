# frozen_string_literal: true

require "test_helper"
require "prism"

# The core keeps some Unicode data twice: String's case fold and its
# table of characters that inspect escapes (core/unicode.rb), beside
# Onigmo's case fold and Print class (core/regexp/unicode_tables.rb) and
# the kernel's fold rows (kernel/onig_tables.rb). This proves that the
# copies hold the same data, by the literals in each file.
class UnicodeSourcesTest < Minitest::Test
  RUNTIME = File.join(ROOT, "lib/zr/runtime")
  SURROGATES = (0xD800..0xDFFF)

  def test_strings_fold_is_onigmos_case_fold
    assert_equal onigmo_fold.size, string_fold.size
    assert_equal onigmo_fold, string_fold
  end

  def test_the_kernels_fold_rows_are_onigmos_case_fold
    assert_equal onigmo_fold, kernel_fold
  end

  # Inspect escapes a character above ASCII that Onigmo's Print class
  # leaves out. A surrogate is never a character of a valid string.
  def test_strings_unprintable_runs_are_the_characters_outside_print
    unprintable = literal("core/unicode.rb", :UNPRINTABLE_RUNS).each_slice(2).map { |first, count| first...(first + count) }
    printable = print_ranges.map { |low, high| low..high }

    expected = without_surrogates(complement(printable, 128..0x10FFFF))
    assert_equal expected, without_surrogates(merge(unprintable))
  end

  private

  # `{ code => [folded codes] }` from FOLD_RUNS and FOLD_MULTI.
  def string_fold
    runs = literal("core/unicode.rb", :FOLD_RUNS).each_slice(3).flat_map do |first, count, delta|
      (first...(first + count)).map { |code| [code, [code + delta]] }
    end
    runs.to_h.merge(literal("core/unicode.rb", :FOLD_MULTI))
  end

  # The same from Onigmo's CASE_FOLD: key, count, then the codes, BER-packed.
  def onigmo_fold
    @onigmo_fold ||= begin
      words = literal("core/regexp/unicode_tables.rb", :CASE_FOLD).unpack("w*")
      fold = {}
      fold[words.shift] = words.shift(words.shift) until words.empty?
      fold
    end
  end

  # The same from zr_onig_fold_rows: a count, then rows of from, how
  # many, and three codes, each a little-endian u32.
  def kernel_fold
    definition = parse("kernel/onig_tables.rb").breadth_first_search { |node| node.is_a?(Prism::DefNode) && node.name == :zr_onig_fold_rows }
    bytes = definition.breadth_first_search { |node| node.is_a?(Prism::StringNode) }.unescaped
    count, *words = bytes.unpack("L<*")
    words.each_slice(5).first(count).to_h { |from, many, *codes| [from, codes.first(many)] }
  end

  # The `[low, high]` pairs of Onigmo's Print class, decoded as
  # Regexp::Onig::Unicode.ranges decodes a table.
  def print_ranges
    names = literal("core/regexp/unicode_tables.rb", :PROPERTY_NAMES).split(" ")
    tables = literal("core/regexp/unicode_tables.rb", :PROPERTY_TABLES).unpack("w*")
    index = tables.fetch(names.index("print"))
    ends = literal("core/regexp/unicode_tables.rb", :RANGE_ENDS).unpack("w*")
    from = index.zero? ? 0 : ends[index - 1]
    last = -1
    literal("core/regexp/unicode_tables.rb", :RANGES).byteslice(from, ends[index] - from).unpack("w*").each_slice(2).map do |gap, span|
      low = last + gap + 1
      last = low + span
      [low, last]
    end
  end

  # The value of the constant `name` in `file`: a literal, so it reads
  # with no runtime.
  def literal(file, name)
    write = parse(file).breadth_first_search { |node| node.is_a?(Prism::ConstantWriteNode) && node.name == name }
    eval(write.value.slice)
  end

  def parse(file) = (@trees ||= {})[file] ||= Prism.parse_file(File.join(RUNTIME, file)).value

  # Sorted, joined ranges as `[first, last]` pairs.
  def merge(ranges)
    ranges.map { |range| [range.begin, range.exclude_end? ? range.end - 1 : range.end] }.sort.each_with_object([]) do |(low, high), out|
      if out.any? && low <= out.last[1] + 1
        out.last[1] = [out.last[1], high].max
      else
        out << [low, high]
      end
    end
  end

  # The pairs of `within` that no range covers.
  def complement(ranges, within)
    out = []
    at = within.begin
    merge(ranges).each do |low, high|
      next if high < at

      out << [at, low - 1] if low > at
      at = high + 1
    end
    out << [at, within.end] if at <= within.end
    out
  end

  def without_surrogates(pairs)
    pairs.flat_map do |low, high|
      [[low, [high, SURROGATES.begin - 1].min], [[low, SURROGATES.end + 1].max, high]].select { |a, b| a <= b }
    end
  end
end
