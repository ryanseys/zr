# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"
require_relative "../../lib/zr/lower"

# An operator site takes the one-operand fast path only for the argument
# it writes: a splat may spread no element or several, so the send must
# count them (`a.+(*rest)`).
class OperatorSpreadTest < Minitest::Test
  def test_a_written_operand_is_fixed
    assert fixed?("a.+(b)")
    assert fixed?("a <=> b")
    assert fixed?("a.between?(b, c)")
  end

  def test_a_splat_is_not_fixed
    refute fixed?("a.+(*rest)")
    refute fixed?("a.<=>(*rest)")
    refute fixed?("a.between?(*rest, c)")
  end

  def test_keywords_are_not_fixed
    refute fixed?("a.+(b, key: 1)")
    refute fixed?("a.+(**opts)")
  end

  private

  def fixed?(call)
    program = Zr::Hir.build("a = b = c = rest = opts = nil\n#{call}\n", "spread.rb")
    sends = []
    collect(program.body, sends)
    sender = Object.new.extend(Zr::Lower::Function::Sends)
    sender.send(:fixed_args?, sends.last)
  end

  def collect(node, out)
    case node
    when Array then node.each { |n| collect(n, out) }
    when Zr::Hir::Node
      node.to_a.each { |field| collect(field, out) }
      out << node if node.is_a?(Zr::Hir::Send)
    end
  end
end
