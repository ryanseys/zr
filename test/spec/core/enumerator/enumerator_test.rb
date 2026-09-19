# frozen_string_literal: true

require "spec_helper"

describe "Enumerator" do
  it "gives an enumerator the count its receiver keeps" do
    result = ze0(<<~'RUBY')
      # Every Enumerable method that answers one element an element hands
      # its enumerator the receiver's own count, so `size` answers without
      # walking anything (enum.c, `enum_size`). A receiver with no count to
      # give leaves the enumerator's unknown.
      r = (1..4)
      %i[map collect select filter find_all reject filter_map flat_map
         collect_concat partition group_by sort_by min_by max_by minmax_by
         each_with_index reverse_each each_entry chunk].each do |name|
        print r.public_send(name).size
      end
      puts
      p r.each_with_object([]).size

      class Sizeless
        include Enumerable
        def each = block_given? ? (yield 1) : to_enum(:each)
      end
      p Sizeless.new.map.size
    RUBY

    _(result).must_answer <<~'OUT'
      4444444444444444444
      4
      nil
    OUT
  end

  it "reaches a size the receiver keeps private, and takes what it answers" do
    result = ze0(<<~'RUBY')
      # `enum_size` asks with rb_check_funcall, which calls a method the
      # receiver keeps private and takes whatever comes back as it stands.
      class Quiet
        include Enumerable
        def each = block_given? ? (yield 1) : to_enum(:each)
        private def size = 99
      end

      class Odd
        include Enumerable
        def each = block_given? ? (yield 1) : to_enum(:each)
        def size = "nine"
      end

      p Quiet.new.map.size
      p Odd.new.map.size
    RUBY

    _(result).must_answer <<~'OUT'
      99
      "nine"
    OUT
  end

  it "counts a cycle by the rounds it was asked for" do
    result = ze0(<<~'RUBY')
      # `enum_cycle_size`: endlessly where no round was named, none where
      # the rounds are none or fewer, and otherwise the count times the
      # rounds. A Struct reaches Enumerable's own cycle and inspects the
      # same way twice, which a plain object does not.
      Trio = Struct.new(:a, :b, :c)
      t = Trio.new(1, 2, 3)

      p t.cycle.size
      p t.cycle(2).size
      p t.cycle(0).size
      p t.cycle(-1).size
      p t.map.size
    RUBY

    _(result).must_answer <<~'OUT'
      Infinity
      6
      0
      0
      3
    OUT
  end

  it "names only the arguments the call was given" do
    result = ze0(<<~'RUBY')
      # `rb_scan_args` then RETURN_SIZED_ENUMERATOR(obj, argc, argv): what
      # an enumerator names is what the caller wrote, so a default that was
      # never passed is not one of them.
      Trio = Struct.new(:a, :b, :c)
      t = Trio.new(1, 2, 3)

      p t.cycle.inspect
      p t.cycle(2).inspect
      p t.min_by.inspect
      p t.min_by(2).inspect
      p t.max_by.inspect
      p t.max_by(2).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "#<Enumerator: #<struct Trio a=1, b=2, c=3>:cycle>"
      "#<Enumerator: #<struct Trio a=1, b=2, c=3>:cycle(2)>"
      "#<Enumerator: #<struct Trio a=1, b=2, c=3>:min_by>"
      "#<Enumerator: #<struct Trio a=1, b=2, c=3>:min_by(2)>"
      "#<Enumerator: #<struct Trio a=1, b=2, c=3>:max_by>"
      "#<Enumerator: #<struct Trio a=1, b=2, c=3>:max_by(2)>"
    OUT
  end

  it "asks the object to start again when it rewinds" do
    result = ze0(<<~'RUBY')
      # `enumerator_rewind` calls the object's own `rewind` with
      # rb_check_funcall: anything that knows how to start again is told
      # to, one that does not is left alone, and a private one is reached
      # all the same.
      class Counted
        include Enumerable
        attr_reader :rewound
        def initialize = @rewound = 0
        def rewind = @rewound += 1
        def each = block_given? ? (yield 1) : to_enum(:each)
      end

      class Quietly
        include Enumerable
        attr_reader :rewound
        def initialize = @rewound = 0
        private def rewind = @rewound += 1
        def each = block_given? ? (yield 1) : to_enum(:each)
      end

      counted = Counted.new
      e = counted.each
      e.next
      e.rewind
      p counted.rewound
      p e.next

      quiet = Quietly.new
      quiet.each.rewind
      p quiet.rewound

      p [1, 2].each.rewind.next
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      1
      1
    OUT
  end
  it "keeps what a lazy stage owes its neighbours" do
    result = ze0(<<~'RUBY')
      # map, select, reject and filter_map go through the kernel's
      # adapter (zr_lazy_stage) rather than a `|*values|` block, which
      # allocated that Array once an element and once a stage. These
      # are what the adapter owes: the block sees the values unpacked,
      # what a stage sends on is the element packed, and the block is
      # called after the call that took it has returned.
      class Several
        include Enumerable
        def each
          yield 1, 2
          yield 3
          yield
          yield 4, 5, 6
          self
        end
      end

      p Several.new.lazy.map { |a| a }.force
      p Several.new.lazy.map { |a, b| [a, b] }.force
      p Several.new.lazy.select { true }.force
      p Several.new.lazy.reject { false }.force
      p Several.new.lazy.filter_map { |a| a }.force

      # A `break` in a lazy block has nothing to break out of.
      begin
        (1..5).lazy.map { |x| break :broke if x == 3; x }.force
      rescue LocalJumpError => e
        p [e.reason, e.message]
      end

      # A lambda is held to its arity where an ordinary block is not.
      begin
        { a: 1 }.lazy.map(&->(a, b) { a }).force
      rescue ArgumentError => e
        p e.message
      end
      p({ a: 1, b: 2 }.lazy.map { |k| k }.force)

      # nil and false are what filter_map drops and map keeps.
      p (1..3).lazy.filter_map { |x| x.odd? && x }.force
      p (1..3).lazy.map { |x| nil }.force

      # The walk stops where the consumer stops, endlessly.
      p (1..Float::INFINITY).lazy.map { |x| x * 3 }.select(&:even?).first(4)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3, nil, 4]
      [[1, 2], [3, nil], [nil, nil], [4, 5]]
      [[1, 2], 3, nil, [4, 5, 6]]
      [[1, 2], 3, nil, [4, 5, 6]]
      [1, 3, 4]
      [:break, "break from proc-closure"]
      "wrong number of arguments (given 1, expected 2)"
      [[:a, 1], [:b, 2]]
      [1, 3]
      [nil, nil, nil]
      [6, 12, 18, 24]
    OUT
  end

  it "walks with an index without an Array an element" do
    result = ze0(<<~'RUBY')
      # with_index, each_with_index and with_object pack what `each` yields
      # as rb_enum_values_pack packs it -- one value through, several as an
      # Array, none as nil -- put the index or the memo beside it, and hand
      # the block's own answer back to `each`, which is what each of the
      # three answers in turn.
      a = [1, 2, 3]
      p a.each.with_index { |x, i| }
      p a.map.with_index { |x, i| x * 2 }
      p a.each_with_index.with_index { |(x, i), j| }
      p a.each.with_index(5).to_a
      p({ x: 1, y: 2 }.each.with_index { |(k, v), i| p [k, v, i] })
      p a.each.with_object(:m) { |x, m| }
      p a.each.each_with_index { |x, i| }
      p [[1, 2], [3, 4]].each.with_index { |v, i| p [v, i] }
      p [].each.with_index { |x, i| }
      e = Enumerator.new { |y| y.yield(1, 2); y << 3 }
      e.with_index { |v, i| p [v, i] }
      p e.with_object([]) { |v, m| m << v }
      p a.each.with_index.to_a
      p a.map.with_index { |x, i| i }
      p a.select.with_index { |x, i| i > 0 }
      p a.each_slice(2).with_index { |s, i| p [s, i] }
      p({ x: 1 }.each_pair.with_object({}) { |(k, v), m| m[k] = v })
      p a.each_with_object([]) { |x, m| m << x }
      p a.each.with_index(-2).to_a
      idx = a.map.with_index(10) { |x, i| [x, i] }
      p idx
      p a.each.with_index { |x, i| next :skip if i.zero?; x }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [2, 4, 6]
      [1, 2, 3]
      [[1, 5], [2, 6], [3, 7]]
      [:x, 1, 0]
      [:y, 2, 1]
      {x: 1, y: 2}
      :m
      [1, 2, 3]
      [[1, 2], 0]
      [[3, 4], 1]
      [[1, 2], [3, 4]]
      []
      [[1, 2], 0]
      [3, 1]
      [[1, 2], 3]
      [[1, 0], [2, 1], [3, 2]]
      [0, 1, 2]
      [2, 3]
      [[1, 2], 0]
      [[3], 1]
      [1, 2, 3]
      {x: 1}
      [1, 2, 3]
      [[1, -2], [2, -1], [3, 0]]
      [[1, 10], [2, 11], [3, 12]]
      [1, 2, 3]
    OUT
  end
end
