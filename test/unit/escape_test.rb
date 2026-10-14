# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# Tests `Hir::Escape`: which uses of a `&b` parameter let it stay a raw
# block, and which uses need the Proc value.
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
    # The builder evaluates `defined?` of a local itself.
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

  # Uses of a `*a` or `**k` that copy it into a new Array or Hash.
  SPREAD = {
    "a send's splat" => "g(*a)",
    "a send's double splat" => "g(**k)",
    "both, with more arguments" => "g(1, *a, 2, **k, x: 3)",
    "a splat to self" => "self.g(*a)",
    "a splat in a send's receiver" => "g(*a).size",
    "a super" => "super(*a, **k)",
    "a bare super" => "super",
    "a yield" => "yield(*a, **k)",
    "an array literal" => "[0, *a]",
    "a hash literal" => "{ x: 1, **k }",
    "a splat in a block" => "xs.each { g(*a) }",
    "a block's own a" => "xs.each { |a| a << 1 }",
    "a def inside cannot reach it" => "def inner(a) = a << 1",
    "another primitive" => "Primitive.zr_x(xs)",
    "a primitive's other argument" => "Primitive.arg!(:x)",
    "a primitive that reads the length" => "Primitive.zr_ary_len_m(a) + Primitive.zr_hash_len_m(k)",
    # `*a` on the right is an Array literal.
    "a splat assignment" => "x = *a",
    "a multiple assignment" => "x, y = *a",
    # The builder answers `defined?` of an assignment itself.
    "defined?" => "defined?(@x = a)"
  }.freeze

  # Uses that read or keep the Array or Hash itself.
  READ = {
    "read alone" => "a",
    "stored" => "@a = a",
    "returned" => "return k",
    "an argument" => "g(a)",
    "the receiver" => "a.size",
    "written to" => "a << 1",
    "an index" => "a[0] = 1",
    "a keyword read" => "k[:x]",
    "written over" => "a = []",
    "a primitive's splat" => "Primitive.zr_x(*a)",
    "a primitive's argument by name" => "Primitive.arg!(:a)",
    "a length primitive with more arguments" => "Primitive.zr_ary_len_m(a, k)",
    "a when splat" => "case 1 when *a then 2 end",
    "a block pass" => "g(&a)",
    "read in a block" => "xs.each { a.size }",
    "kept by a lambda" => "-> { a }",
    "a splat of a call on it" => "g(*a.dup)"
  }.freeze

  SPREAD.each do |name, body|
    define_method("test_#{name.tr(" ", "_")}_only_spreads") { assert spread_only?(body), body }
  end

  READ.each do |name, body|
    define_method("test_#{name.tr(" ", "_")}_reads_the_rest") { refute spread_only?(body), body }
  end

  # A keyword's default is read after the rest is bound, so it counts.
  def test_a_keyword_default_counts
    refute spread_only?("g(*a)", "def f(*a, x: a, **k)")
  end

  RAW.each do |name, body|
    define_method("test_#{name.tr(" ", "_")}_stays_raw") { assert raw?(body), body }
  end

  KEPT.each do |name, body|
    define_method("test_#{name.tr(" ", "_")}_keeps_the_proc") { refute raw?(body), body }
  end

  # A default cannot refer to the block parameter: it is declared after
  # all other parameters, so `b` in a default is a method call.
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

  # Whether the def spreads both its `*a` and its `**k` only.
  def spread_only?(body, head = "def f(*a, **k)")
    d = def_of("#{head}\n#{body}\nend")
    defaults = d.params.defaults
    %i[a k].all? { |name| Zr::Hir::Escape.spread_only?([d.body, *defaults], name) }
  end

  # Returns the one Def in the program `source`.
  def def_of(source)
    program = Zr::Hir.build(source, "escape.rb")
    find = lambda do |node|
      return node if node.is_a?(Zr::Hir::Def)

      children = case node
                 when Zr::Hir::Node then node.to_a
                 when Array then node
                 else []
                 end
      children.each { |v| (d = find.call(v)) and return d }
      nil
    end
    find.call(program.body) or raise "no def in #{source}"
  end
end
