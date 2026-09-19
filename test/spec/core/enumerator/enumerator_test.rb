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
end
