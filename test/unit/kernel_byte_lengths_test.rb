# frozen_string_literal: true

require "test_helper"
require "prism"

# A kernel call that takes a literal's bytes and its length,
# `zr_buf_push(b, Machine.bytes("text"), 4)`, must give the literal's
# true length: one too many writes the NUL after it, and one too few
# loses the last byte.
class KernelByteLengthsTest < Minitest::Test
  RUNTIME = File.expand_path("../../lib/zr/runtime", __dir__)

  def test_each_literal_length_is_the_literals_bytesize
    wrong = Dir[File.join(RUNTIME, "kernel/**/*.rb")].sort.flat_map { |path| wrong_lengths(path) }

    assert_empty wrong
  end

  # Each `Machine.bytes("...")` argument with an Integer literal right
  # after it whose value is not the literal's byte count.
  def wrong_lengths(path)
    found = []
    Prism.parse_file(path).value.breadth_first_search do |node|
      next false unless node.is_a?(Prism::CallNode) && node.arguments

      node.arguments.arguments.each_cons(2) do |text, length|
        next unless literal_bytes?(text) && length.is_a?(Prism::IntegerNode)

        bytes = text.arguments.arguments.first.unescaped
        next if bytes.bytesize == length.value

        found << "#{path.delete_prefix("#{RUNTIME}/")}:#{text.location.start_line}: #{bytes.inspect} is #{bytes.bytesize} bytes, not #{length.value}"
      end
      false
    end
    found
  end

  def literal_bytes?(node)
    node.is_a?(Prism::CallNode) && node.name == :bytes && node.receiver.is_a?(Prism::ConstantReadNode) &&
      node.receiver.name == :Machine && node.arguments&.arguments&.first.is_a?(Prism::StringNode)
  end
end
