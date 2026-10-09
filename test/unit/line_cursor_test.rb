# frozen_string_literal: true

require "test_helper"
require "zr/prism"

# Zr::LineCursor answers each line lookup as prism's binary search does
# (lib/zr/line_cursor.rb), in any order of offsets.
class LineCursorTest < Minitest::Test
  SOURCE = "a = 1\n\nb = [\n  2,\n  3\n]\n# end\nputs a + b.sum".b

  def lines(source, offsets)
    offsets.map { |offset| source.line(offset) }
  end

  def test_every_offset_in_any_order_gets_prisms_line
    source = Prism.parse(SOURCE).source
    plain = Prism::Source.for(SOURCE.dup, 1, source.offsets.dup).freeze # frozen: no cursor, prism's own search
    offsets = (0...SOURCE.bytesize).to_a

    [offsets, offsets.reverse, offsets.shuffle(random: Random.new(7))].each do |order|
      assert_equal lines(plain, order), lines(source, order)
    end
  end

  def test_a_source_that_starts_at_a_later_line_counts_from_it
    source = Prism.parse(SOURCE, line: 10).source

    assert_equal [10, 12, 17], lines(source, [0, 7, SOURCE.bytesize - 1])
  end
end
