# frozen_string_literal: true

require "spec_helper"

describe "Pack programs" do
  it "block call multi arg pack" do
    result = ze0(<<~'RUBY')
      # A block invoked through `block.call(a, b)` with MULTIPLE arguments packs
      # those arguments into an array for a collector that takes the block's value
      # as one object (`to_a`), and binds them across a destructuring block's
      # parameters -- exactly as `yield a, b` already does. Calling the block with
      # several arguments dropped all but the first, so an Enumerable whose #each
      # forwards through a &block parameter collected scalars where CRuby collects
      # pairs.
      #
      # Found porting tobi/try: its fuzzy matcher yields (entry, positions, score)
      # from an #each that forwards the caller's block, so `.to_a` silently lost the
      # positions and the score.
      class ViaCall
        include Enumerable
        def each(&block)
          block.call(1, 2)
          block.call(3, 4)
        end
      end

      # `yield` with the same arity, for contrast: this form already worked.
      class ViaYield
        include Enumerable
        def each
          yield 1, 2
          yield 3, 4
        end
      end

      p ViaCall.new.to_a
      p ViaYield.new.to_a

      # A single-argument call still passes its value through unwrapped.
      class Single
        include Enumerable
        def each(&block)
          block.call(1)
          block.call(2)
        end
      end
      p Single.new.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [3, 4]]
      [[1, 2], [3, 4]]
      [1, 2]
    OUT
  end

  it "computed require without the pack is a load error" do
    _(ze0(<<~'RUBY', files: {"a_computed_require_without_the_pack_is_a_load_error/lib/greeter.rb" => "module Greeter; end\n", "a_computed_require_without_the_pack_is_a_load_error/prog.rb" => "begin\n  require [\"greeter\", \"\"].first\nrescue LoadError => e\n  puts e.message\nend\n"})).must_answer "cannot load such file -- greeter\n"
      # Without the flag the same program raises the LoadError it always did --
      # a hermetic binary is the default, not an accident.

      require_relative "a_computed_require_without_the_pack_is_a_load_error/prog"
    RUBY
  end

  it "each entry packs multi value yields where each passes them through" do
    result = ze0(<<~'RUBY')
      # The entire difference between `each_entry` and `each`, and it is only
      # observable when the receiver's own `each` yields MORE THAN ONE value.

      class Multi
        include Enumerable
        def each
          yield 1
          yield 2, 3
          yield
        end
      end
      r = []
      Multi.new.each_entry { |x| r << x }
      p r
      s = []
      Multi.new.each { |x| s << x }
      p s
      p Multi.new.each_entry.to_a
      p [1, 2].each_entry.to_a
      h = []
      ({a: 1}).each_entry { |e| h << e }
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      [1, [2, 3], nil]
      [1, 2, nil]
      [1, [2, 3], nil]
      [1, 2]
      [[:a, 1]]
    OUT
  end

  it "enumerator new yields through a yielder with cruby packing" do
    result = ze0(<<~'RUBY')
      # `Enumerator.new { |y| ... }` -- the generator/Yielder pair, and the
      # packing truth table: `next_values` preserves yield arity exactly,
      # `next` collapses through ary2sv (`yield`->nil, `yield nil`->nil,
      # `yield 1,2`->[1,2], `yield [3,4]`->[3,4]); the block's return value is
      # the StopIteration result; `rewind` restarts from the top.

      g = Enumerator.new do |y|
        y.yield
        y.yield nil
        y.yield 1, 2
        y << [3, 4]
        :fin
      end
      p g.next_values
      p g.next_values
      p g.next_values
      p g.next_values
      g.rewind
      p g.next
      p g.next
      p g.next
      p g.next
      begin
        g.next
      rescue StopIteration => e
        p e.result
      end
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [nil]
      [1, 2]
      [[3, 4]]
      nil
      nil
      [1, 2]
      [3, 4]
      :fin
    OUT
  end

  it "hash each packs a pair only when the block takes one" do
    result = ze0(<<~'RUBY')
      # `Hash#each` yields two values to a block that can take two, and packs them
      # into one array only for a block that cannot -- `rb_hash_foreach`'s own rule.
      # Every shape below decides that question differently, and the lambda case is
      # load-bearing: CRuby raises ArgumentError there PRECISELY because a lambda
      # receives the packed pair as one argument.
      h = { a: 1, b: 2 }
      out = []
      h.each { |pair| out << [:one, pair] }
      h.each { |k, v| out << [:two, k, v] }
      h.each { |*a| out << [:splat, a] }
      h.each { |k, *r| out << [:k_rest, k, r] }
      h.each { |k, v, *r| out << [:kv_rest, k, v, r] }
      h.each { out << [:none] }
      h.each { |k, v, w| out << [:three, k, v, w] }
      out.each { |r| p r }
      p h.map { |k, v| "#{k}#{v}" }
      p h.map { |pair| pair.class }
      p h.select { |k, v| v > 1 }
      p h.count { |k, v| v > 0 }
      p h.each_with_object([]) { |(k, v), acc| acc << k }
      p h.to_a
      begin
        h.each(&->(k, v) { out << [:lambda, k, v] })
        p :lambda_ok
      rescue => e
        p [:lambda_err, e.class]
      end
      p out.last
      begin
        p h.each(&:class)
      rescue => e
        p [:sym_err, e.class]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:one, [:a, 1]]
      [:one, [:b, 2]]
      [:two, :a, 1]
      [:two, :b, 2]
      [:splat, [[:a, 1]]]
      [:splat, [[:b, 2]]]
      [:k_rest, :a, [1]]
      [:k_rest, :b, [2]]
      [:kv_rest, :a, 1, []]
      [:kv_rest, :b, 2, []]
      [:none]
      [:none]
      [:three, :a, 1, nil]
      [:three, :b, 2, nil]
      ["a1", "b2"]
      [Array, Array]
      {b: 2}
      2
      [:a, :b]
      [[:a, 1], [:b, 2]]
      [:lambda_err, ArgumentError]
      [:three, :b, 2, nil]
      {a: 1, b: 2}
    OUT
  end

  it "multiple yield args pack into an array for the resumer" do
    result = ze0(<<~'RUBY')
      # Asserted via `puts` (an Array prints one element per line, matching
      # real ruby) rather than `v.length`/`v[0]`: `resume`'s result is
      # statically Poly, and collection methods on a Poly value are the
      # PRE-existing Poly-dispatch gap, nothing fiber-specific.

      m = Fiber.new do
        Fiber.yield(1, 2)
        :fin
      end
      v = m.resume
      puts v
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
    OUT
  end

  it "poly user pack unpack" do
    result = ze0(<<~'RUBY')
      # The poly-receiver arms for `pack` and `unpack1` did not ask whether a user
      # class owns the name, the way their neighbours do. `pack` answered "" and
      # `unpack1` read the receiver through a char * whatever it held -- both
      # silently, neither entering the method (#4071's shape, found by sweeping the
      # poly arms for the guard).
      class Frame
        def initialize
          @packed = 0
        end

        attr_reader :packed

        def pack(fmt)
          @packed += 1
          "frame:" + fmt
        end
      end

      class Wire
        def unpack1(fmt)
          "wire:" + fmt
        end
      end

      def packed(v) = v.pack("C*")
      def first_of(v) = v.unpack1("C")

      f = Frame.new
      p packed(f)
      p f.packed
      p packed([65, 66])
      p packed([1.5])

      p first_of(Wire.new)
      p first_of("AB")

      # and with no user class in sight the plain lowering is unchanged
      p [65, 66].pack("C*")
      p "AB".unpack1("C")
      p "AB".unpack1("a")
    RUBY

    _(result).must_answer <<~'OUT'
      "frame:C*"
      1
      "AB"
      "\x01"
      "wire:C"
      65
      "AB"
      65
      "A"
    OUT
  end
end
