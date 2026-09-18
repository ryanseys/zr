# frozen_string_literal: true

require "spec_helper"

describe "Enumerable programs" do
  it "autoload is lazy" do
    result = ze0(<<~'RUBY', files: {"autoload_fixture/late.rb" => "puts \"  late.rb body ran\"\nmodule AL\n  LOADED_AT = \"body\"\n  class Late\n    def self.hi = \"hi\"\n  end\nend\n"})
      # `Module#autoload` runs its target at the DECLARATION, where ruby runs it at
      # the constant's first READ.
      #
      # The cause is not the declaration row -- it is what a lazy unit registers.
      # `parse::loader` compiles a literal `autoload :C, "feature"` target in as a
      # lazy unit and keeps the call, and `builtins::rmodule`'s `autoload` row loads
      # that unit right there. Moving the load to the read is not enough on its own:
      # a lazy unit's CLASSES and their methods are in the dispatch tables from
      # startup, so `AL::Late.hi` answers before the unit has ever run and no miss
      # is left for a read hook to catch. Only the constants a unit's BODY assigns
      # (`AL::LOADED_AT` below) actually miss. Making autoload lazy therefore means
      # holding a lazy unit's class registrations back until its unit runs, not
      # adding a hook at the constant read.
      #
      # Measured cost, while it was broken: this was one of the things that blocked
      # `require "rubygems"`, so `tests/bench/rubygems.rb` and `bundler.rb` entered
      # at sub-files instead. With the declaration eager, `rubygems.rb`'s `autoload
      # :RequestSet` ran `request_set/gem_dependency_api.rb` before
      # `rubygems/platform` was required, and died on `uninitialized constant
      # Gem::Platform`. Both bench programs enter at the umbrella now.
      $LOAD_PATH.unshift(File.expand_path("autoload_fixture", __dir__))

      puts "before the module"
      module AL
        puts "  module body, before the autoload"
        autoload :Late, File.expand_path("autoload_fixture/late.rb", __dir__)
        puts "  module body, after the autoload"
      end
      puts "after the module"

      # Ruby has run nothing yet, and says so.
      p AL.autoload?(:Late)&.end_with?("late.rb")
      p AL.const_defined?(:Late)
      p defined?(AL::LOADED_AT)

      puts "first read"
      p AL::Late.hi
      p AL::LOADED_AT
      # Once the feature has loaded, ruby answers nil.
      p AL.autoload?(:Late)
    RUBY

    _(result).must_answer <<~'OUT'
      before the module
        module body, before the autoload
        module body, after the autoload
      after the module
      true
      true
      nil
      first read
        late.rb body ran
      "hi"
      "body"
      nil
    OUT
  end

  it "autoload lazy at declaration" do
    result = ze0(<<~'RUBY', files: {"autoload_lazy/differ.rb" => "module Outer\n  module Foo\n    class Differ\n      ORIGIN = Outer::Foo.tag(\"differ\")\n      def self.origin = ORIGIN\n    end\n  end\nend\n"})
      # An `autoload` target no longer loads BEFORE the statement holding it:
      # differ.rb calls a singleton method this module body installs a few
      # statements earlier (rspec-support's exact shape) -- the old eager splice
      # hoisted the target's body ahead of the whole `module` statement, so the
      # helper did not exist yet and the load raised NoMethodError.
      #
      # The target now runs at the constant's first ACCESS, as CRuby's does --
      # see `autoload_is_lazy.rb`. The divergence this header used to record is
      # gone; the shape is kept because it is the one the eager splice broke.
      module Outer
        module Foo
          puts "body-1"
          def self.tag(x) = "tagged #{x}"
          autoload :Differ, "#{__dir__}/autoload_lazy/differ"
          puts "body-2"
        end
      end
      puts Outer::Foo::Differ.origin
    RUBY

    _(result).must_answer <<~'OUT'
      body-1
      body-2
      tagged differ
    OUT
  end

  it "blocked consumer is woken by a producer thread" do
    result = ze0(<<~'RUBY')
      # The consumer genuinely BLOCKS on the empty pop (a Condvar wait) and is
      # woken by the producer's push -- exercising the real cross-thread wakeup
      # path. The value is deterministic regardless of which thread runs first.

      q = Queue.new
      consumer = Thread.new { q.pop }
      producer = Thread.new { q.push 42 }
      puts consumer.value
      producer.join
    RUBY

    _(result).must_answer "42\n"
  end

  it "dir each child enumerator" do
    result = ze0(<<~'RUBY')
      require "tmpdir"

      Dir.mktmpdir do |d|
        File.write(File.join(d, "a.txt"), "x")
        p Dir.each_child(d).to_a
        p Dir.foreach(d).to_a.sort
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["a.txt"]
      [".", "..", "a.txt"]
    OUT
  end

  it "dir for fd and enumerable" do
    result = ze0(<<~'RUBY')
      # `Dir.for_fd` is not implemented, so the program dies on line 9 before any of
      # the Enumerable-on-Dir coverage below it runs. ruby opens a Dir handle from a
      # raw file descriptor.
      # Dir.for_fd's handle lists through the descriptor (it has no path), and Dir's
      # Enumerable surface routes through #entries.
      d = "spinel_dir_suite"
      Dir.mkdir(d) unless Dir.exist?(d)
      File.write(File.join(d, "a.txt"), "a")
      File.write(File.join(d, "b.txt"), "b")

      h = Dir.new(d)
      w = Dir.for_fd(h.fileno)
      p w.path
      p w.children.sort
      p w.entries.sort

      n = Dir.new(d)
      p n.to_a.sort
      p n.select { |e| e.end_with?(".txt") }.sort
      p n.sort
      p n.count
      p n.include?("a.txt")
      p n.map { |e| e.upcase }.sort
      p n.reject { |e| e.start_with?(".") }.sort
      n.close
      h.close

      p Dir.new(d).path
      File.delete(File.join(d, "a.txt"))
      File.delete(File.join(d, "b.txt"))
      Dir.rmdir(d)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      ["a.txt", "b.txt"]
      [".", "..", "a.txt", "b.txt"]
      [".", "..", "a.txt", "b.txt"]
      ["a.txt", "b.txt"]
      [".", "..", "a.txt", "b.txt"]
      4
      true
      [".", "..", "A.TXT", "B.TXT"]
      ["a.txt", "b.txt"]
      "spinel_dir_suite"
    OUT
  end

  it "enumerable breadth" do
    result = ze0(<<~'RUBY')
      # Enumerable chunking/slicing and Array combinatorics/search.
      #
      # Everything here is driven by the receiver's own `each`, so it works the
      # same on an Array, a Range, or a user class that includes Enumerable --
      # which the last section shows.

      # --- chunk_while / slice_when ----------------------------------------------
      # Exact negations of each other: both walk adjacent pairs and cut between
      # them, `chunk_while` when the block is false, `slice_when` when it's true.
      runs = [1, 2, 4, 9, 10, 11, 12, 15]
      p runs.chunk_while { |i, j| i + 1 == j }.to_a
      p runs.slice_when { |i, j| i + 1 != j }.to_a
      p [1, 1, 2, 3, 3].chunk_while { |i, j| i == j }.to_a

      # No adjacent pair means the block never runs.
      p [].chunk_while { |i, j| true }.to_a
      p [7].chunk_while { |i, j| true }.to_a

      # --- slice_before / slice_after --------------------------------------------
      # `before` puts the match at the START of the next slice, `after` at the END
      # of the current one.
      p [1, 2, 3, 4, 5].slice_before { |x| x.even? }.to_a
      p [1, 2, 3, 4, 5].slice_after { |x| x.even? }.to_a

      # A match at the very start opens the first slice -- it does not close an
      # empty one.
      p [1, 2, 3].slice_before { |x| x == 1 }.to_a

      # Both also take a PATTERN instead of a block, matched with `===`.
      p [1, 2, 3, 4, 5].slice_before(3).to_a
      p [1, 2, 3, 4, 5].slice_after(3).to_a
      p ["a", "b1", "c"].slice_before(/\d/).to_a

      # --- grep / grep_v ---------------------------------------------------------
      # Also `===`, so a Range covers, a Class checks is_a?, a Regexp matches.
      p (1..10).grep(3..5)
      p [1, "a", 2, "b"].grep(Integer)
      p ["apple", "banana", "cherry"].grep(/an/)
      p [1, "a", 2, "b"].grep_v(Integer)

      # A block maps the survivors.
      p [1, "a", 2, "b"].grep(Integer) { |x| x * 10 }
      p [1, "a", 2, "b"].grep_v(Integer) { |x| x.upcase }

      # --- zip -------------------------------------------------------------------
      p [1, 2, 3].zip([4, 5, 6])
      p [1, 2, 3].zip([4, 5], [6])      # short others pad with nil
      p [1, 2].zip([3, 4], [5, 6])
      p([1, 2].zip([3, 4]) { |pair| })  # the block form answers nil

      # --- minmax_by -------------------------------------------------------------
      p [1, 2, 3, 4].minmax_by { |x| -x }
      p ["a", "bbb", "cc"].minmax_by { |s| s.length }
      p [].minmax_by { |x| x }          # a nil PAIR, not []

      # --- Array combinatorics ---------------------------------------------------
      p [1, 2, 3].combination(2).to_a
      p [1, 2, 3].combination(0).to_a   # one EMPTY tuple...
      p [1, 2, 3].combination(4).to_a   # ...but none at all past the length
      p [1, 2, 3].permutation(2).to_a
      p [1, 2].permutation.to_a         # no argument = full length

      # The block form yields each tuple.
      picked = []
      [1, 2, 3].combination(2) { |c| picked << c.sum }
      p picked

      # --- bsearch ---------------------------------------------------------------
      # Find-minimum mode: the array is sorted so every false precedes every true,
      # and the answer is the first true.
      sorted = [1, 2, 3, 4, 5]
      p sorted.bsearch { |x| x >= 3 }
      p sorted.bsearch { |x| x >= 99 }  # nil when nothing matches
      p sorted.bsearch_index { |x| x >= 3 }

      # --- cycle -----------------------------------------------------------------
      p [1, 2, 3].cycle(2).to_a
      p [1, 2].cycle(0).to_a
      seen = []
      [1, 2].cycle(2) { |x| seen << x }
      p seen

      # With no count `cycle` repeats forever, so it only ends via `break`.
      count = 0
      [1, 2].cycle do |x|
        count += 1
        break if count == 5
      end
      p count

      # --- the destructive forms -------------------------------------------------
      # `flatten!` answers nil when nothing changed; `sort_by!` always answers the
      # receiver.
      p [[1, [2, 3]], [4]].flatten!
      p [1, 2].flatten!
      nested = [1, [2, [3, [4]]]]
      p nested.flatten!(1)
      ordered = [3, 1, 2]
      ordered.sort_by! { |x| -x }
      p ordered

      # --- values_at / each_index ------------------------------------------------
      p [1, 2, 3].values_at(0, 2, 5)     # out of bounds is nil, not skipped
      p [1, 2, 3].values_at(-1, -3)
      p [1, 2, 3].values_at(0..1)
      p [1, 2, 3, 4, 5].values_at(3..9)  # one entry PER INDEX the range names
      p [1, 2, 3].each_index.to_a

      # --- Array.new -------------------------------------------------------------
      p Array.new
      p Array.new(3)
      p Array.new(3) { |i| i * i }

      # The default-value form SHARES one object across every slot -- which is
      # exactly why the block form exists.
      shared = Array.new(2, "x")
      p shared
      shared[0] << "!"
      p shared

      fresh = Array.new(2) { "x" }
      fresh[0] << "!"
      p fresh

      # --- all of it works on a user Enumerable ----------------------------------
      class Steps
        include Enumerable

        def initialize(*values)
          @values = values
        end

        def each(&blk)
          @values.each(&blk)
          self
        end
      end

      steps = Steps.new(1, 2, 4, 5, 6, 9)
      p steps.chunk_while { |i, j| i + 1 == j }.to_a
      p steps.grep(2..5)
      p steps.minmax_by { |x| -x }
      p steps.slice_before(&:even?).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [4], [9, 10, 11, 12], [15]]
      [[1, 2], [4], [9, 10, 11, 12], [15]]
      [[1, 1], [2], [3, 3]]
      []
      [[7]]
      [[1], [2, 3], [4, 5]]
      [[1, 2], [3, 4], [5]]
      [[1, 2, 3]]
      [[1, 2], [3, 4, 5]]
      [[1, 2, 3], [4, 5]]
      [["a"], ["b1", "c"]]
      [3, 4, 5]
      [1, 2]
      ["banana"]
      ["a", "b"]
      [10, 20]
      ["A", "B"]
      [[1, 4], [2, 5], [3, 6]]
      [[1, 4, 6], [2, 5, nil], [3, nil, nil]]
      [[1, 3, 5], [2, 4, 6]]
      nil
      [4, 1]
      ["a", "bbb"]
      [nil, nil]
      [[1, 2], [1, 3], [2, 3]]
      [[]]
      []
      [[1, 2], [1, 3], [2, 1], [2, 3], [3, 1], [3, 2]]
      [[1, 2], [2, 1]]
      [3, 4, 5]
      3
      nil
      2
      [1, 2, 3, 1, 2, 3]
      []
      [1, 2, 1, 2]
      5
      [1, 2, 3, 4]
      nil
      [1, 2, [3, [4]]]
      [3, 2, 1]
      [1, 3, nil]
      [3, 1]
      [1, 2]
      [4, 5, nil, nil, nil, nil, nil]
      [0, 1, 2]
      []
      [nil, nil, nil]
      [0, 1, 4]
      ["x", "x"]
      ["x!", "x!"]
      ["x!", "x"]
      [[1, 2], [4, 5, 6], [9]]
      [2, 4, 5]
      [9, 1]
      [[1], [2], [4, 5], [6, 9]]
    OUT
  end

  it "enumerable chain more" do
    result = ze0(<<~'RUBY')
      # Enumerable chain/reverse_each/compact/to_set on user classes + Array#chain (#2474-2478)
      class C
        include Enumerable
        def each; yield 3; yield 1; yield 2; end
      end
      c = C.new
      a = []; v = a
      p(v.chain([1, 2]).to_a)      # 2474 Array#chain, empty array in a variable
      c.reverse_each { |x| print x }; puts  # 2475
      p(c.compact)                 # 2476
      p(c.chain([9]).to_a)         # 2477
      require "set"
      p(c.to_set)                  # 2478
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      213
      [3, 1, 2]
      [3, 1, 2, 9]
      Set[3, 1, 2]
    OUT
  end

  it "enumerable pattern predicates" do
    result = ze0(<<~'RUBY')
      # any?/all?/none?/one? accept a pattern argument, matched with === (case
      # equality) against each element -- a class, range, regexp, or any === value.
      nums = [1, 2, 3, 4]
      p nums.any?(Integer)
      p nums.all?(Integer)
      p nums.none?(String)
      p nums.one?(3)
      p nums.any?(10..20)
      p nums.all?(0..)

      words = %w[apple banana cherry]
      p words.all?(/a/)
      p words.any?(/z/)
      p words.count(/an/)

      # Hash yields [key, value] pairs, matched against an array pattern.
      h = { a: 1, b: 2 }
      p h.any?([:a, 1])
      p h.none?([:c, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      false
      true
      false
      false
      0
      true
      true
    OUT
  end

  it "enumerable predicates accept a pattern" do
    result = ze0(<<~'RUBY')
      p [1, 2, 3].any?(Integer)
      p [1, "a", 3].all?(Integer)
      p [1, 2, 3].none?(String)
      p [1, 2, 3].one?(2)
      p [1, 2, 3].any?(4..10)
      p %w[foo bar].all?(/o|a/)
      p({ a: 1 }.any?([:a, 1]))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      false
      true
      true
    OUT
  end

  it "enumerable surplus arguments raise" do
    result = ze0(<<~'RUBY')
      # The Enumerable/Array rows that take an OPTIONAL argument must still count
      # what they were given: a surplus one is `wrong number of arguments`, not a
      # conversion error on the first, and not silently ignored.
      #
      # Five rows were wrong. `tally(1, 2)` reported the first argument's type,
      # `tally({}, 2)` and `each_slice(1, 2)`/`each_cons(1, 2)` ignored the extra
      # entirely and answered, `min(1, 2)`/`max(1, 2)` did too, and `count(1, 2)`
      # named the wrong bound ("expected 1" for a method whose range is 0..1).
      #
      # The rows that were already right are kept as controls, so a regression
      # names which half broke.
      rows = {
        "tally(1, 2)" => -> { [1, 2].tally(1, 2) },
        "tally(:x)" => -> { [1, 2].tally(:x) },
        "tally({}, 2)" => -> { [1, 2].tally({}, 2) },
        "sum(0, 1)" => -> { [1].sum(0, 1) },
        "min(1, 2)" => -> { [1].min(1, 2) },
        "max(1, 2)" => -> { [1].max(1, 2) },
        "first(1, 2)" => -> { [1].first(1, 2) },
        "uniq(1)" => -> { [1].uniq(1) },
        "flatten(1, 2)" => -> { [1].flatten(1, 2) },
        "count(1, 2)" => -> { [1].count(1, 2) },
        "zip()" => -> { [1].zip },
        "group_by(1)" => -> { [1].group_by(1) { |x| x } },
        "each_slice(1, 2)" => -> { [1].each_slice(1, 2) { break } },
        "each_cons(1, 2)" => -> { [1].each_cons(1, 2) { break } },
      }
      rows.each do |name, fn|
        r = begin
          v = fn.call
          "ok #{v.inspect}"
        rescue Exception => e
          "#{e.class}: #{e.message}"
        end
        puts "#{name}\t#{r}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      tally(1, 2)	ArgumentError: wrong number of arguments (given 2, expected 0..1)
      tally(:x)	TypeError: no implicit conversion of Symbol into Hash
      tally({}, 2)	ArgumentError: wrong number of arguments (given 2, expected 0..1)
      sum(0, 1)	ArgumentError: wrong number of arguments (given 2, expected 0..1)
      min(1, 2)	ArgumentError: wrong number of arguments (given 2, expected 0..1)
      max(1, 2)	ArgumentError: wrong number of arguments (given 2, expected 0..1)
      first(1, 2)	ArgumentError: wrong number of arguments (given 2, expected 0..1)
      uniq(1)	ArgumentError: wrong number of arguments (given 1, expected 0)
      flatten(1, 2)	ArgumentError: wrong number of arguments (given 2, expected 0..1)
      count(1, 2)	ArgumentError: wrong number of arguments (given 2, expected 0..1)
      zip()	ok [[1]]
      group_by(1)	ArgumentError: wrong number of arguments (given 1, expected 0)
      each_slice(1, 2)	ArgumentError: wrong number of arguments (given 2, expected 1)
      each_cons(1, 2)	ArgumentError: wrong number of arguments (given 2, expected 1)
    OUT
  end

  it "enumerable tally accumulator" do
    result = ze0(<<~'RUBY')
      # Enumerable#tally(hash) counts into the given accumulator hash and returns it
      # (the same object), across hash variants (#2628).
      class E
        include Enumerable
        def initialize(*a) = @a = a
        def each(&b) = @a.each(&b)
      end
      h = {1 => 10}
      r = E.new(1, 2, 2).tally(h)
      p r
      p r.equal?(h)
      p(E.new("a", "b", "a").tally({"a" => 5}))
      p([1, 1, 2].tally({2 => 100}))
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => 11, 2 => 2}
      true
      {"a" => 7, "b" => 1}
      {2 => 101, 1 => 2}
    OUT
  end

  it "enumerable via each" do
    result = ze0(<<~'RUBY')
      # A class that includes Enumerable and defines only #each gets the bare
      # Enumerable methods (map/select/to_a/sort/count/...) directly, with no explicit
      # enum_for: the compiler redirects each such call through the materialized array.
      class IntBag
        include Enumerable

        def initialize
          @items = []
        end

        def add(x)
          @items << x
          self
        end

        def each
          @items.each { |x| yield x }
        end
      end

      class WordBag
        include Enumerable

        def initialize
          @items = []
        end

        def add(x)
          @items << x
          self
        end

        def each
          @items.each { |x| yield x }
        end
      end

      b = IntBag.new
      b.add(3).add(1).add(2)

      p b.map { |n| n * 10 }
      p b.select { |n| n > 1 }
      p b.reject { |n| n > 1 }
      p b.to_a
      p b.sort
      p b.find { |n| n > 1 }
      puts b.count
      puts b.include?(2)
      puts b.sum
      puts b.min
      puts b.max
      puts b.any? { |n| n > 2 }
      puts b.all? { |n| n > 0 }
      puts b.one? { |n| n > 2 }
      p b.take_while { |n| n > 2 }
      p b.drop_while { |n| n > 2 }
      p b.zip([10, 20, 30])
      p b.grep(1..2)
      p b.grep_v(1..2)

      w = WordBag.new
      w.add("hi").add("there").add("world")
      p w.map { |s| s.upcase }
      p w.select { |s| s.length > 2 }
      p w.sort
      puts w.count
    RUBY

    _(result).must_answer <<~'OUT'
      [30, 10, 20]
      [3, 2]
      [1]
      [3, 1, 2]
      [1, 2, 3]
      3
      3
      true
      6
      1
      3
      true
      true
      true
      [3]
      [1, 2]
      [[3, 10], [1, 20], [2, 30]]
      [1, 2]
      [3]
      ["HI", "THERE", "WORLD"]
      ["there", "world"]
      ["hi", "there", "world"]
      3
    OUT
  end

  it "enumerator identity and resumability" do
    result = ze0(<<~'RUBY')
      # Enumerator identity/copy semantics: blockless `each` returns SELF,
      # pre-iteration dup is a fresh enumerator over the same source, breaking
      # out of an external loop leaves the enumerator resumable.

      e = [1, 2].each
      p e.each.equal?(e)
      d = e.dup
      p d.class
      p e.next
      p d.next
      g = [1, 2, 3].each
      loop do
        v = g.next
        break if v == 2
      end
      p g.next
    RUBY

    _(result).must_answer <<~'OUT'
      true
      Enumerator
      1
      1
      3
    OUT
  end

  it "exception from deep inside a fibers method stack reraises at the resumer" do
    result = ze0(<<~'RUBY')
      class Deep
        def go; boom; end
        def boom
          raise "deep boom"
        end
      end
      d = Deep.new
      f = Fiber.new { d.go }
      begin
        f.resume
      rescue RuntimeError => e
        puts "resumer caught: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "resumer caught: deep boom\n"
  end

  it "fiber does not see its resumers currently handled exception" do
    result = ze0(<<~'RUBY')
      # CRuby: the fiber has its own errinfo (fresh, nil), so its bare
      # `raise` builds a fresh empty-message RuntimeError instead of
      # re-raising the resumer's in-flight exception -- `fiber saw: []`.

      f = Fiber.new do
        begin
          raise
        rescue RuntimeError => e
          "fiber saw: [#{e.send(:message)}]"
        end
      end
      begin
        raise "resumer's exception"
      rescue RuntimeError
        puts f.resume
      end
    RUBY

    _(result).must_answer "fiber saw: []\n"
  end

  it "fiber reached through a dynamic receiver still resumes" do
    result = ze0(<<~'RUBY')
      # The static fast path emits `fiber_resume` directly; a fiber held in a
      # collection/ivar dispatches through the runtime's Fiber table instead.

      holder = [Fiber.new { Fiber.yield 1; 2 }]
      p holder[0].resume
      p holder[0].alive?
      p holder[0].resume
      p holder[0].alive?
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      2
      false
    OUT
  end

  it "fiber resume and yield pass values in both directions" do
    result = ze0(<<~'RUBY')
      # resume(v)'s v becomes the suspended Fiber.yield's return value;
      # Fiber.yield(v)'s v becomes resume's return value -- CRuby
      # `make_passing_arg` both ways.

      g = Fiber.new do |x|
        y = Fiber.yield(x + 1)
        z = Fiber.yield(y + 10)
        z + 100
      end
      puts g.resume(5)
      puts g.resume(6)
      puts g.resume(7)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      16
      107
    OUT
  end

  it "fibers rescue state survives suspension isolated from the resumer" do
    result = ze0(<<~'RUBY')
      # The fiber suspends MID-rescue; the resumer then handles (and
      # finishes handling) its own exception; on re-entry the fiber's bare
      # re-raise must still see the FIBER's exception -- the save/restore
      # swap around every switch, exercised in both directions.

      g = Fiber.new do
        begin
          raise "fiber's own"
        rescue RuntimeError
          Fiber.yield :suspended_mid_rescue
          begin
            raise
          rescue RuntimeError => again
            again.send(:message)
          end
        end
      end
      puts g.resume
      begin
        raise "resumer noise"
      rescue RuntimeError
        x = 1
      end
      puts g.resume
    RUBY

    _(result).must_answer "suspended_mid_rescue\nfiber's own\n"
  end

  it "include enumerable block each" do
    result = ze0(<<~'RUBY')
      # A class that includes Enumerable and defines each by forwarding an explicit
      # &block (rather than using yield) still derives the Enumerable method set:
      # each drives the synthesized materialization the same way a yield-based each
      # does.
      class Bag
        include Enumerable
        def initialize(*items) = @items = items
        def each(&blk) = @items.each(&blk)
      end
      b = Bag.new(3, 1, 2)
      p b.map { |x| x * 2 }
      p b.select { |x| x > 1 }
      p b.reject { |x| x > 1 }
      p b.find { |x| x > 1 }
      p b.sort
      p b.sort_by { |x| -x }
      p b.include?(2)
      p b.to_a
      p b.min
      p b.max
      p b.count
      p b.first
      p b.any? { |x| x > 2 }
      p b.all? { |x| x > 0 }
    RUBY

    _(result).must_answer <<~'OUT'
      [6, 2, 4]
      [3, 2]
      [1]
      3
      [1, 2, 3]
      [3, 2, 1]
      true
      [3, 1, 2]
      1
      3
      3
      3
      true
      true
    OUT
  end

  it "minmax by count" do
    result = ze0(<<~'RUBY')
      # Array#min_by(n) / max_by(n) with a count return the n smallest / largest
      # elements by the block's key, as a generic Array: min_by ascending, max_by
      # descending. Receivers are routed through per-type identity methods to defeat
      # constant folding. Keys are distinct so ordering is unambiguous (Ruby's count
      # form uses an internal heap with unspecified order for tied keys).
      def ss(x); x; end
      def si(x); x; end

      p ss(%w[bbbb a ccc dd]).max_by(2, &:length)   # ["bbbb", "ccc"]
      p ss(%w[bbbb a ccc dd]).min_by(2, &:length)   # ["a", "dd"]
      p si([3, 1, 4, 1, 5, 9, 2]).max_by(3) { |n| n }   # [9, 5, 4]
      p si([3, 1, 4, 6, 5, 9, 2]).min_by(3) { |n| -n }  # [9, 6, 5]

      # count larger than the array, and zero count.
      p si([1, 2, 3]).max_by(5) { |n| n }    # [3, 2, 1]
      p si([1, 2, 3]).min_by(0) { |n| n }    # []

      # the no-count form still returns a single element.
      p ss(%w[bb a ccc dd]).max_by(&:length)   # "ccc"
      p si([3, 1, 2]).min_by { |n| n }         # 1

      # a negative count raises ArgumentError, as in CRuby (not an empty array).
      begin
        si([1, 2, 3]).max_by(-1) { |n| n }
      rescue ArgumentError => e
        p e.message
      end                                       # "negative size"
    RUBY

    _(result).must_answer <<~'OUT'
      ["bbbb", "ccc"]
      ["a", "dd"]
      [9, 5, 4]
      [9, 6, 5]
      [3, 2, 1]
      []
      "ccc"
      1
      "negative size (-1)"
    OUT
  end

  it "minmax makes one pass over its source" do
    result = ze0(<<~'RUBY')
      # `Enumerable#minmax` ran `min` and then `max`, so a comparison block saw
      # every element TWICE and the source was walked twice. CRuby's `enum_minmax`
      # buffers in PAIRS: one comparison orders the pair, then at most one more
      # lowers the min and one more raises the max. The call SEQUENCE is
      # observable, so it is pinned here, not just the result.
      def probe(a)
        seen = []
        r = a.minmax { |x, y| seen << [x, y]; x <=> y }
        [r, seen]
      end

      p probe([])
      p probe([7])
      p probe([5, 1])
      p probe([5, 1, 9])
      p probe([5, 1, 9, 3])
      p probe([5, 1, 9, 3, 0])

      # The block-less spelling, and a non-Array Enumerable, which reaches the same
      # driver through `each`.
      p [].minmax
      p [4].minmax
      p [3, 1, 2].minmax

      class Bag
        include Enumerable
        def initialize(*a) = @a = a
        def each(&b) = @a.each(&b)
      end
      p Bag.new(4, 2, 8, 6, 1).minmax
      n = 0
      p Bag.new(4, 2, 8).minmax { |x, y| n += 1; x <=> y }
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      [[nil, nil], []]
      [[7, 7], []]
      [[1, 5], [[5, 1]]]
      [[1, 9], [[5, 1], [9, 1], [9, 5]]]
      [[1, 9], [[5, 1], [9, 3], [3, 1], [9, 5]]]
      [[0, 9], [[5, 1], [9, 3], [3, 1], [9, 5], [0, 1], [0, 9]]]
      [nil, nil]
      [4, 4]
      [1, 3]
      [1, 8]
      [2, 8]
      3
    OUT
  end

  it "misc" do
    result = ze0(<<~'RUBY')
      # Test miscellaneous features: is_a?, respond_to?, String <<, Array#reduce, upto/downto

      # String << (append/concat mutating)
      s = "Hello"
      s << ", World"
      puts s  # Hello, World

      # Array#reduce / inject
      arr = (1..5).to_a
      total = 0
      arr.each do |x|
        total += x
      end
      puts total  # 15

      # upto / downto
      count = 0
      1.upto(5) do |i|
        count += i
      end
      puts count  # 15

      count2 = 0
      5.downto(1) do |i|
        count2 += i
      end
      puts count2  # 15

      # abs on negative
      puts (-42).abs  # 42

      # Multiple return (via array)
      def min_max(arr)
        mn = arr[0]
        mx = arr[0]
        arr.each do |x|
          if x < mn
            mn = x
          end
          if x > mx
            mx = x
          end
        end
        puts mn
        puts mx
      end

      data = (1..10).to_a
      min_max(data)  # 1, 10
    RUBY

    _(result).must_answer <<~'OUT'
      Hello, World
      15
      15
      15
      42
      1
      10
    OUT
  end

  it "nested fibers each yield to their own resumer" do
    result = ze0(<<~'RUBY')
      # The exact shape a fiber save/restore discipline exists for: after the
      # inner fiber yields, the OUTER fiber's own Fiber.yield must suspend the
      # outer one, not touch the inner's suspended yielder. The inner fiber is
      # CREATED outside the outer's block (captured via an ordinary local)
      # because a block literal escaping from inside another escaping block is a
      # PRE-existing scope-cut unrelated to fibers.

      inner = Fiber.new do
        Fiber.yield :from_inner
        :inner_done
      end
      outer = Fiber.new do
        got = inner.resume
        Fiber.yield got
        inner.resume
      end
      puts outer.resume
      puts outer.resume
    RUBY

    _(result).must_answer "from_inner\ninner_done\n"
  end

  it "never yields" do
    result = ze0(<<~'RUBY')
      class Empt
        include Enumerable
        def each; end
      end
      p(Empt.new.to_a)
      p(Empt.new.map { |x| x })
      p(Empt.new.count)
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      0
    OUT
  end

  it "nmin keeps rubys survivors" do
    result = ze0(<<~'RUBY')
      # `min(n)`, `max(n)`, `min_by(n)` and `max_by(n)` are NOT sort-then-take.
      # CRuby buffers 4n elements, QUICKSELECTS them down to n, and remembers the
      # last pivot as a limit -- after which an element no better than the limit is
      # dropped without being buffered at all. So among equal keys it is the SET of
      # survivors that quickselect decides, not merely their order, and only the
      # survivors are sorted at the end.
      #
      # The 4n buffer is why the count matters: at n=3 over 60 elements the filter
      # runs several times, at n=20 once, and each run moves the limit.
      #
      # The survivors are sorted through `ruby_qsort`, which IS the system
      # `qsort_r`, so two rows are libc's answer rather than ruby's. TWO goldens:
      # `.expected` is macOS, `.linux.expected` linux.

      def t(label)
        puts format("%-24s %s", label, (yield).inspect)
      rescue StandardError => e
        puts format("%-24s %s: %s", label, e.class, e.message)
      end

      pairs = Array.new(60) { |i| [i % 3, i] }

      t("min_by(3)") { pairs.min_by(3) { |x| x[0] } }
      t("max_by(3)") { pairs.max_by(3) { |x| x[0] } }
      t("min(3)") { pairs.min(3) { |a, b| a[0] <=> b[0] } }
      t("max(3)") { pairs.max(3) { |a, b| a[0] <=> b[0] } }
      t("min_by(1)") { pairs.min_by(1) { |x| x[0] } }
      t("min_by(20)") { pairs.min_by(20) { |x| x[0] }.last(4) }
      t("min_by(60)") { pairs.min_by(60) { |x| x[0] }.first(3) }
      t("min_by past the end") { pairs.min_by(100) { |x| x[0] }.size }
      t("min_by(0)") { pairs.min_by(0) { |x| x[0] } }
      t("min(0)") { pairs.min(0) }
      t("negative") { pairs.min_by(-1) { |x| x[0] } }

      t("enumerator") { pairs.each_with_index.min_by(3) { |x,| x[0] } }
      t("a range") { (1..40).min(3) { |a, b| (a % 4) <=> (b % 4) } }
      t("distinct keys min") { [5, 3, 9, 1].min(2) }
      t("distinct keys max") { [5, 3, 9, 1].max(2) }
      t("all equal") { Array.new(30) { |i| [0, i] }.min_by(4) { |x| x[0] } }
      t("strings") { %w[pear apple fig kiwi date].min_by(2, &:length) }
      t("incomparable") { [1, "a"].min(1) }
      t("nil from the block") { pairs.min(2) { |_a, _b| nil } }
    RUBY

    _(result).must_answer <<~'OUT', linux: <<~'LINUX'
      min_by(3)                [[0, 3], [0, 0], [0, 6]]
      max_by(3)                [[2, 11], [2, 2], [2, 5]]
      min(3)                   [[0, 3], [0, 0], [0, 6]]
      max(3)                   [[2, 11], [2, 2], [2, 5]]
      min_by(1)                [[0, 0]]
      min_by(20)               [[0, 21], [0, 51], [0, 18], [0, 0]]
      min_by(60)               [[0, 3], [0, 21], [0, 0]]
      min_by past the end      60
      min_by(0)                []
      min(0)                   []
      negative                 ArgumentError: negative size (-1)
      enumerator               [[[0, 3], 3], [[0, 0], 0], [[0, 6], 6]]
      a range                  [20, 8, 36]
      distinct keys min        [1, 3]
      distinct keys max        [9, 5]
      all equal                [[0, 7], [0, 0], [0, 14], [0, 13]]
      strings                  ["fig", "date"]
      incomparable             ArgumentError: comparison of String with 1 failed
      nil from the block       ArgumentError: comparison of Array with Array failed
    OUT
      min_by(3)                [[0, 3], [0, 0], [0, 6]]
      max_by(3)                [[2, 11], [2, 2], [2, 5]]
      min(3)                   [[0, 3], [0, 0], [0, 6]]
      max(3)                   [[2, 11], [2, 2], [2, 5]]
      min_by(1)                [[0, 0]]
      min_by(20)               [[0, 21], [0, 51], [0, 18], [0, 39]]
      min_by(60)               [[0, 0], [0, 24], [0, 54]]
      min_by past the end      60
      min_by(0)                []
      min(0)                   []
      negative                 ArgumentError: negative size (-1)
      enumerator               [[[0, 3], 3], [[0, 0], 0], [[0, 6], 6]]
      a range                  [20, 8, 36]
      distinct keys min        [1, 3]
      distinct keys max        [9, 5]
      all equal                [[0, 7], [0, 0], [0, 14], [0, 13]]
      strings                  ["fig", "date"]
      incomparable             ArgumentError: comparison of String with 1 failed
      nil from the block       ArgumentError: comparison of Array with Array failed
    LINUX
  end

  it "non number ends the compensated sum" do
    result = ze0(<<~'RUBY')
      # A value that is no number ends a compensated Float sum: CRuby goes on
      # from the sum without the compensation it had gathered, for an Array
      # and for any Enumerable.
      p [0.1, 0.2, 0.3, 1i].sum, [0.1, 0.2, 0.3, 1i].each.sum
      p [1e100, 1.0, -1e100, 1i].sum, [1e100, 1.0, -1e100, 1i].each.sum
      p [0.1, 0.2, 0.3, 1r, 1i].sum

    RUBY

    _(result).must_answer <<~'OUT'
      (0.6000000000000001+1i)
      (0.6000000000000001+1i)
      (0.0+1i)
      (0.0+1i)
      (1.6+1i)
    OUT
  end

  it "raising to s and inspect propagate catchably through every display consumer" do
    result = ze0(<<~'RUBY')
      # The fallible-display contract: a user `to_s`/`inspect` that raises
      # surfaces as a CATCHABLE exception from puts/print/p/warn/format/
      # interpolation (string and regexp)/Array+Hash to_s -- never a
      # runtime panic. Partial-output rules are CRuby's own: puts/print/p
      # flush what rendered before the raise, warn flushes nothing.
      # Expected output is verbatim ruby 4.0.6.

      class Boom
        def to_s
          raise "to_s boom"
        end
        def inspect
          raise "inspect boom"
        end
      end
      b = Boom.new
      begin
        puts b
      rescue => e
        puts "puts: #{e.class}: #{e.message}"
      end
      begin
        print b
      rescue => e
        puts "print: #{e.class}: #{e.message}"
      end
      begin
        x = "v=#{b}"
      rescue => e
        puts "interp: #{e.class}: #{e.message}"
      end
      begin
        p b
      rescue => e
        puts "p: #{e.class}: #{e.message}"
      end
      begin
        s = format("%s", b)
      rescue => e
        puts "format s: #{e.class}: #{e.message}"
      end
      begin
        s = format("%p", b)
      rescue => e
        puts "format p: #{e.class}: #{e.message}"
      end
      begin
        puts [1, b, 2]
      rescue => e
        puts "puts arr: #{e.class}: #{e.message}"
      end
      begin
        p [1, b]
      rescue => e
        puts "p arr: #{e.class}: #{e.message}"
      end
      begin
        puts({ k: b }.to_s)
      rescue => e
        puts "hash to_s: #{e.class}: #{e.message}"
      end
      puts "still running"
      begin
        p 1, b
      rescue => e
        puts "p multi: #{e.class}: #{e.message}"
      end
      begin
        print "x", b
      rescue => e
        puts "print multi: #{e.class}: #{e.message}"
      end
      puts
      begin
        warn "w1", b
      rescue => e
        puts "warn multi: #{e.class}: #{e.message}"
      end
      begin
        s = "pat#{b}"
      rescue => e
        puts "interp2: #{e.class}: #{e.message}"
      end
      begin
        r = /x#{b}/
      rescue => e
        puts "regexp interp: #{e.class}: #{e.message}"
      end
      puts "end"
    RUBY

    _(result).must_answer <<~'OUT'
      puts: RuntimeError: to_s boom
      print: RuntimeError: to_s boom
      interp: RuntimeError: to_s boom
      p: RuntimeError: inspect boom
      format s: RuntimeError: to_s boom
      format p: RuntimeError: inspect boom
      1
      puts arr: RuntimeError: to_s boom
      p arr: RuntimeError: inspect boom
      hash to_s: RuntimeError: inspect boom
      still running
      1
      p multi: RuntimeError: inspect boom
      xprint multi: RuntimeError: to_s boom

      warn multi: RuntimeError: to_s boom
      interp2: RuntimeError: to_s boom
      regexp interp: RuntimeError: to_s boom
      end
    OUT
  end

  it "reopening enumerable reaches every includer" do
    result = ze0(<<~'RUBY')
      # Enumerable is a NATIVE builtin, yet reopenable (D3): an added
      # method registers as a value method on the module id and the MRO walk
      # finds it for every includer, its body free to drive the native
      # Enumerable protocol (`reduce`) on the receiver.

      module Enumerable
        def my_join
          reduce("") { |acc, x| acc + x.to_s }
        end
      end
      puts [1, 2, 3].my_join
      puts (1..3).my_join
    RUBY

    _(result).must_answer "123\n123\n"
  end

  it "resolves before method missing" do
    result = ze0(<<~'RUBY')
      # The send-ladder fidelity fix: a REAL module method (Enumerable's `map`,
      # via `include Enumerable` + `each`) resolves BEFORE `method_missing` --
      # previously method_missing fired first, the opposite of real Ruby.

      class Sack
        include Enumerable
        def initialize(items)
          @items = items
        end
        def each(&b)
          @items.each(&b)
          self
        end
        def method_missing(name, *a)
          "mm:#{name}"
        end
      end

      s = Sack.new([1, 2, 3])
      puts s.map { |x| x * 10 }.inspect
      puts s.nope
    RUBY

    _(result).must_answer "[10, 20, 30]\nmm:nope\n"
  end

  it "resuming a dead fiber raises a catchable fiber error" do
    result = ze0(<<~'RUBY')
      d = Fiber.new { :done }
      d.resume
      begin
        d.resume
      rescue FiberError => e
        puts e.send(:message)
      end
    RUBY

    _(result).must_answer "attempt to resume a terminated fiber\n"
  end

  it "scalar isa dead branch" do
    result = ze0(<<~'RUBY')
      h = {}
      h[57] = -4

      h.keys.sort.each do |key|
        value = h[key]
        puts(key.to_s + "=" + (value.is_a?(Array) ?
          ("[" + value.map { |item| item.to_s }.join(",") + "]") :
          (value.is_a?(Hash) ?
            ("{" + value.keys.sort_by(&:to_s).map { |nested_key| nested_key.to_s + ":" + value[nested_key].to_s }.join(",") + "}") :
            (value.is_a?(Float) ? format("%.2f", value) : value.to_s))))
      end

      # A bool's class depends on its value, and a module target is an ancestor:
      # neither guard may be folded away.
      flag = true
      puts(flag.is_a?(TrueClass) ? "true-class" : "false-class")
      n = 5
      puts(n.is_a?(Comparable) ? "comparable" : "not")
      puts(n.is_a?(Numeric) ? "numeric" : "not")
      puts(n.is_a?(String) ? "string" : "not-string")
      s = "x"
      puts(s.instance_of?(String) ? "exact" : "inexact")
      puts(s.is_a?(Object) ? "object" : "not")
    RUBY

    _(result).must_answer <<~'OUT'
      57=-4
      true-class
      comparable
      numeric
      not-string
      exact
      object
    OUT
  end

  it "super from an overridden inspect resumes above it" do
    result = ze0(<<~'RUBY')
      module PB; def inspect = "P" + super; end
      class Array; prepend PB; end
      p [1, 2].inspect

      class Integer
        def inspect = "I" + super
      end
      p 5.inspect

      module PT; def to_s = "T" + super; end
      class Hash; prepend PT; end
      p({ a: 1 }.to_s)

      p Kernel.instance_method(:inspect).bind(5).call
      p 5.inspect, [1, 2].inspect, ({ a: 1 }).inspect, "x".inspect, (1..2).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "P[1, 2]"
      "I#<Integer:0xADDR>"
      "T{a: I#<Integer:0xADDR>}"
      "#<Integer:0xADDR>"
      "I#<Integer:0xADDR>"
      "P[I#<Integer:0xADDR>, I#<Integer:0xADDR>]"
      "{a: I#<Integer:0xADDR>}"
      "\"x\""
      "I#<Integer:0xADDR>..I#<Integer:0xADDR>"
    OUT
  end

  it "tail iter call receiver" do
    result = ze0(<<~'RUBY')
      # An iterator answers its receiver, and at tail position that value is the
      # method's return. The statement form produces it by re-READING the receiver,
      # so a receiver that is itself a call used to fall through to nil.
      def keys_of(h) = h.keys.each { |a| a }
      def values_of(h) = h.values.each { |a| a }
      def pairs_of(h) = h.to_a.each { |a| a }
      def sorted(a) = a.sort.each { |x| x }
      def duped(a) = a.dup.each { |x| x }
      def mapped(a) = a.map { |x| x }.each { |x| x }
      def backwards(a) = a.sort.reverse_each { |x| x }

      p keys_of({ "y" => 2 })
      p values_of({ "y" => 2 })
      p pairs_of({ "y" => 2 })
      p sorted(["b", "a"])
      p duped(["y"])
      p mapped(["y"])
      p backwards(["b", "a"])

      # a plain read still returns the receiver itself, and a non-tail loop still
      # leaves the following value alone
      def plain(a) = a.each { |x| x }
      def after(a)
        a.each { |x| x }
        1
      end
      p plain(["y"])
      p after(["y"])

      # the shape it turned up in: nested blocks under a module method
      module M
        Only = Struct.new(:v)
        def self.walk(scope)
          scope.keys.each { |a| [1].each { |b| Only.new(a) } }
        end
      end
      p M.walk({ "y" => 2 })
    RUBY

    _(result).must_answer <<~'OUT'
      ["y"]
      [2]
      [["y", 2]]
      ["a", "b"]
      ["y"]
      ["y"]
      ["a", "b"]
      ["y"]
      1
      ["y"]
    OUT
  end

  it "take while boxed predicate" do
    result = ze0(<<~'RUBY')
      # take_while / drop_while whose block answers a boxed value: `!(rbval)` is not
      # valid C -- the value is a struct -- so the loop condition did not compile.
      p([1,nil,2].take_while { |q| q })
      p([1,nil,2].drop_while { |q| q })
      p([nil,1].take_while { |w| w })
      p([1,2,3].take_while { |e| e < 3 })
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [nil, 2]
      []
      [1, 2]
    OUT
  end

  it "tally accumulator" do
    result = ze0(<<~'RUBY')
      # Enumerable#tally(hash) accumulates into the given hash and returns it (#2533)
      h = Hash.new(0)
      p([1, 1, 2, 3, 3, 3].tally(h))
      p(h)
      g = { 5 => 10 }
      p([5, 5, 6].tally(g))            # accumulates onto existing counts
      s = Hash.new(0)
      p(%w[a a b].tally(s))
      # plain tally still works (no arg)
      p([1, 1, 2].tally)
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => 2, 2 => 1, 3 => 3}
      {1 => 2, 2 => 1, 3 => 3}
      {5 => 12, 6 => 1}
      {"a" => 2, "b" => 1}
      {1 => 2, 2 => 1}
    OUT
  end

  it "thread and the fiber it resumes have isolated handling" do
    result = ze0(<<~'RUBY')
      # A Thread mid-rescue resumes a fiber whose bare raise must see an EMPTY
      # $!, not the thread's in-flight exception.

      t = Thread.new do
        f = Fiber.new do
          begin
            raise
          rescue RuntimeError => e
            "fiber saw: [#{e.send(:message)}]"
          end
        end
        begin
          raise "thread's exception"
        rescue RuntimeError
          f.resume
        end
      end
      puts t.value
    RUBY

    _(result).must_answer "fiber saw: []\n"
  end

  it "throw inside a fiber cannot see the resumers catch" do
    result = ze0(<<~'RUBY')
      # The ec-swap's catch-tag slice, oracle-verified: a fiber has its own
      # execution context, so the resumer's live `catch` frame is invisible
      # inside it (UncaughtThrowError AT the throw) -- while a catch/throw
      # pair fully inside the fiber works normally.

      r = catch(:tag) do
        f = Fiber.new do
          begin
            throw :tag, 1
            :not_reached
          rescue UncaughtThrowError => e
            "uncaught: #{e.message}"
          end
        end
        f.resume
      end
      p r
      f2 = Fiber.new { catch(:in) { throw :in, :works } }
      p f2.resume
    RUBY

    _(result).must_answer <<~'OUT'
      "uncaught: uncaught throw :tag"
      :works
    OUT
  end

  it "uncaught exception inside a fiber reraises at the resumer and kills the fiber" do
    result = ze0(<<~'RUBY')
      x = Fiber.new do
        raise "boom in fiber"
      end
      begin
        x.resume
      rescue RuntimeError => e
        puts "caught: #{e.send(:message)}"
      end
      puts x.alive?
    RUBY

    _(result).must_answer "caught: boom in fiber\nfalse\n"
  end
end
