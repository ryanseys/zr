# frozen_string_literal: true

require "spec_helper"

describe "Pack programs" do
  it "block call multi arg pack" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY', files: beside("computed_require/lib/greeter.rb", "computed_require/prog.rb"))
      # Without the flag the same program raises the LoadError it always did --
      # a hermetic binary is the default, not an accident.

      require_relative "computed_require/prog"
    RUBY

    _(result).must_answer "cannot load such file -- greeter\n"
  end

  it "each entry packs multi value yields where each passes them through" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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

    _(result).must_answer "1\n2\n"
  end

  it "poly user pack unpack" do
    result = zr(<<~'RUBY')
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
    it "every integer directive packs and unpacks the machine words and past them, a fixnum or not" do
      result = zr(<<~'RUBY')
        class Two
          def to_int = 2
        end
        values = [0, 1, -1, 127, 128, 255, 256, -128, -129, 65_535, -32_768, 2**31, -(2**31), 2**32 - 1, 2**62, -(2**62) - 1, 2**63, 2**64 - 1, -(2**63)]
        %w[C c S s L l Q q J j n N v V S> s> L> l> Q> q< L_ q!].each do |d|
          packed = values.pack("#{d}*")
          back = packed.unpack("#{d}*")
          puts "#{d.ljust(3)} #{packed.bytesize} #{packed.unpack1('H*')[0, 48]} #{back.first(8).inspect} #{back.last(3).inspect}"
        end
        p [1, 2.9, Two.new, 2**70, -3].pack("Q<5").unpack("Q<5")
        p [1, 2, 3].pack("S2")
        p "\x01\x02\x03".unpack("S2")
        p "\x01\x02\x03\x04\x05".unpack("L<3")
        p "\xff\xff\xff\xff\xff\xff\xff\xff".unpack("Q<q>C2")
        p "abc".unpack1("C", offset: 1)
        p (0..2000).to_a.pack("L<*").unpack("L<*").sum
        begin
          [1].pack("L2")
        rescue ArgumentError => e
          p e.message
        end
        begin
          [nil].pack("L")
        rescue TypeError => e
          p e.message
        end
      RUBY

      _(result).must_answer <<~'OUT'
        C   19 0001ff7f80ff00807fff000000ff00ff00ff00 [0, 1, 255, 127, 128, 255, 0, 128] [0, 255, 0]
        c   19 0001ff7f80ff00807fff000000ff00ff00ff00 [0, 1, -1, 127, -128, -1, 0, -128] [0, -1, 0]
        S   38 00000100ffff7f008000ff00000180ff7fffffff00800000 [0, 1, 65535, 127, 128, 255, 256, 65408] [0, 65535, 0]
        s   38 00000100ffff7f008000ff00000180ff7fffffff00800000 [0, 1, -1, 127, 128, 255, 256, -128] [0, -1, 0]
        L   76 0000000001000000ffffffff7f00000080000000ff000000 [0, 1, 4294967295, 127, 128, 255, 256, 4294967168] [0, 4294967295, 0]
        l   76 0000000001000000ffffffff7f00000080000000ff000000 [0, 1, -1, 127, 128, 255, 256, -128] [0, -1, 0]
        Q   152 00000000000000000100000000000000ffffffffffffffff [0, 1, 18446744073709551615, 127, 128, 255, 256, 18446744073709551488] [9223372036854775808, 18446744073709551615, 9223372036854775808]
        q   152 00000000000000000100000000000000ffffffffffffffff [0, 1, -1, 127, 128, 255, 256, -128] [-9223372036854775808, -1, -9223372036854775808]
        J   152 00000000000000000100000000000000ffffffffffffffff [0, 1, 18446744073709551615, 127, 128, 255, 256, 18446744073709551488] [9223372036854775808, 18446744073709551615, 9223372036854775808]
        j   152 00000000000000000100000000000000ffffffffffffffff [0, 1, -1, 127, 128, 255, 256, -128] [-9223372036854775808, -1, -9223372036854775808]
        n   38 00000001ffff007f008000ff0100ff80ff7fffff80000000 [0, 1, 65535, 127, 128, 255, 256, 65408] [0, 65535, 0]
        N   76 0000000000000001ffffffff0000007f00000080000000ff [0, 1, 4294967295, 127, 128, 255, 256, 4294967168] [0, 4294967295, 0]
        v   38 00000100ffff7f008000ff00000180ff7fffffff00800000 [0, 1, 65535, 127, 128, 255, 256, 65408] [0, 65535, 0]
        V   76 0000000001000000ffffffff7f00000080000000ff000000 [0, 1, 4294967295, 127, 128, 255, 256, 4294967168] [0, 4294967295, 0]
        S>  38 00000001ffff007f008000ff0100ff80ff7fffff80000000 [0, 1, 65535, 127, 128, 255, 256, 65408] [0, 65535, 0]
        s>  38 00000001ffff007f008000ff0100ff80ff7fffff80000000 [0, 1, -1, 127, 128, 255, 256, -128] [0, -1, 0]
        L>  76 0000000000000001ffffffff0000007f00000080000000ff [0, 1, 4294967295, 127, 128, 255, 256, 4294967168] [0, 4294967295, 0]
        l>  76 0000000000000001ffffffff0000007f00000080000000ff [0, 1, -1, 127, 128, 255, 256, -128] [0, -1, 0]
        Q>  152 00000000000000000000000000000001ffffffffffffffff [0, 1, 18446744073709551615, 127, 128, 255, 256, 18446744073709551488] [9223372036854775808, 18446744073709551615, 9223372036854775808]
        q<  152 00000000000000000100000000000000ffffffffffffffff [0, 1, -1, 127, 128, 255, 256, -128] [-9223372036854775808, -1, -9223372036854775808]
        L_  152 00000000000000000100000000000000ffffffffffffffff [0, 1, 18446744073709551615, 127, 128, 255, 256, 18446744073709551488] [9223372036854775808, 18446744073709551615, 9223372036854775808]
        q!  152 00000000000000000100000000000000ffffffffffffffff [0, 1, -1, 127, 128, 255, 256, -128] [-9223372036854775808, -1, -9223372036854775808]
        [1, 2, 2, 0, 18446744073709551613]
        "\x01\x00\x02\x00"
        [513, nil]
        [67305985, nil, nil]
        [18446744073709551615, nil, nil, nil]
        98
        2001000
        "too few arguments"
        "no implicit conversion of nil into Integer"
      OUT
    end
end
