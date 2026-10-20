# frozen_string_literal: true

require "test_helper"
require "zr/parse"

# Zr::LineCursor answers each line lookup as a scan of the line starts
# does (lib/zr/line_cursor.rb), in any order of offsets.
class LineCursorTest < Minitest::Test
  SOURCE = "a = 1\n\nb = [\n  2,\n  3\n]\n# end\nputs a + b.sum".b

  def lines(source, offsets)
    offsets.map { |offset| source.line(offset) }
  end

  def test_every_offset_in_any_order_gets_prisms_line
    source = Prism.parse(SOURCE).source
    frozen = Prism::Source.for(SOURCE.dup, 1, source.offsets.dup).freeze # frozen: no cursor
    offsets = (0...SOURCE.bytesize).to_a

    [offsets, offsets.reverse, offsets.shuffle(random: Random.new(7))].each do |order|
      scanned = order.map { |offset| source.offsets.rindex { |start| start <= offset } + 1 }
      assert_equal scanned, lines(source, order)
      assert_equal scanned, lines(frozen, order)
    end
  end

  def test_a_source_that_starts_at_a_later_line_counts_from_it
    source = Prism.parse(SOURCE, line: 10).source

    assert_equal [10, 12, 17], lines(source, [0, 7, SOURCE.bytesize - 1])
  end
end
