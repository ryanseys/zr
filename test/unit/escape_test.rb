# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# `Hir::Escape`: which uses of a `&b` parameter let it stay the block
# it was given, and which keep its value.
class EscapeTest < Minitest::Test
  RAW = {
    "call" => "b.call(1, 2)",
    "safe call" => "b&.call(x)",
    "call with keywords and a splat" => "b.call(*xs, k: 1)",
    "forward" => "each(&b)",
    "forward to super" => "super(&b)",
    "bare super" => "super",
    "if" => "if b then 1 else 2 end",
    "unless" => "3 unless b",
    "and" => "b && b.call",
    "or in a test" => "if b || x then 1 end",
    "not" => "!b",
    "while" => "while b do break end",
    "ternary" => "b ? b.call : nil",
    "and as a value" => "y = b && 1",
    "call inside a block" => "xs.each { |x| b.call(x) }",
    "forward inside a block" => "xs.each { |x| g(x, &b) }",
    "call inside a lambda" => "-> { b.call }",
    "call inside a nested block" => "xs.each { ys.each { b.call } }",
    "the same name in a block of its own" => "xs.each { |b| b.arity }",
    "a def inside cannot reach it" => "def inner(b) = b.arity",
    "a singleton class body cannot reach it" => "class << self; b = 1; b.arity; end",
    # The builder answers `defined?` of a local itself.
    "asked defined?" => "defined?(b)",
    "a block with a default reading it" => "xs.each { |x = b.call| x }",
    "other locals" => "c = b.call; d = c; [c, d]"
  }.freeze

  KEPT = {
    "stored" => "@b = b",
    "returned" => "return b",
    "an argument" => "g(b)",
    "a splat" => "g(*b)",
    "the receiver of another method" => "b.arity",
    "the receiver of call with a block" => "b.call { 1 }",
    "a case subject" => "case b when Proc then 1 end",
    "or as a value" => "c = b || nil",
    "written over" => "b = nil",
    "interpolated" => '"#{b}"',
    "a local read alone" => "b",
    "yielded" => "yield b",
    "an array element" => "[b]",
    "stored from inside a block" => "xs.each { |x| @b = b }",
    "read from a lambda as a value" => "-> { b }",
    "a block parameter default keeping it" => "xs.each { |x = b| x }",
    "a call through a nested block's own name and ours" => "xs.each { |c| b.arity }"
  }.freeze

  RAW.each do |name, body|
    define_method("test_#{name.tr(' ', '_')}_stays_raw") { assert raw?(body), body }
  end

  KEPT.each do |name, body|
    define_method("test_#{name.tr(' ', '_')}_keeps_the_proc") { refute raw?(body), body }
  end

  # A default cannot name the block parameter: it is declared after
  # every other, so `b` in a default is a call.
  def test_a_default_expression_cannot_reach_it
    assert raw?("x", "def f(x = b, &b)")
  end

  def test_an_anonymous_block_forwards_raw
    d = def_of("def f(&) = g(&)")
    assert Zr::Hir::Escape.raw_block?(d.body, d.params.block)
  end

  private

  def raw?(body, head = "def f(x = 1, &b)")
    d = def_of("#{head}\n#{body}\nend")
    defaults = d.params.optional.map(&:last)
    Zr::Hir::Escape.raw_block?([d.body, *defaults], :b)
  end

  # The one Def a program of `source` holds.
  def def_of(source)
    program = Zr::Hir.build(source, "escape.rb")
    find = lambda do |node|
      return node if node.is_a?(Zr::Hir::Def)

      node.is_a?(Zr::Record) ? node.to_a.each { |v| (d = find.call(v)) and return d } && nil : node.is_a?(Array) ? node.each { |v| (d = find.call(v)) and return d } && nil : nil
    end
    find.call(program.body) or raise "no def in #{source}"
  end
end
