# frozen_string_literal: true

require "spec_helper"

describe "Builtins programs" do
  it "accessor devirtualized surface" do
    result = zr(<<~'RUBY')
      # A method whose whole body is one ivar access reaches the field directly
      # from the dynamic dispatch table (`zr_tramp!`'s `rd`/`wr` heads) instead of
      # downcasting and calling the generated method. Everything OBSERVABLE about
      # such a method must survive that: reflection, visibility, arity errors, the
      # frozen guard, inheritance and aliasing.
      #
      # A RUNTIME redefinition winning over an accessor is the one part not pinned
      # here -- zr does not honour it for a plain method either, so it lives in
      # `tests/gaps/issue_runtime_redefine_accessor.rb` rather than pretending to be
      # something devirtualization introduced.
      class Node
        attr_accessor :value
        attr_reader :tag

        # Hand-written, not `attr_*` -- the SHAPE is what qualifies, not the
        # provenance, so these must devirtualize identically.
        def left
          @left
        end

        def left=(n)
          @left = n
        end

        # One statement too many, or the wrong statement: NOT an accessor.
        def value_twice
          @value + @value
        end

        def touched
          @count = 1
          @count
        end

        def initialize(v)
          @value = v
          @tag = "t#{v}"
        end

        private

        def secret
          @tag
        end
      end

      n = Node.new(7)
      p [n.value, n.tag, n.left]
      n.value = 9
      n.left = Node.new(1)
      p [n.value, n.left.value, n.value_twice, n.touched]

      # Reading an ivar nothing ever assigned is nil, and leaves it UNDEFINED.
      p n.instance_variables.sort
      fresh = Node.allocate
      p [fresh.value, fresh.instance_variables]

      # Reflection reaches the same method however it is spelled.
      p [n.method(:value).arity, n.method(:value=).arity, n.method(:left).arity]
      p [Node.instance_method(:value).owner, Node.instance_method(:left).owner]
      p [n.method(:tag).parameters, n.method(:value=).parameters.map(&:first)]
      p [n.respond_to?(:value), n.respond_to?(:secret), n.respond_to?(:secret, true)]
      p [n.send(:value), n.send(:secret), n.public_send(:tag)]
      p n.method(:value).unbind.bind(Node.new(3)).call

      # A private accessor stays private through the dynamic path.
      begin
        n.secret
      rescue NoMethodError => e
        puts e.message
      end

      # Arity errors are attributed to the accessor, with CRuby's wording.
      begin
        n.send(:value, 1)
      rescue ArgumentError => e
        puts e.message
      end
      begin
        n.send(:value=)
      rescue ArgumentError => e
        puts e.message
      end

      # The frozen guard survives, and reports the receiver.
      frozen = Node.new(2)
      frozen.freeze
      begin
        frozen.value = 5
      rescue FrozenError => e
        puts e.message.sub(/0x[0-9a-f]+/, "0xADDR")
        p e.receiver.equal?(frozen)
      end
      p frozen.value

      # Inherited and aliased accessors keep working, and keep their identities.
      class Child < Node
        alias_method :val, :value
      end

      c = Child.new(4)
      p [c.value, c.val, c.tag]
      p [Child.instance_method(:value).owner, c.method(:val).original_name]
      c.val = 6 if c.respond_to?(:val=)
      p c.value
    RUBY

    _(result).must_answer <<~'OUT'
      [7, "t7", nil]
      [9, 1, 18, 1]
      [:@count, :@left, :@tag, :@value]
      [nil, []]
      [0, 1, 0]
      [Node, Node]
      [[], [:req]]
      [true, false, true]
      [9, "t7", "t7"]
      3
      private method 'secret' called for an instance of Node
      wrong number of arguments (given 1, expected 0)
      wrong number of arguments (given 0, expected 1)
      can't modify frozen Node: #<Node:0xADDR @value=2, @tag="t2">
      true
      2
      [4, 4, "t4"]
      [Node, :value]
      4
    OUT
  end

  it "arithmetic sequence rows" do
    result = zr(<<~'RUBY')
      # `Enumerator::ArithmeticSequence` -- what a blockless `Range#step`,
      # `Range#%` or `Numeric#step` over a numeric receiver answers, its thirteen
      # own methods, and the strided `Array#[]` that reads one.

      puts "class: #{(1..10).step(2).class}"
      puts "superclass: #{Enumerator::ArithmeticSequence.superclass}"
      puts "own methods: #{Enumerator::ArithmeticSequence.instance_methods(false).sort.inspect}"
      puts "ancestors head: #{Enumerator::ArithmeticSequence.ancestors.first(4).inspect}"
      puts "range %: #{((1..10) % 3).class}"
      puts "numeric step: #{1.step(10, 3).class}"
      puts "string range: #{("a".."e").step(2).class}"

      # The quadruple, which every other row is computed from.
      s = (1..10).step(2)
      puts "parts: #{[s.begin, s.end, s.step, s.exclude_end?].inspect}"
      puts "exclusive parts: #{[(1...10).step(3).end, (1...10).step(3).exclude_end?].inspect}"
      puts "endless end: #{(1..).step(2).end.inspect}"
      puts "numeric exclude_end?: #{1.step(10, 3).exclude_end?}"

      # `#inspect` replays the CALL, so the same sequence prints three ways.
      puts "inspect range: #{(1..10).step(2).inspect}"
      puts "inspect exclusive: #{(1...10).step(2).inspect}"
      puts "inspect endless: #{(1..).step(2).inspect}"
      puts "inspect %: #{((1..10) % 2).inspect}"
      puts "inspect float: #{(1.0..2.0).step(0.5).inspect}"
      puts "inspect numeric: #{1.step(10, 3).inspect}"
      puts "inspect bare: #{1.step.inspect}"
      puts "inspect kwargs: #{1.step(to: 9, by: 2).inspect}"
      puts "inspect rational: #{Rational(1, 2).step(Rational(5, 2), Rational(1, 2)).inspect}"

      # `#each` answers self, and a blockless call answers self too rather than
      # wrapping the sequence in another enumerator.
      seen = []
      puts "each self: #{s.each { |x| seen << x }.equal?(s)}"
      puts "each yielded: #{seen.inspect}"
      puts "each blockless: #{s.each.class}"
      puts "to_a: #{s.to_a.inspect}"
      puts "map: #{s.map { |x| x * 10 }.inspect}"

      # The Float lane computes `begin + i * step` rather than running a sum, so
      # the last element lands exactly on the endpoint.
      puts "float walk: #{(0.0..1.0).step(0.1).to_a.inspect}"
      puts "numeric float walk: #{0.0.step(1.0, 0.1).to_a.inspect}"
      puts "mixed walk: #{1.step(2.0, 0.5).to_a.inspect}"
      puts "rational walk: #{Rational(1, 2).step(Rational(5, 2), Rational(1, 2)).to_a.inspect}"
      puts "descending: #{(10..1).step(-2).to_a.inspect}"
      puts "against direction: #{(1..10).step(-2).to_a.inspect}"
      puts "endless take: #{(1..).step(2).first(4).inspect}"

      # `#size` is computed, never walked -- which is the only way an endless
      # sequence answers at all.
      puts "size: #{s.size}"
      puts "size exclusive: #{(1...10).step(3).size}"
      puts "size float: #{(0.0..1.0).step(0.1).size}"
      puts "size float exclusive: #{(1...10).step(2.5).size}"
      puts "size mixed: #{(1..10.5).step(2).size}"
      puts "size empty: #{(1..0).step(2).size}"
      puts "size descending: #{(10..1).step(-2).size}"
      puts "size endless: #{(1..).step(2).size}"
      puts "size rational: #{Rational(1, 2).step(Rational(5, 2), Rational(1, 2)).size}"

      # `#first` answers `begin` untouched; `#first(n)` walks, so it inherits the
      # walk's Float lane.
      puts "first: #{s.first}"
      puts "first mixed: #{(1..10.5).step(2).first}"
      puts "first n mixed: #{(1..10.5).step(2).first(3).inspect}"
      puts "first empty: #{(1..0).step(2).first.inspect}"
      puts "first zero: #{s.first(0).inspect}"
      puts "first over: #{s.first(99).inspect}"
      begin
        s.first(-1)
      rescue ArgumentError => e
        puts "first negative: #{e.message}"
      end

      # `#last` computes from the quadruple instead, which is why a mixed
      # sequence answers an Integer where its walk yields Floats.
      puts "last: #{s.last}"
      puts "last n: #{s.last(3).inspect}"
      puts "last over: #{s.last(99).inspect}"
      puts "last exclusive: #{(1...10).step(3).last}"
      puts "last n exclusive: #{(1...10).step(3).last(2).inspect}"
      puts "last mixed: #{(1..10.5).step(2).last}"
      puts "last walked: #{(1..10.5).step(2).to_a.last}"
      puts "last empty: #{(1..0).step(2).last.inspect}"
      puts "last rational: #{Rational(1, 2).step(Rational(5, 2), Rational(1, 2)).last}"
      begin
        s.last(-1)
      rescue ArgumentError => e
        puts "last negative: #{e.message}"
      end
      begin
        (1..).step(2).last
      rescue RangeError => e
        puts "last endless: #{e.message}"
      end

      # Equality reads the quadruple, so the call that built it does not enter
      # into it -- but `#hash` is NOT held to that, exactly as in CRuby, because
      # `2.hash` and `2.0.hash` differ.
      puts "== same: #{(1..9).step(2) == 1.step(9, 2)}"
      puts "eql? same: #{(1..9).step(2).eql?(1.step(9, 2))}"
      puts "=== same: #{(1..9).step(2) === 1.step(9, 2)}"
      puts "== float step: #{(1..10).step(2) == (1..10).step(2.0)}"
      puts "hash float step: #{(1..10).step(2).hash == (1..10).step(2.0).hash}"
      puts "hash same: #{(1..10).step(2).hash == (1..10).step(2).hash}"
      puts "== exclusive: #{(1...10).step(2) == (1..10).step(2)}"
      puts "== element: #{(1..10).step(2) === 3}"
      puts "== other: #{(1..10).step(2) == 1}"

      # `Array#[]` slices with a stride. A sequence is stricter than the
      # equivalent Range: where `a[20..30]` answers nil, the sequence raises --
      # except at a step of exactly 1, which routes through the Range slice.
      a = (0..9).to_a
      puts "aref: #{a[(1..10).step(2)].inspect}"
      puts "aref endless: #{a[(0..).step(3)].inspect}"
      puts "aref beginless: #{a[(..5).step(2)].inspect}"
      puts "aref negative bounds: #{a[(-3..-1).step(2)].inspect}"
      puts "aref descending: #{a[(9..0).step(-2)].inspect}"
      puts "aref descending exclusive: #{a[(9...1).step(-2)].inspect}"
      puts "aref against direction: #{a[(0..9).step(-2)].inspect}"
      puts "aref exclusive: #{a[(0...9).step(3)].inspect}"
      puts "aref float bounds: #{a[(1.5..5.5).step(2)].inspect}"
      puts "aref float step: #{a[(0..9).step(2.9)].inspect}"
      puts "aref numeric: #{a[1.step(7, 2)].inspect}"
      puts "aref stride 1: #{a[(0..10).step(1)].inspect}"
      puts "aref stride 1 past end: #{a[(11..12).step(1)].inspect}"
      puts "aref slice: #{a.slice((1..7).step(2)).inspect}"
      puts "aref at end: #{a[(10..11).step(2)].inspect}"
      begin
        a[(0..10).step(3)]
      rescue RangeError => e
        puts "aref out of range: #{e.message}"
      end
      begin
        a[(11..12).step(2)]
      rescue RangeError => e
        puts "aref begin past end: #{e.message}"
      end
      begin
        a[(1..5).step(0.5)]
      rescue ArgumentError => e
        puts "aref zero stride: #{e.message}"
      end

      # A zero step is rejected up front on both paths.
      begin
        (1..10).step(0)
      rescue ArgumentError => e
        puts "zero step: #{e.message}"
      end
      begin
        1.step(10, 0)
      rescue ArgumentError => e
        puts "zero numeric step: #{e.message}"
      end
      # A non-numeric step is not refused until the walk needs it, so the
      # blockless form is an ordinary Enumerator rather than a sequence.
      puts "string step: #{(1..5).step("x").class}"
      puts "string step inspect: #{(1..5).step("x").inspect}"
      begin
        (1..5).step("x") { |x| x }
      rescue TypeError => e
        puts "string step block: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      class: Enumerator::ArithmeticSequence
      superclass: Enumerator
      own methods: [:==, :===, :begin, :each, :end, :eql?, :exclude_end?, :first, :hash, :inspect, :last, :size, :step]
      ancestors head: [Enumerator::ArithmeticSequence, Enumerator, Enumerable, Object]
      range %: Enumerator::ArithmeticSequence
      numeric step: Enumerator::ArithmeticSequence
      string range: Enumerator
      parts: [1, 10, 2, false]
      exclusive parts: [10, true]
      endless end: nil
      numeric exclude_end?: false
      inspect range: ((1..10).step(2))
      inspect exclusive: ((1...10).step(2))
      inspect endless: ((1..).step(2))
      inspect %: ((1..10).%(2))
      inspect float: ((1.0..2.0).step(0.5))
      inspect numeric: (1.step(10, 3))
      inspect bare: (1.step)
      inspect kwargs: (1.step(to: 9, by: 2))
      inspect rational: (1/2.step((5/2), (1/2)))
      each self: true
      each yielded: [1, 3, 5, 7, 9]
      each blockless: Enumerator::ArithmeticSequence
      to_a: [1, 3, 5, 7, 9]
      map: [10, 30, 50, 70, 90]
      float walk: [0.0, 0.1, 0.2, 0.30000000000000004, 0.4, 0.5, 0.6000000000000001, 0.7000000000000001, 0.8, 0.9, 1.0]
      numeric float walk: [0.0, 0.1, 0.2, 0.30000000000000004, 0.4, 0.5, 0.6000000000000001, 0.7000000000000001, 0.8, 0.9, 1.0]
      mixed walk: [1.0, 1.5, 2.0]
      rational walk: [(1/2), (1/1), (3/2), (2/1), (5/2)]
      descending: [10, 8, 6, 4, 2]
      against direction: []
      endless take: [1, 3, 5, 7]
      size: 5
      size exclusive: 3
      size float: 11
      size float exclusive: 4
      size mixed: 5
      size empty: 0
      size descending: 5
      size endless: Infinity
      size rational: 5
      first: 1
      first mixed: 1
      first n mixed: [1.0, 3.0, 5.0]
      first empty: nil
      first zero: []
      first over: [1, 3, 5, 7, 9]
      first negative: attempt to take negative size
      last: 9
      last n: [5, 7, 9]
      last over: [1, 3, 5, 7, 9]
      last exclusive: 7
      last n exclusive: [4, 7]
      last mixed: 9
      last walked: 9.0
      last empty: nil
      last rational: 5/2
      last negative: negative array size
      last endless: cannot get the last element of endless arithmetic sequence
      == same: true
      eql? same: true
      === same: true
      == float step: true
      hash float step: false
      hash same: true
      == exclusive: false
      == element: false
      == other: false
      aref: [1, 3, 5, 7, 9]
      aref endless: [0, 3, 6, 9]
      aref beginless: [0, 2, 4]
      aref negative bounds: [7, 9]
      aref descending: [9, 7, 5, 3, 1]
      aref descending exclusive: [9, 7, 5, 3]
      aref against direction: []
      aref exclusive: [0, 3, 6]
      aref float bounds: [1, 3, 5]
      aref float step: [0, 2, 4, 6, 8]
      aref numeric: [1, 3, 5, 7]
      aref stride 1: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
      aref stride 1 past end: nil
      aref slice: [1, 3, 5, 7]
      aref at end: []
      aref out of range: ((0..10).step(3)) out of range
      aref begin past end: ((11..12).step(2)) out of range
      aref zero stride: slice step cannot be zero
      zero step: step can't be 0
      zero numeric step: step can't be 0
      string step: Enumerator
      string step inspect: #<Enumerator: 1..5:step("x")>
      string step block: String can't be coerced into Integer
    OUT
  end

  it "boxed receiver enumerable surface" do
    result = zr(<<~'RUBY')
      # The Enumerable and Integer names a boxed receiver shares with its typed self:
      # a value that only reads poly (a container element, a widened local) had no arm
      # for these and raised NoMethodError naming the very class that defines them.
      a = [[3, 1, 2], nil][0]
      p a.minmax
      p a.tally
      p a.product([1])
      p a.combination(2).to_a
      p a.partition { |x| x > 1 }
      p a.group_by { |x| x.odd? }
      p a.each_with_object([]) { |x, m| m << x }
      p a.chunk_while { |x, y| y > x }.to_a
      p a.slice_when { |x, y| y < x }.to_a

      h = [{ a: 1, b: 2 }, nil][0]
      p h.sum { |k, v| v }
      p h.each_with_object({}) { |(k, v), m| m[v] = k }
      p h.minmax
      p h.group_by { |k, v| v.odd? }

      r = [(1..5), nil][0]
      p r.minmax
      p r.tally.size

      n = [42, nil][0]
      p n.digits
      p n.pred
      p n.bit_length
      p n.ceildiv(5)
      p n.pow(2)
      p n.gcdlcm(28)
      p n.size

      # the typed receivers keep answering as before
      p [3, 1, 2].minmax
      p({ a: 1 }.sum { |k, v| v })
      p 42.digits
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3]
      {3 => 1, 1 => 1, 2 => 1}
      [[3, 1], [1, 1], [2, 1]]
      [[3, 1], [3, 2], [1, 2]]
      [[3, 2], [1]]
      {true => [3, 1], false => [2]}
      [3, 1, 2]
      [[3], [1, 2]]
      [[3], [1, 2]]
      3
      {1 => :a, 2 => :b}
      [[:a, 1], [:b, 2]]
      {true => [[:a, 1]], false => [[:b, 2]]}
      [1, 5]
      5
      [2, 4]
      41
      6
      9
      1764
      [14, 84]
      8
      [1, 3]
      1
      [2, 4]
    OUT
  end

  it "builtin method parameter names" do
    result = zr(<<~'RUBY')
      # `Method#parameters` on a BUILTIN row names the parameters ruby names, and
      # names nothing where ruby names nothing.
      #
      # CLOSED 2026-08-24. The whole-surface census is zero: over 2,594 rows both
      # ruby 4.0.7 and zr declare, `#parameters` and `#arity` agree on every one.
      #
      # The mechanism landed 2026-08-21 -- the DSL spells a row's signature per NAME
      # (`params "fmt, buffer: nil"`) in ruby's own `def` spelling, and the ARITY
      # falls out of it, so a row that carries a spelling cannot disagree with
      # itself. A `ruby def` marks the row's own parameter list AS ruby's
      # signature, for the rows where the two lists say the same thing. Both are
      # opt-in, because deriving names from every list would invent
      # them for the 1,025 rows ruby names nothing on and misreport the 793 whose
      # body shape differs on purpose.
      #
      # What was left then was 46 rows -- Pathname (41) and Kernel (5) -- deferred
      # to a vendored corelib that would carry CRuby's real signatures. The corelib
      # was DROPPED, so they were annotated by hand instead, which the measurement
      # says was the right trade anyway: the Ruby route ran 22.7x slower than the
      # native rows and cost 3.5x the bytes, and bought only these signatures.
      #
      # Five clusters closed it, and three were not on that list of 46:
      #
      #   * Pathname, 44 rows. CRuby writes it in Ruby, so it reports real names.
      #     20 rows took a `ruby def` (the native parameter names already matched);
      #     the rest needed `params "..."`, because the body's shape genuinely
      #     differs -- `def "read" params "*, **, &" (recv, *rest)`.
      #
      #   * Kernel, 7 rows. `require` is asymmetric: `Kernel#require` names its
      #     parameter and `Kernel.require` does not, because CRuby defines the two
      #     separately -- so it is two defs here rather than one `module_function`.
      #
      #   * `Dir#initialize`, `Hash#initialize`, `Time#initialize`, whose C
      #     functions declare real signatures.
      #
      #   * Every exception class that declares its own `initialize`. All twelve
      #     bypass the `ruby_class!` DSL, so they reached no table at all and
      #     answered `[] / 0` where ruby says `[[:rest]] / -1`.
      #
      #   * A generated WRITER. ruby names an `attr_accessor` slot NOTHING and a
      #     Struct member's slot `_`; zr spelled both `value`. Both are the same
      #     generated accessor here, so the attr slot became `__value` (which
      #     `param_entries` reports anonymously) and the struct fold renames its
      #     slot after lowering -- keeping the mark that elides the frame.
      #
      # The sweeps are `tests/builtin_rows_report_rubys_signature.rb` and
      # `tests/an_accessor_reports_rubys_parameter_name.rb`, plus the per-row
      # tables for Pathname, Kernel, Exception and Struct.
      # (`Kernel#require` is left out: the oracle runs under `bundler/setup`, whose
      # `bundled_gems.rb` replaces it with a Ruby method named `name`.)
      p method(:load).parameters
    RUBY

    _(result).must_answer "[[:rest]]\n"
  end

  it "builtin protected rows" do
    result = zr(<<~'RUBY')
      # A BUILTIN row declared `protected` read as public. The DSL parsed
      # `private`/`protected` in front of a `def`, but the generated method table
      # carried ONE bit -- `is_private` -- so `protected` collapsed into public: the
      # method answered an outside caller, `protected_instance_methods` was empty,
      # and `public_instance_methods` listed it.
      #
      # The table now carries the third state (`is_protected`, a companion fn rather
      # than a widened `is_private`, because the readers ask the two questions
      # separately), and both reflection readers plus `instance_method_visibility`
      # consult it. Enforcement then comes for free: the explicit-receiver barrier
      # already reads that one function.
      #
      # `Pathname#path` is the whole population today -- ruby makes it protected so
      # `#to_s` is the way to spell a path out loud.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("calling it") { Pathname.new("a").path }
      show("protected_instance_methods") { Pathname.protected_instance_methods(false) }
      show("public lists it") { Pathname.public_instance_methods(false).include?(:path) }
      show("instance_methods lists it") { Pathname.instance_methods(false).include?(:path) }

      # A Ruby-defined protected method is enforced, which is what makes this a
      # builtin-table gap rather than a dispatch one.
      class Probe
        protected def secret = 1
      end
      show("ruby-defined protected") { Probe.new.secret }

      # A protected builtin row IS reachable when the CALLER's self is a kind of the
      # owner, which is the whole point of the third state rather than a second
      # flavour of private. Spelled as a REOPEN, because zr decides the caller from
      # the class the call site sits in -- a compile-time answer, so `instance_eval`
      # does not move it (see tests/gaps/protected_reach_from_instance_eval.rb).
      class Pathname
        def same_path?(other) = path == other.path
      end
      show("kin caller") { Pathname.new("a").same_path?(Pathname.new("a")) }
      show("kin caller differs") { Pathname.new("a").same_path?(Pathname.new("b")) }
      show("non-kin caller") { Object.new.instance_eval { Pathname.new("b").path } }
      show("send reaches it") { Pathname.new("a").send(:path) }
      show("public_send does not") { Pathname.new("a").public_send(:path) }
      show("respond_to?") { Pathname.new("a").respond_to?(:path) }
      show("respond_to? all") { Pathname.new("a").respond_to?(:path, true) }
      show("protected_method_defined?") { Pathname.protected_method_defined?(:path) }
      show("private_method_defined?") { Pathname.private_method_defined?(:path) }
      show("public_method_defined?") { Pathname.public_method_defined?(:path) }
    RUBY

    _(result).must_answer <<~'OUT'
      calling it: NoMethodError: protected method 'path' called for an instance of Pathname
      protected_instance_methods: [:path]
      public lists it: false
      instance_methods lists it: true
      ruby-defined protected: NoMethodError: protected method 'secret' called for an instance of Probe
      kin caller: true
      kin caller differs: false
      non-kin caller: NoMethodError: protected method 'path' called for an instance of Pathname
      send reaches it: "a"
      public_send does not: NoMethodError: protected method 'path' called for an instance of Pathname
      respond_to?: false
      respond_to? all: true
      protected_method_defined?: true
      private_method_defined?: false
      public_method_defined?: false
    OUT
  end

  it "builtin reopen string blank dispatches everywhere" do
    result = zr(<<~'RUBY')
      # The Box docs' motivating example shape: a fresh method on `class String`,
      # dispatching statically ("".blank?), dynamically through a Poly ivar
      # (@s.blank?), and calling a NATIVE builtin method (`length`) implicitly on
      # self from inside the reopen.

      class String
        def blank?
          length == 0
        end
      end

      class Foo
        def initialize(s)
          @s = s
        end

        def foo_is_blank?
          @s.blank?
        end
      end

      puts "".blank?
      puts "  hi".blank?
      puts Foo.new("").foo_is_blank?
      puts Foo.new("x").foo_is_blank?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
    OUT
  end

  it "builtin reopen with matching superclass clause" do
    result = zr(<<~'RUBY')
      # A builtin reopen may RESTATE the class's real superclass (`class String <
      # Object`); the methods attach exactly as a clauseless reopen (D3).

      class String < Object
        def shout
          upcase + "!"
        end
      end
      puts "hi".shout
    RUBY

    _(result).must_answer "HI!\n"
  end

  it "builtin row claims the name" do
    result = zr(<<~'RUBY')
      # A NATIVE row on a class claims its name in the MRO exactly as a `def` does.
      # `Array#none?` and `Array#size` are native builtins with no user scope, and a
      # `module Enumerable` reopen does not take a name `Array` owns. Ruby puts
      # `Array` first in the ancestry and its own definition wins.

      # A user REOPEN of the builtin outranks the native row it replaces. Written
      # up top so the whole file reads one answer -- when the reopen wins is the
      # separate question `a_later_def_on_a_builtin_reaches_back` pins.
      class Array
        def take_while; :array_own; end
      end

      module Enumerable
        def take_while; :enum_take_while; end
        def none?; :enum_none; end
        def size; :enum_size; end
        def zzz_only_here; :enum_only; end
      end

      # Array owns both natively, so the module reopen loses.
      p [1].take_while { true }
      p [1].none?
      p [1].size
      p [].none? { |x| x > 9 }
      # ... but a name only the module has still reaches.
      p [1].zzz_only_here

      # Every other Enumerable host answers from its own native row too.
      p({ a: 1 }.size)
      p((1..3).size)
      S0 = Struct.new(:a)
      p S0.new(1).size

      # The claim is per-ancestor, so a subclass inherits the winner.
      class MyArr < Array; end
      p MyArr.new.none?
      p MyArr.new.size

      module M1
        def size; :m1; end
      end

      # `prepend` sits AHEAD of the class, so it beats the native row.
      class WithPrepend < Array
        prepend M1
      end
      p WithPrepend.new.size

      # `include` in a SUBCLASS also sits ahead of the parent's native row.
      class WithInclude < Array
        include M1
      end
      p WithInclude.new.size

      # `include` in the class ITSELF sits behind its own rows.
      class Array
        include M1
      end
      p [1, 2].size

      # A name the host does NOT own natively still comes from the module.
      module Comparable
        def between?(a, b); :cmp_between; end
      end
      p 5.between?(1, 9)
      p 5.clamp(1, 3)

      module Kernel
        def frozen?; :kernel_frozen; end
      end
      p "x".frozen?
      p Object.new.frozen?

    RUBY

    _(result).must_answer <<~'OUT'
      :array_own
      false
      1
      true
      :enum_only
      1
      3
      1
      true
      0
      :m1
      :m1
      2
      :cmp_between
      3
      :kernel_frozen
      :kernel_frozen
    OUT
  end

  it "class new dispatch arity" do
    result = zr(<<~'RUBY')
      # Class-object `.new` dispatch (zero-arg) only builds classes whose initialize
      # takes no required args; an arg-requiring constructor is omitted (as MRI
      # raises ArgumentError for it), and a value-type class is built by value, not
      # as a heap pointer.
      class A
        def initialize; @v = "a"; end
        def v; @v; end
      end
      class Other
        def initialize(x); @x = x; end
        def x; @x; end
      end
      class Rel
        def initialize(model); @model = model; end
        def build; @model.new; end
      end
      puts Rel.new(A).build.v
      puts Other.new("keep").x

      # an optional-arg constructor is zero-arg-compatible: its arm fills the
      # default
      class WithOpt
        def initialize(attrs = {}); @attrs = attrs; end
        def size; @attrs.length; end
      end
      class WithOpt2
        def initialize(attrs = {}); @attrs = attrs; end
        def size; @attrs.length + 1; end
      end
      class Maker
        def initialize(model); @model = model; end
        def build; @model.new; end
      end
      puts Maker.new(WithOpt).build.size
      puts Maker.new(WithOpt2).build.size
    RUBY

    _(result).must_answer <<~'OUT'
      a
      keep
      0
      1
    OUT
  end

  it "comparable and kernel rows reach builtin values" do
    result = zr(<<~'RUBY')
      # Comparable's operators and Kernel's universals reach builtin values
      # dynamically: `"abc" < "abd"` resolves String(no `<`) -> Comparable(`<`
      # drives `<=>`) -> `String#<=>`; itself/tap/then/frozen?/eql?/equal? are
      # Kernel/BasicObject rows found through every value's chain.

      x = "abc"
      puts x < "abd"
      puts x.between?("aaa", "b")
      puts "m".clamp("a", "f")
      puts 5.itself
      r = 5.tap { |v| puts "saw #{v}" }
      puts r
      puts 5.then { |v| v + 1 }
      puts 5.equal?(5)
      puts 5.send("itself")
      puts 5.frozen?
      puts "x".frozen?
      puts 5.eql?(5.0)
      puts 5.eql?(5)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      f
      5
      saw 5
      5
      6
      true
      5
      true
      false
      false
      true
    OUT
  end

  it "comparable clamp parity" do
    result = zr(<<~'RUBY')
      # Comparable#clamp parity for user classes: reversed bounds raise, nil bounds
      # clamp one-sided, the range form accepts Integer endpoints (a clamped result
      # IS that endpoint), an exclusive range raises, and a poly receiver routes
      # through the user <=>. Receivers go through per-shape helper defs to defeat
      # constant folding.
      class Money
        include Comparable
        attr_reader :cents
        def initialize(cents); @cents = cents; end
        def <=>(other)
          v = other.is_a?(Money) ? other.cents : (other.is_a?(Integer) ? other : nil)
          v.nil? ? nil : (cents <=> v)
        end
      end

      def money_id(x); x; end
      def poly_id(x); x; end
      def int_id(x); x; end

      # reversed bounds raise
      begin
        money_id(Money.new(20)).clamp(Money.new(30), Money.new(10))
      rescue ArgumentError => e
        puts e.message
      end

      # nil bounds clamp one-sided (the nil side is never returned, so the result
      # keeps the receiver's class)
      p money_id(Money.new(5)).clamp(Money.new(10), nil).cents
      p money_id(Money.new(5)).clamp(nil, Money.new(3)).cents
      p money_id(Money.new(5)).clamp(nil, Money.new(9)).cents

      # range form with Integer endpoints: the user <=> sees the Integer; a clamped
      # result is the Integer endpoint itself
      p money_id(Money.new(0)).clamp(1..5)
      p money_id(Money.new(9)).clamp(1..5)
      # in-range returns the receiver (not an endpoint); clamped returns the endpoint
      p money_id(Money.new(3)).clamp(1..5).is_a?(Integer)
      p money_id(Money.new(0)).clamp(1..5).is_a?(Integer)

      # beginless / endless ranges clamp one-sided
      p money_id(Money.new(9)).clamp(..5)
      p money_id(Money.new(0)).clamp(2..)

      # an exclusive range with a real end cannot clamp; exclusive endless can
      begin
        money_id(Money.new(3)).clamp(1...5)
      rescue ArgumentError => e
        puts e.message
      end
      p money_id(Money.new(0)).clamp(2...)

      # Integer receivers: exclusive range raises there too
      begin
        int_id(7).clamp(1...5)
      rescue ArgumentError => e
        puts e.message
      end
      p int_id(7).clamp(1..5)
      p int_id(7).clamp(1..)
      p int_id(0).clamp(..5)

      # a poly receiver holding a user object clamps via the user <=>
      p poly_id(Money.new(50)).clamp(Money.new(10), Money.new(30)).cents
      p (poly_id(Money.new(50)).clamp(10..30))
      begin
        poly_id(Money.new(3)).clamp(1...5)
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      min argument must be less than or equal to max argument
      10
      3
      5
      1
      5
      false
      true
      5
      2
      cannot clamp with an exclusive range
      2
      cannot clamp with an exclusive range
      5
      7
      0
      30
      30
      cannot clamp with an exclusive range
    OUT
  end

  it "comparator block arity" do
    result = zr(<<~'RUBY')
      # A comparator block that takes ONE parameter still gets both elements, so it
      # compares the first against nothing and answers a value unrelated to the pair.
      # Every pair then ties or contradicts, and the order that comes out is the sort
      # algorithm's rather than the program's -- which makes line 7 a pin on the
      # algorithm itself. It was a divergence until zr sorted through the same
      # `qsort_r` CRuby's `ruby_qsort` calls.

      p [1, 5, 3].max { |x| -x }
      p [3, 1, 2].sort { |x| 0 }
      p [3, 1, 2].sort { 0 }
      p [3, 1, 2].min { |x| 1 }
      p [3, 1, 2].sort { |a, b| b <=> a }
      p [3, 1, 2].max { |a, b| a <=> b }
      p %w[bb a ccc].sort { |x| x.length }
      p [2.5, 1.5].min { |x| -1 }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [3, 1, 2]
      [3, 1, 2]
      3
      [3, 2, 1]
      3
      ["ccc", "a", "bb"]
      1.5
    OUT
  end

  it "const env defined parity" do
    result = zr(<<~'RUBY')
      # Constant ||= typing, toplevel ivar op-assign, defined?(implicit method),
      # and ENV parity: fetch KeyError, nil-deletes, non-String TypeError, size.

      # `CONST ||= v` as the only definition types the constant
      LIMIT ||= 10
      puts LIMIT + 1

      # toplevel ivar compound assignment
      @count = 0
      @count += 1
      @count *= 5
      p @count

      # defined? sees an implicit-self method inside a class
      class Widget
        def name = "w"
        attr_reader :size
        def check
          [defined?(name), defined?(size), defined?(missing_thing)]
        end
      end
      p Widget.new.check

      # ENV.fetch with a default and with a KeyError
      ENV["SPINEL_PARITY_A"] = "set"
      p ENV.fetch("SPINEL_PARITY_A")
      p ENV.fetch("SPINEL_PARITY_MISSING", "fallback")
      begin
        ENV.fetch("SPINEL_PARITY_MISSING")
      rescue KeyError => e
        puts e.class
        puts e.message.lines.first
      end

      # ENV[k] = nil through a runtime value deletes
      def env_set(k, v); ENV[k] = v; end
      env_set("SPINEL_PARITY_A", nil)
      p ENV["SPINEL_PARITY_A"]

      # literal nil deletes too
      ENV["SPINEL_PARITY_B"] = "x"
      ENV["SPINEL_PARITY_B"] = nil
      p ENV["SPINEL_PARITY_B"]

      # non-String RHS raises TypeError naming the class
      def env_set_poly(v); ENV["SPINEL_PARITY_C"] = v; end
      vals = [7, "ok"]
      begin
        env_set_poly(vals[0])
      rescue TypeError => e
        puts "#{e.class}: #{e.message}"
      end
      env_set_poly(vals[1])
      p ENV["SPINEL_PARITY_C"]

      # ENV.size counts the environment
      p ENV.size > 0
      p ENV.length == ENV.size
    RUBY

    _(result).must_answer <<~'OUT'
      11
      5
      ["method", "method", nil]
      "set"
      "fallback"
      KeyError
      key not found: "SPINEL_PARITY_MISSING"
      nil
      nil
      TypeError: no implicit conversion of Integer into String
      "ok"
      true
      true
    OUT
  end

  it "const int rows destructure" do
    result = zr(<<~'RUBY')
      # A poly-array CONSTANT whose rows are all int-array literals (a frozen
      # direction table) destructures its 2+ block params as ints, so methods
      # called with the destructured values keep typed int params -- one such
      # call site must not poison every downstream caller (e.g. a hot
      # "#{x}-#{y}" key builder) onto the boxed slow path.
      DIRECTIONS = [
        [-1, -1], [-1, 0], [-1, 1],
        [0, -1], [0, 1],
        [1, -1], [1, 0], [1, 1],
      ].freeze

      def make_key(x, y)
        "#{x}-#{y}"
      end

      def neighbours(cx, cy)
        DIRECTIONS.filter_map do |rel_x, rel_y|
          nx = cx + rel_x
          ny = cy + rel_y
          next if nx < 0 || ny < 0
          make_key(nx, ny)
        end
      end

      p neighbours(1, 1)
      p neighbours(0, 0)
      p make_key(7, 8)

      # each with destructure over the same constant
      sum = 0
      DIRECTIONS.each { |dx, dy| sum += dx * 10 + dy }
      p sum

      # a non-uniform constant stays poly (no wrong narrowing)
      MIXED = [[1, 2], "s"].freeze
      kinds = MIXED.map { |m| m.class.to_s }
      p kinds
    RUBY

    _(result).must_answer <<~'OUT'
      ["0-0", "0-1", "0-2", "1-0", "1-2", "2-0", "2-1", "2-2"]
      ["0-1", "1-0", "1-1"]
      "7-8"
      0
      ["Array", "String"]
    OUT
  end

  it "Array.[] builds an array from its arguments, and an empty one from none" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "Array.[]: #{Array[1, 2, 3].inspect}"
      puts "Array.[] empty: #{Array[].inspect}"

    RUBY

    _(result).must_answer <<~'OUT'
      Array.[]: [1, 2, 3]
      Array.[] empty: []
    OUT
  end

  it "attached_object answers the object a singleton class belongs to" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "attached_object: #{String.singleton_class.attached_object}"
      begin
        Class.new.attached_object
      rescue TypeError => e
        puts "attached_object plain: #{e.message.sub(/0x\h+/, '0xADDR')}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      attached_object: String
      attached_object plain: '#<Class:0xADDR>' is not a singleton class
    OUT
  end

  it "Encoding.aliases maps an alias to its name, and locale_charmap answers a String" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "Encoding.aliases: #{Encoding.aliases['BINARY']}"
      puts "Encoding.locale_charmap: #{Encoding.locale_charmap.class}"
      puts "Encoding._dump: #{Encoding::UTF_8._dump(0)}"
      puts "Encoding._load: #{Encoding._load('UTF-8')}"
      # CRuby's `_load` answers what it was handed rather than the singleton.
      puts "Encoding._load class: #{Encoding._load('UTF-8').class}"

    RUBY

    _(result).must_answer <<~'OUT'
      Encoding.aliases: ASCII-8BIT
      Encoding.locale_charmap: String
      Encoding._dump: UTF-8
      Encoding._load: UTF-8
      Encoding._load class: String
    OUT
  end

  it "lazy.eager answers an Enumerator that forces the chain" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "lazy eager: #{[1, 2, 3].lazy.map { |x| x * 2 }.eager.class}"
      puts "lazy eager values: #{[1, 2, 3].lazy.map { |x| x * 2 }.eager.to_a.inspect}"

    RUBY

    _(result).must_answer <<~'OUT'
      lazy eager: Enumerator
      lazy eager values: [2, 4, 6]
    OUT
  end

  it "GC#garbage_collect is listed among GC's own instance methods" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "GC#garbage_collect listed: #{GC.instance_methods(false).include?(:garbage_collect)}"

    RUBY

    _(result).must_answer <<~'OUT'
      GC#garbage_collect listed: true
    OUT
  end

  it "ruby2_keywords_hash marks a Hash, and ruby2_keywords_hash? reads the mark" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      marked = Hash.ruby2_keywords_hash({ a: 1 })
      puts "ruby2_keywords_hash: #{marked.inspect}"
      puts "ruby2_keywords_hash? plain: #{Hash.ruby2_keywords_hash?({})}"

    RUBY

    _(result).must_answer <<~'OUT'
      ruby2_keywords_hash: {a: 1}
      ruby2_keywords_hash? plain: false
    OUT
  end

  it "Marshal.restore reads back what Marshal.dump wrote" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "Marshal.restore: #{Marshal.restore(Marshal.dump([1, 'two', :three])).inspect}"

    RUBY

    _(result).must_answer <<~'OUT'
      Marshal.restore: [1, "two", :three]
    OUT
  end

  it "Random.seed answers an Integer" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "Random.seed: #{Random.seed.is_a?(Integer)}"

    RUBY

    _(result).must_answer <<~'OUT'
      Random.seed: true
    OUT
  end

  it "Regexp.timeout reads and writes the global timeout" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "Regexp.timeout default: #{Regexp.timeout.inspect}"
      Regexp.timeout = 3
      puts "Regexp.timeout set: #{Regexp.timeout.inspect}"
      Regexp.timeout = nil
      puts "Regexp.timeout cleared: #{Regexp.timeout.inspect}"
      $_ = "hello world"
      puts "Regexp#~: #{~/world/}"
      puts "Regexp#~ miss: #{(~/nope/).inspect}"

    RUBY

    _(result).must_answer <<~'OUT'
      Regexp.timeout default: nil
      Regexp.timeout set: 3.0
      Regexp.timeout cleared: nil
      Regexp#~: 6
      Regexp#~ miss: nil
    OUT
  end

  it "compare_by_identity switches a Set to identity and answers the Set" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      s = Set[1, 2]
      puts "compare_by_identity? before: #{s.compare_by_identity?}"
      puts "compare_by_identity: #{s.compare_by_identity.class}"
      puts "compare_by_identity? after: #{s.compare_by_identity?}"

    RUBY

    _(result).must_answer <<~'OUT'
      compare_by_identity? before: false
      compare_by_identity: Set
      compare_by_identity? after: true
    OUT
  end

  it "unicode_normalize! normalizes the receiver in place" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      str = +"é"
      puts "unicode_normalize!: #{str.unicode_normalize!(:nfc).bytes.inspect}"
      puts "unicode_normalize! in place: #{str.bytes.inspect}"

    RUBY

    _(result).must_answer <<~'OUT'
      unicode_normalize!: [195, 169]
      unicode_normalize! in place: [195, 169]
    OUT
  end

  it "Symbol.all_symbols answers an Array of the symbols in use" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "Symbol.all_symbols: #{Symbol.all_symbols.is_a?(Array)}"
      puts "Symbol.all_symbols has one: #{Symbol.all_symbols.include?(:all_symbols_probe_sym)}"

    RUBY

    _(result).must_answer <<~'OUT'
      Symbol.all_symbols: true
      Symbol.all_symbols has one: true
    OUT
  end

  it "Warning.categories names the categories, and Warning#warn is listed" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "Warning.categories: #{Warning.categories.include?(:deprecated)}"
      puts "Warning#warn listed: #{Warning.instance_methods(false).inspect}"

    RUBY

    _(result).must_answer <<~'OUT'
      Warning.categories: true
      Warning#warn listed: [:warn]
    OUT
  end

  it "Process::Tms names its four members" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "Process::Tms.members: #{Process::Tms.members.inspect}"
      puts "Process::Tms.keyword_init?: #{Process::Tms.keyword_init?.inspect}"
      tms = Process::Tms[1, 2, 3, 4]
      puts "Process::Tms.[]: #{tms.inspect}"
      tms.utime = 9.5
      puts "Process::Tms writer: #{tms.utime}"
      puts "Process::Tms to_a: #{tms.to_a.inspect}"

    RUBY

    _(result).must_answer <<~'OUT'
      Process::Tms.members: [:utime, :stime, :cutime, :cstime]
      Process::Tms.keyword_init?: nil
      Process::Tms.[]: #<struct Process::Tms utime=1, stime=2, cutime=3, cstime=4>
      Process::Tms writer: 9.5
      Process::Tms to_a: [9.5, 2, 3, 4]
    OUT
  end

  it "Process::Status.wait answers a Status for the child it waited on" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      pid = Process.spawn("true")
      st = Process::Status.wait(pid)
      puts "Status.wait: #{st.class}"
      puts "Status.wait exit: #{st.exitstatus}"
      puts "Status coredump?: #{st.coredump?}"
      puts "Status stopsig: #{st.stopsig.inspect}"

    RUBY

    _(result).must_answer <<~'OUT'
      Status.wait: Process::Status
      Status.wait exit: 0
      Status coredump?: false
      Status stopsig: nil
    OUT
  end

  it "a Queue answers num_waiting, clear and size" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      q = Thread::Queue.new
      q << 1
      q << 2
      puts "Queue num_waiting: #{q.num_waiting}"
      puts "Queue clear: #{q.clear.class}"
      puts "Queue size after clear: #{q.size}"
      begin
        q.marshal_dump
      rescue TypeError => e
        puts "Queue marshal_dump: #{e.message}"
      end
      begin
        Thread::ConditionVariable.new.marshal_dump
      rescue TypeError => e
        puts "CV marshal_dump: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      Queue num_waiting: 0
      Queue clear: Thread::Queue
      Queue size after clear: 0
      Queue marshal_dump: can't dump Thread::Queue
      CV marshal_dump: can't dump Thread::ConditionVariable
    OUT
  end

  it "a SizedQueue answers num_waiting and clear as a Queue does" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      sq = Thread::SizedQueue.new(2)
      puts "SizedQueue num_waiting: #{sq.num_waiting}"
      sq << 1
      puts "SizedQueue clear: #{sq.clear.class}"

    RUBY

    _(result).must_answer <<~'OUT'
      SizedQueue num_waiting: 0
      SizedQueue clear: Thread::SizedQueue
    OUT
  end

  it "Mutex#sleep answers nil and leaves the mutex locked" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      m = Thread::Mutex.new
      m.lock
      puts "Mutex#sleep: #{m.sleep(0.001).inspect}"
      puts "Mutex still locked: #{m.locked?}"
      m.unlock

    RUBY

    _(result).must_answer <<~'OUT'
      Mutex#sleep: nil
      Mutex still locked: true
    OUT
  end

  it "ThreadGroup#enclose marks the group, and enclosed? reads the mark" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      g = ThreadGroup.new
      puts "ThreadGroup enclosed? before: #{g.enclosed?}"
      puts "ThreadGroup enclose: #{g.enclose.class}"
      puts "ThreadGroup enclosed? after: #{g.enclosed?}"
      puts "Default enclosed?: #{ThreadGroup::Default.enclosed?}"

    RUBY

    _(result).must_answer <<~'OUT'
      ThreadGroup enclosed? before: false
      ThreadGroup enclose: ThreadGroup
      ThreadGroup enclosed? after: true
      Default enclosed?: false
    OUT
  end

  it "the top-level Queue, Mutex and SizedQueue are the Thread:: ones" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      puts "top-level Queue: #{Queue.equal?(Thread::Queue)}"
      puts "top-level Mutex: #{Mutex.equal?(Thread::Mutex)}"
      puts "top-level SizedQueue: #{SizedQueue.equal?(Thread::SizedQueue)}"
      puts "top-level ConditionVariable: #{ConditionVariable.equal?(Thread::ConditionVariable)}"
      puts "RUBY_COPYRIGHT: #{RUBY_COPYRIGHT.start_with?('ruby - Copyright')}"
      puts "File::Separator: #{File::Separator.inspect}"

    RUBY

    _(result).must_answer <<~'OUT'
      top-level Queue: true
      top-level Mutex: true
      top-level SizedQueue: true
      top-level ConditionVariable: true
      RUBY_COPYRIGHT: true
      File::Separator: "/"
    OUT
  end

  it "Dir#chdir with a block returns to where it was, and chroot raises EPERM" do
    result = zr(<<~'RUBY')
      # The long tail: one row apiece across Array, Class, Dir, Encoding,

      # Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
      # Symbol, Warning and the Thread family.

      require "set"
      require "tmpdir"

      Dir.mktmpdir do |dir|
        Dir.open(dir) do |d|
          inside = d.chdir { File.basename(Dir.pwd) }
          puts "Dir#chdir block: #{inside == File.basename(dir)}"
        end
      end
      begin
        Dir.chroot("/nonexistent-zr-probe")
      rescue SystemCallError => e
        puts "Dir.chroot: #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Dir#chdir block: true
      Dir.chroot: Errno::EPERM
    OUT
  end

  it "dynamic dispatch wrong arity raises a rescuable argument error" do
    result = zr(<<~'RUBY')
      # On an arity mismatch, `send` raises a RESCUABLE ArgumentError, as Ruby
      # does. The program survives every mismatch and the final line prints.
      # All three message shapes -- fixed `N`, range `N..M`, and the rest form
      # `N+` -- are oracle-verified against ruby 4.0.7.

      class A
        def fixed(a) = a
        def rng(a, b = 2) = a + b
        def restp(a, *b) = a
      end
      o = A.new
      [[:fixed, []], [:fixed, [1, 2]], [:rng, []], [:rng, [1, 2, 3]], [:restp, []]].each do |m, args|
        begin
          o.send(m, *args)
        rescue ArgumentError => e
          puts "#{m}: #{e.message}"
        end
      end
      puts "survived"
    RUBY

    _(result).must_answer <<~'OUT'
      fixed: wrong number of arguments (given 0, expected 1)
      fixed: wrong number of arguments (given 2, expected 1)
      rng: wrong number of arguments (given 0, expected 1..2)
      rng: wrong number of arguments (given 3, expected 1..2)
      restp: wrong number of arguments (given 0, expected 1+)
      survived
    OUT
  end

  it "encoding error rows" do
    result = zr(<<~'RUBY')
      # The two conversion errors carry the encoding pair and the offending input on
      # the exception, not only inside the message.

      begin
        "\xC2".dup.force_encoding("UTF-8").encode("Shift_JIS")
      rescue Encoding::InvalidByteSequenceError => e
        puts "invalid class: #{e.class}"
        puts "invalid source: #{e.source_encoding}"
        puts "invalid source name: #{e.source_encoding_name}"
        puts "invalid destination: #{e.destination_encoding}"
        puts "invalid destination name: #{e.destination_encoding_name}"
        puts "invalid bytes: #{e.error_bytes.inspect}"
        puts "invalid incomplete?: #{e.incomplete_input?}"
        puts "invalid readagain: #{e.readagain_bytes.inspect}"
      end

      begin
        "é".encode("US-ASCII")
      rescue Encoding::UndefinedConversionError => e
        puts "undef class: #{e.class}"
        puts "undef source: #{e.source_encoding}"
        puts "undef source name: #{e.source_encoding_name}"
        puts "undef destination: #{e.destination_encoding}"
        puts "undef destination name: #{e.destination_encoding_name}"
        puts "undef char: #{e.error_char.inspect}"
      end

      # Reflection files each accessor on the class CRuby owns it on -- and an
      # ordinary subclass owns none of them.
      puts "invalid own: #{Encoding::InvalidByteSequenceError.instance_methods(false).sort.inspect}"
      puts "undef own: #{Encoding::UndefinedConversionError.instance_methods(false).sort.inspect}"
      # `respond_to?` is the one row zr files on Kernel rather than Exception -- an
      # accepted owner divergence in the census, subtracted so the rest can be exact.
      puts "Exception own: #{(Exception.instance_methods(false).sort - [:respond_to?]).inspect}"
      # `#initialize` is Exception's and PRIVATE, so it appears here and in neither
      # public listing. (zr files `method_missing`/`respond_to_missing?` on
      # BasicObject rather than restating them here, which reflection does not gate.)
      puts "Exception private initialize: #{Exception.private_instance_methods(false).include?(:initialize)}"
      puts "KeyError own: #{KeyError.instance_methods(false).sort.inspect}"
      puts "NameError own: #{NameError.instance_methods(false).sort.inspect}"

      class PlainError < StandardError; end
      puts "user subclass own: #{PlainError.instance_methods(false).inspect}"
      puts "StandardError own: #{StandardError.instance_methods(false).inspect}"

      # `Exception#backtrace_locations` is `#backtrace`'s object form.
      begin
        raise "boom"
      rescue => e
        puts "locations class: #{e.backtrace_locations.class}"
        puts "locations first: #{e.backtrace_locations.first.class}"
        puts "locations agree: #{e.backtrace_locations.size == e.backtrace.size}"
        puts "location lineno: #{e.backtrace_locations.first.lineno.is_a?(Integer)}"
      end
      puts "unraised locations: #{RuntimeError.new('x').backtrace_locations.inspect}"

      # `NoMatchingPatternKeyError` carries the key and the Hash it was asked of.
      err = NoMatchingPatternKeyError.new(matchee: { a: 1 }, key: :b)
      puts "pattern key: #{err.key.inspect}"
      puts "pattern matchee: #{err.matchee.inspect}"
      puts "pattern message: #{err.message}"
      bare = NoMatchingPatternKeyError.new
      begin
        bare.key
      rescue ArgumentError => e
        puts "pattern bare key: #{e.message}"
      end
      begin
        bare.matchee
      rescue ArgumentError => e
        puts "pattern bare matchee: #{e.message}"
      end

      begin
        nil.no_such_method
      rescue NameError => e
        puts "name error locals: #{e.local_variables.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      invalid class: Encoding::InvalidByteSequenceError
      invalid source: UTF-8
      invalid source name: UTF-8
      invalid destination: Shift_JIS
      invalid destination name: Shift_JIS
      invalid bytes: "\xC2"
      invalid incomplete?: true
      invalid readagain: nil
      undef class: Encoding::UndefinedConversionError
      undef source: UTF-8
      undef source name: UTF-8
      undef destination: US-ASCII
      undef destination name: US-ASCII
      undef char: "é"
      invalid own: [:destination_encoding, :destination_encoding_name, :error_bytes, :incomplete_input?, :readagain_bytes, :source_encoding, :source_encoding_name]
      undef own: [:destination_encoding, :destination_encoding_name, :error_char, :source_encoding, :source_encoding_name]
      Exception own: [:==, :backtrace, :backtrace_locations, :cause, :detailed_message, :exception, :full_message, :inspect, :message, :set_backtrace, :to_s]
      Exception private initialize: true
      KeyError own: [:key, :receiver]
      NameError own: [:local_variables, :name, :receiver]
      user subclass own: []
      StandardError own: []
      locations class: Array
      locations first: Thread::Backtrace::Location
      locations agree: true
      location lineno: true
      unraised locations: nil
      pattern key: :b
      pattern matchee: {a: 1}
      pattern message: NoMatchingPatternKeyError
      pattern bare key: no key is available
      pattern bare matchee: no matchee is available
      name error locals: Array
    OUT
  end

  it "encoding surface reports transcodes and raises" do
    result = zr(<<~'RUBY')
      # The Encoding engine: a string is bytes + an encoding, queryable and
      # transcodable, with the Encoding class and its constants. `__ENCODING__`
      # answers the script encoding (UTF-8). Cross-checked against ruby 4.0.7.

      p "hello".encoding
      p __ENCODING__
      p "€".bytesize
      p "€".length
      p "hello".ascii_only?
      p "€".ascii_only?
      p Encoding::UTF_8.name
      p Encoding::ASCII_8BIT.names
      p Encoding.find("BINARY")
      p Encoding.default_external
      raw = "€".b
      p raw.encoding
      p raw.length
      mis = "€".dup.force_encoding("US-ASCII")
      p mis.valid_encoding?
      latin = "café".encode(Encoding::ISO_8859_1)
      p latin.encoding
      p latin.bytes
      p latin.encode(Encoding::UTF_8) == "café"
      p "café".encode(Encoding::US_ASCII, undef: :replace)
      p "a<b>&c".encode(Encoding::US_ASCII, xml: :text)
      begin
        "café".encode(Encoding::US_ASCII)
      rescue Encoding::UndefinedConversionError => e
        puts "raised #{e.class}"
      end
      p :hi.encoding
      p :café.encoding
    RUBY

    _(result).must_answer <<~'OUT'
      #<Encoding:UTF-8>
      #<Encoding:UTF-8>
      3
      1
      true
      false
      "UTF-8"
      ["ASCII-8BIT", "BINARY"]
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:UTF-8>
      #<Encoding:BINARY (ASCII-8BIT)>
      3
      false
      #<Encoding:ISO-8859-1>
      [99, 97, 102, 233]
      true
      "caf?"
      "a&lt;b&gt;&amp;c"
      raised Encoding::UndefinedConversionError
      #<Encoding:US-ASCII>
      #<Encoding:UTF-8>
    OUT
  end

  it "enumerator callee and size surface" do
    result = zr(<<~'RUBY')
      # An Enumerator records the ALIAS actually called (CRuby captures
      # `__callee__`), and its size comes from the size function the METHOD supplies
      # -- so `[1, 2].each.size` is 2 while `[1, 2].to_enum(:each).size` is nil.
      p [1,2].each.size, [1,2].map.size, [1,2].select.size, [1,2].each_slice(2).size, [1,2].each_cons(2).size
      p [1,2].to_enum(:each).size, [1,2].enum_for(:each).size, [1,2].enum_for(:each) { 9 }.size
      p 3.times.size, 3.times.to_enum.size
      p [1,2].cycle.size, [1,2].cycle(3).size, [].cycle.size, [1,2].cycle(0).size
      p [1,2].map.inspect, [1,2].collect.inspect, [1,2].select.inspect, [1,2].filter.inspect, [1,2].find_all.inspect
      p [1,2].reject.inspect, [1,2].each_entry.inspect
      p({ a: 1 }.each.inspect)
      p({ a: 1 }.each_pair.inspect)
      p({ a: 1 }.select!.inspect)
      p({ a: 1 }.filter!.inspect)
      p({ a: 1 }.keep_if.inspect)
      p({ a: 1 }.reject!.inspect)
      p({ a: 1 }.delete_if.inspect)
      p [1,2].map!.inspect, [1,2].collect!.inspect, [1,2].select!.inspect, [1,2].filter!.inspect, [1,2].keep_if.inspect
      p [1,2].flat_map.inspect, [1,2].collect_concat.inspect
      p [1,2].detect.inspect, [1,2].find.inspect
      p [1,2].each_with_index.size, [1,2].each_with_object(0).size
      p [1,2].map { |x| x * 2 }, [1,2].collect { |x| x }, [1,2].select { |x| x > 1 }, [1,2].find_all { |x| x > 1 }
      p({ a: 1, b: 2 }.select { |k, v| v > 1 })
      p [1,2,3].select! { |x| x > 1 }
      h = {a: 1, b: 2}; h.keep_if { |k,v| v > 1 }; p h
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      2
      1
      1
      nil
      nil
      9
      3
      nil
      Infinity
      6
      0
      0
      "#<Enumerator: [1, 2]:map>"
      "#<Enumerator: [1, 2]:collect>"
      "#<Enumerator: [1, 2]:select>"
      "#<Enumerator: [1, 2]:filter>"
      "#<Enumerator: [1, 2]:find_all>"
      "#<Enumerator: [1, 2]:reject>"
      "#<Enumerator: [1, 2]:each_entry>"
      "#<Enumerator: {a: 1}:each>"
      "#<Enumerator: {a: 1}:each_pair>"
      "#<Enumerator: {a: 1}:select!>"
      "#<Enumerator: {a: 1}:filter!>"
      "#<Enumerator: {a: 1}:keep_if>"
      "#<Enumerator: {a: 1}:reject!>"
      "#<Enumerator: {a: 1}:delete_if>"
      "#<Enumerator: [1, 2]:map!>"
      "#<Enumerator: [1, 2]:collect!>"
      "#<Enumerator: [1, 2]:select!>"
      "#<Enumerator: [1, 2]:filter!>"
      "#<Enumerator: [1, 2]:keep_if>"
      "#<Enumerator: [1, 2]:flat_map>"
      "#<Enumerator: [1, 2]:collect_concat>"
      "#<Enumerator: [1, 2]:detect>"
      "#<Enumerator: [1, 2]:find>"
      2
      2
      [2, 4]
      [1, 2]
      [2]
      [2]
      {b: 2}
      [2, 3]
      {b: 2}
    OUT
  end

  it "enumerator chain product rows" do
    result = zr(<<~'RUBY')
      # `Enumerator::Chain` and `::Product` add no behaviour of their own -- what
      # they answer comes down the chain from `Enumerator`. ruby OWNS these four on
      # each subclass all the same, which is what these rows make true.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("Chain own rows") { Enumerator::Chain.instance_methods(false).sort }
      show("Product own rows") { Enumerator::Product.instance_methods(false).sort }
      show("Chain each owner") { Enumerator::Chain.instance_method(:each).owner }
      show("Product each owner") { Enumerator::Product.instance_method(:each).owner }
      show("Chain ancestors") { Enumerator::Chain.ancestors.take(4) }
      show("Product ancestors") { Enumerator::Product.ancestors.take(4) }
      show("Chain arities") { %i[each inspect rewind size].to_h { |m| [m, Enumerator::Chain.instance_method(m).arity] } }
      show("Product arities") { %i[each inspect rewind size].to_h { |m| [m, Enumerator::Product.instance_method(m).arity] } }

      chain = [1, 2].each + [3].each
      show("chain class") { chain.class }
      show("chain to_a") { chain.to_a }
      show("chain size") { chain.size }
      show("chain inspect") { chain.inspect }
      show("chain rewind") { chain.rewind.class }
      show("chain each block") { r = []; chain.each { |x| r << x }; r }

      prod = Enumerator.product([1, 2], [3, 4])
      show("product class") { prod.class }
      show("product to_a") { prod.to_a }
      show("product size") { prod.size }
      show("product rewind") { prod.rewind.class }
      show("product each block") { r = []; prod.each { |a| r << a }; r }
    RUBY

    _(result).must_answer <<~'OUT'
      Chain own rows: [:each, :inspect, :rewind, :size]
      Product own rows: [:each, :inspect, :rewind, :size]
      Chain each owner: Enumerator::Chain
      Product each owner: Enumerator::Product
      Chain ancestors: [Enumerator::Chain, Enumerator, Enumerable, Object]
      Product ancestors: [Enumerator::Product, Enumerator, Enumerable, Object]
      Chain arities: {each: -1, inspect: 0, rewind: 0, size: 0}
      Product arities: {each: 0, inspect: 0, rewind: 0, size: 0}
      chain class: Enumerator::Chain
      chain to_a: [1, 2, 3]
      chain size: 3
      chain inspect: "#<Enumerator::Chain: [#<Enumerator: [1, 2]:each>, #<Enumerator: [3]:each>]>"
      chain rewind: Enumerator::Chain
      chain each block: [1, 2, 3]
      product class: Enumerator::Product
      product to_a: [[1, 3], [1, 4], [2, 3], [2, 4]]
      product size: 4
      product rewind: Enumerator::Product
      product each block: [[1, 3], [1, 4], [2, 3], [2, 4]]
    OUT
  end

  it "env hash and enumerable surface" do
    result = zr(<<~'RUBY')
      # `ENV`'s own singleton rows and the Enumerable half its singleton class
      # includes. Both matter for dispatch: ENV's class IS `Object`, so a row it
      # does not declare falls through to `Object`/`Kernel` -- which is how
      # `ENV.select` once reached the private `Kernel#select`.
      ENV.keys.each { |k| ENV.delete(k) unless k == "PATH" }
      ENV["ZR_TEST_A"] = "1"
      ENV["ZR_TEST_B"] = "2"

      p ENV.select { |k, v| k.start_with?("ZR_TEST_") }
      p ENV.filter { |k, v| k.start_with?("ZR_TEST_") }
      p ENV.reject { |k, v| !k.start_with?("ZR_TEST_") }
      p ENV.select { |k, v| false }
      p ENV.select.class, ENV.each_key.class, ENV.each_value.class
      p ENV.to_a.class, ENV.to_a.include?(["ZR_TEST_A", "1"])
      p ENV.invert["1"], ENV.rassoc("1")
      p ENV.has_value?("1"), ENV.value?("2"), ENV.value?("nope-zzz")
      p ENV.except("PATH", "ZR_TEST_B")
      p ENV.rehash

      ks = []
      ENV.each_key { |k| ks << k }
      p ks.include?("ZR_TEST_A")
      vs = []
      ENV.each_value { |v| vs << v }
      p vs.include?("2")

      # Every iterator answers ENV itself, and IDENTITY survives -- a Hash snapshot
      # standing in for ENV would fail both.
      p ENV.equal?(ENV)
      p (ENV.each_key { |k| }).equal?(ENV)
      p (ENV.each { |k, v| }).equal?(ENV)
      p ENV.object_id == ENV.object_id
      p ENV.class, ENV.to_s, ENV.frozen?, ENV.nil?

      # The Enumerable half, served by a snapshot.
      p ENV.count > 0
      p ENV.map { |k, v| k }.class, ENV.min.class, ENV.sort.class
      p ENV.find { |k, v| k == "ZR_TEST_A" }
      p ENV.each_with_index.to_a.first.class
      p ENV.tally.class, ENV.grep(/x/).class, ENV.lazy.class
      p ENV.include?("ZR_TEST_A"), ENV.any? { |k, v| k == "ZR_TEST_A" }, ENV.length
    RUBY

    _(result).must_answer <<~'OUT'
      {"ZR_TEST_A" => "1", "ZR_TEST_B" => "2"}
      {"ZR_TEST_A" => "1", "ZR_TEST_B" => "2"}
      {"ZR_TEST_A" => "1", "ZR_TEST_B" => "2"}
      {}
      Enumerator
      Enumerator
      Enumerator
      Array
      true
      "ZR_TEST_A"
      ["ZR_TEST_A", "1"]
      true
      true
      false
      {"ZR_TEST_A" => "1"}
      nil
      true
      true
      true
      true
      true
      true
      Object
      "ENV"
      false
      false
      true
      Array
      Array
      Array
      ["ZR_TEST_A", "1"]
      Array
      Hash
      Array
      Enumerator::Lazy
      true
      true
      3
    OUT
  end

  it "env mutation surface" do
    result = zr(<<~'RUBY')
      # ENV: predicate arity, the wider Enumerable
      # surface, and the mutators (update/merge!/clear/shift/delete_if family).
      ENV['ZZ_A'] = '1'
      r1 = (ENV.has_key? rescue $!.class);             p r1
      r2 = (ENV.key?('ZZ_A', 'ZZ_B') rescue $!.class); p r2
      r3 = (ENV.include?('a', 'b') rescue $!.class);   p r3
      r4 = (ENV.member?('a', 'b') rescue $!.class);    p r4
      p ENV.key?('ZZ_A')
      ENV['ZZ_A'] = '1'
      ENV['ZZ_B'] = '2'
      p ENV.value?('1')
      p ENV.to_hash.class
      p ENV.first.class
      p ENV.update('ZZ_A' => '9')['ZZ_A']
      p ENV['ZZ_A']
      p ENV.merge!('ZZ_C' => '3')['ZZ_C']
      p ENV.frozen?
      p ENV.has_value?('3')
      ENV.delete_if { |k, v| k.start_with?('ZZ_') }
      p ENV['ZZ_A']
      p ENV.key?('ZZ_C')
      ENV['ZK_1'] = 'a'
      ENV['ZK_2'] = 'b'
      ENV.keep_if { |k, v| !k.start_with?('ZK_') }
      p ENV.key?('ZK_1')
      p ENV.tally.class
      p ENV.take(1).class
      p ENV.min.class
      sl_n = 0
      ENV.each_slice(2) { |sl| sl_n += sl.length }
      p sl_n >= 2
      p ENV.grep(/^nope$/)
      sh = ENV.shift
      p sh.class
      p ENV.entries.class
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      true
      true
      Hash
      Array
      "9"
      "9"
      "3"
      false
      true
      nil
      false
      false
      Hash
      Array
      Array
      true
      []
      Array
      Array
    OUT
  end

  it "errno full surface", only: "macos" do
    result = zr(<<~'RUBY')

      # `Errno` is generated from one table (`Errno::CODES`), so every name
      # the platform errno list carries exists -- not just the dozen the runtime
      # happened to raise. A name the platform does not define is bound to
      # `Errno::NOERROR`, and a second spelling of one value is bound to the class
      # that owns it, both exactly as CRuby does.

      puts "-- every name is present, and they are the platform's own"
      p Errno.constants.size
      p Errno.constants.include?(:ERANGE)
      p Errno.constants.include?(:EWOULDBLOCK)
      p Errno::ERANGE.name

      puts "-- each class names the errno it stands for"
      p Errno::ENOENT::Errno
      p Errno::EACCES::Errno
      p Errno::EINVAL::Errno
      p Errno::ENOENT.new.errno

      puts "-- a second spelling IS the class it duplicates"
      p Errno::EWOULDBLOCK.equal?(Errno::EAGAIN)
      p Errno::EWOULDBLOCK.name
      begin
        raise Errno::EAGAIN
      rescue Errno::EWOULDBLOCK => e
        p ["EWOULDBLOCK caught an EAGAIN", e.class]
      end

      puts "-- a name this platform lacks is NOERROR, as in CRuby"
      p Errno::EADV.name
      p Errno::NOERROR::Errno

      puts "-- the whole hierarchy"
      p Errno::ENOENT.superclass
      p Errno::ENOENT.ancestors.first(4)

      puts "-- the message is composed from strerror, not stored"
      p Errno::ENOENT.new.message
      p Errno::ENOENT.new(nil).message
      p Errno::ENOENT.new("f").message

      puts "-- SystemCallError.new picks the class its errno names"
      p SystemCallError.new("x", 2).class
      p SystemCallError.new("x", 2).message
      p SystemCallError.new("x", 2).errno
      p SystemCallError.new(2).class
      p SystemCallError.new(2).message

      puts "-- and stays itself when the errno names none"
      p SystemCallError.new("x").class
      p SystemCallError.new("x").message
      p SystemCallError.new("x").errno
      p SystemCallError.new("x", 9999).class
      p SystemCallError.new("x", 9999).message
      p SystemCallError.new("x", 9999).errno

      puts "-- a real syscall failure keeps CRuby's own message shape"
      begin
        File.open("/nope/nope")
      rescue SystemCallError => e
        p [e.class, e.message, e.errno]
      end
      begin
        Dir.mkdir("/nope/nope")
      rescue SystemCallError => e
        p [e.class, e.errno]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      -- every name is present, and they are the platform's own
      158
      true
      true
      "Errno::ERANGE"
      -- each class names the errno it stands for
      2
      13
      22
      2
      -- a second spelling IS the class it duplicates
      true
      "Errno::EAGAIN"
      ["EWOULDBLOCK caught an EAGAIN", Errno::EAGAIN]
      -- a name this platform lacks is NOERROR, as in CRuby
      "Errno::NOERROR"
      0
      -- the whole hierarchy
      SystemCallError
      [Errno::ENOENT, SystemCallError, StandardError, Exception]
      -- the message is composed from strerror, not stored
      "No such file or directory"
      "No such file or directory"
      "No such file or directory - f"
      -- SystemCallError.new picks the class its errno names
      Errno::ENOENT
      "No such file or directory - x"
      2
      Errno::ENOENT
      "No such file or directory"
      -- and stays itself when the errno names none
      SystemCallError
      "unknown error - x"
      nil
      SystemCallError
      "Unknown error: 9999 - x"
      9999
      -- a real syscall failure keeps CRuby's own message shape
      [Errno::ENOENT, "No such file or directory @ rb_sysopen - /nope/nope", 2]
      [Errno::ENOENT, 2]
    OUT
  end

  it "exception private rows" do
    result = zr(<<~'RUBY')
      # `Exception` declares three private rows of its own, not one. zr had only
      # `#initialize`, so `method_missing` and `respond_to_missing?` reported
      # `BasicObject` and `Kernel` as their owners and went missing from
      # `Exception.private_instance_methods(false)`.
      #
      # Nothing OBSERVABLE changes about what they do -- the answer is the root pair's
      # either way, which is why the divergence survived: the census gates public
      # method sets only, so a private row is invisible to it.

      p Exception.private_instance_methods(false).sort
      p Exception.instance_method(:method_missing).owner
      p Exception.instance_method(:respond_to_missing?).owner
      p Exception.instance_method(:method_missing).arity
      p Exception.instance_method(:respond_to_missing?).arity
      p Exception.private_method_defined?(:method_missing)
      p Exception.method_defined?(:method_missing)

      # Only `Exception` OWNS them, while flat dispatch puts a row on every id -- so
      # every descendant must report them private without listing them as its own.
      p StandardError.private_instance_methods(false)
      p RuntimeError.private_instance_methods(false)
      p RuntimeError.private_method_defined?(:method_missing)
      p RuntimeError.new.respond_to?(:method_missing)
      p RuntimeError.new.respond_to?(:method_missing, true)
      p RuntimeError.new.respond_to?(:initialize)

      # The behavior is still the root pair's.
      class Boom < StandardError; end
      begin
        Boom.new("x").nope
      rescue NoMethodError => e
        p [e.class, e.message, e.name]
      end
      p Boom.new("x").respond_to?(:nope)
      p Boom.new("x").send(:respond_to_missing?, :nope, true)

      # A user override still wins, and its `super` still reaches the root.
      class Loud < StandardError
        def method_missing(name, *args)
          return :loud if name == :shout

          super
        end

        def respond_to_missing?(name, include_private = false) = name == :shout || super
      end
      l = Loud.new("x")
      p l.shout
      p l.respond_to?(:shout)
      p l.respond_to?(:quiet)
      begin
        l.quiet
      rescue NoMethodError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:initialize, :method_missing, :respond_to_missing?]
      Exception
      Exception
      -1
      2
      true
      false
      []
      []
      true
      false
      true
      false
      [NoMethodError, "undefined method 'nope' for an instance of Boom", :nope]
      false
      false
      :loud
      true
      false
      "undefined method 'quiet' for an instance of Loud"
    OUT
  end

  it "gc fiber binding rows" do
    result = zr(<<~'RUBY')
      # `GC`, `Fiber` and `Binding` rows for facts a refcounted heap with no fiber
      # scheduler can state truthfully. Values that describe MRI's own heap (slot
      # counts, build options) are asserted by shape; the rest match outright.

      puts "== GC =="
      # A collection may have run already, so the counters are asserted by TYPE.
      puts "count: #{GC.count.is_a?(Integer)}"
      puts "total_time: #{GC.total_time.is_a?(Integer)}"
      puts "stat: #{GC.stat.class}"
      puts "stat_heap: #{GC.stat_heap.class}"
      puts "config: #{GC.config.class}"
      puts "OPTS: #{GC::OPTS.class}"
      puts "INTERNAL_CONSTANTS: #{GC::INTERNAL_CONSTANTS.class}"
      # The VALUES describe MRI's last collection; the key set does not.
      puts "latest_gc_info keys: #{GC.latest_gc_info.keys.sort.inspect}"
      puts "latest_compact_info: #{GC.latest_compact_info.inspect}"
      puts "verify_compaction_references: #{GC.verify_compaction_references.class}"
      puts "verify_internal_consistency: #{GC.verify_internal_consistency.inspect}"
      puts "measure_total_time: #{GC.measure_total_time}"
      GC.measure_total_time = false
      puts "measure_total_time set: #{GC.measure_total_time}"
      GC.measure_total_time = true
      puts "auto_compact: #{GC.auto_compact}"
      puts "stress: #{GC.stress}"
      GC.stress = false
      puts "stress set: #{GC.stress}"

      puts "== Fiber =="
      puts "blocking?: #{Fiber.blocking?}"
      puts "current blocking?: #{Fiber.current.blocking?}"
      puts "scheduler: #{Fiber.scheduler.inspect}"
      puts "current_scheduler: #{Fiber.current_scheduler.inspect}"
      puts "set_scheduler nil: #{Fiber.set_scheduler(nil).inspect}"
      begin
        Fiber.schedule { 1 }
      rescue RuntimeError => e
        puts "schedule: #{e.message}"
      end
      puts "blocking block: #{Fiber.blocking { |fb| fb.class }}"

      f = Fiber.new { Fiber.yield(:paused); :done }
      puts "new fiber blocking?: #{f.blocking?}"
      puts "inside blocking?: #{Fiber.new { Fiber.blocking? }.resume}"
      puts "resume: #{f.resume}"
      puts "alive?: #{f.alive?}"
      puts "resume again: #{f.resume}"
      puts "dead backtrace: #{f.backtrace.inspect}"
      puts "dead locations: #{f.backtrace_locations.inspect}"
      puts "current backtrace is an Array: #{Fiber.current.backtrace.is_a?(Array)}"

      # `Fiber#raise` injects at the yield point.
      g = Fiber.new do
        begin
          Fiber.yield(:first)
        rescue ArgumentError => e
          :"caught #{e.message}"
        end
      end
      puts "raise setup: #{g.resume}"
      puts "raise: #{g.raise(ArgumentError, 'boom')}"

      puts "== Binding =="
      b = binding
      puts "implicit_parameters: #{b.implicit_parameters.inspect}"
      puts "implicit_parameter_defined?: #{b.implicit_parameter_defined?(:it)}"
      begin
        b.implicit_parameter_get(:it)
      rescue NameError => e
        puts "implicit_parameter_get: #{e.message.split(' for ').first}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      == GC ==
      count: true
      total_time: true
      stat: Hash
      stat_heap: Hash
      config: Hash
      OPTS: Array
      INTERNAL_CONSTANTS: Hash
      latest_gc_info keys: [:gc_by, :have_finalizer, :immediate_sweep, :major_by, :need_major_by, :retained_weak_references_count, :state, :weak_references_count]
      latest_compact_info: {considered: {}, moved: {}, moved_up: {}, moved_down: {}}
      verify_compaction_references: Hash
      verify_internal_consistency: nil
      measure_total_time: true
      measure_total_time set: false
      auto_compact: false
      stress: false
      stress set: false
      == Fiber ==
      blocking?: 1
      current blocking?: true
      scheduler: nil
      current_scheduler: nil
      set_scheduler nil: nil
      schedule: No scheduler is available!
      blocking block: Fiber
      new fiber blocking?: false
      inside blocking?: false
      resume: paused
      alive?: true
      resume again: done
      dead backtrace: []
      dead locations: []
      current backtrace is an Array: true
      raise setup: first
      raise: caught boom
      == Binding ==
      implicit_parameters: []
      implicit_parameter_defined?: false
      implicit_parameter_get: implicit parameter 'it' is not defined
    OUT
  end

  it "kernel autoload rows" do
    result = zr(<<~'RUBY')
      # `Kernel#autoload`/`#autoload?` -- the receiverless spellings, which ruby
      # files as private instance methods AND public singleton methods of `Kernel`.
      # zr answered `Kernel.autoload` off `Module`, so the call worked but every
      # reflection question named the wrong owner.

      p Kernel.singleton_methods(false).grep(/autoload/).sort
      p Kernel.private_instance_methods(false).grep(/autoload/).sort
      p Kernel.instance_methods(false).grep(/autoload/)
      p [Kernel.method(:autoload).arity, Kernel.method(:autoload?).arity]

      # The registration lands on `Object`, not on `Kernel` -- which is what makes a
      # top-level `autoload` visible to every class.
      p Kernel.autoload?(:Sprocket)
      Kernel.autoload(:Sprocket, "sprocket")
      p Kernel.autoload?(:Sprocket)
      p Object.autoload?(:Sprocket)
      p Module.new.autoload?(:Sprocket)

      # Private on every object, so a receiverless send reaches it and an explicit
      # one does not.
      p Object.new.respond_to?(:autoload, true)
      p Object.new.respond_to?(:autoload)
      p Object.new.send(:autoload?, :Sprocket)

      # A constant that already resolved reports nil, whatever was registered.
      Kernel.autoload(:Integer, "integer")
      p Kernel.autoload?(:Integer)
    RUBY

    _(result).must_answer <<~'OUT'
      [:autoload, :autoload?]
      [:autoload, :autoload?]
      []
      [2, -1]
      nil
      "sprocket"
      "sprocket"
      nil
      true
      false
      "sprocket"
      nil
    OUT
  end

  it "marshal private surfaces" do
    result = zr(<<~'RUBY')
      # The census-visible marshal privates: Marshal's module_function dump,
      # Complex/Rational marshal_dump hooks, Random's full state family.
      p Marshal.private_instance_methods(false)
      p Marshal.singleton_methods(false).sort

      p Complex(1, 2).send(:marshal_dump)
      p Rational(3, 4).send(:marshal_dump)
      p Complex(1.5, 0r).send(:marshal_dump)
      p Complex.private_instance_methods(false).include?(:marshal_dump)
      p Rational.private_instance_methods(false).include?(:marshal_dump)

      # Random: state exposes the raw MT position; a dump resumes the stream.
      r = Random.new(42)
      p r.send(:left)
      p r.send(:state) % (2**32)
      r.rand(100)
      p r.send(:left)
      d = r.send(:marshal_dump)
      p [d.class, d.size, d[1], d[2]]
      r2 = Random.new(0)
      r2.send(:marshal_load, d)
      p r2.rand(100) == r.rand(100)
      p r2.rand == r.rand
      p Marshal.load(Marshal.dump(Random.new(7))).rand(1000) == Random.new(7).rand(1000)
      begin
        Random.new(1).send(:marshal_load, [1, 0])
      rescue ArgumentError => e
        puts e.message
      end
      p [Random.send(:state).class, Random.send(:left).class]
      p Random.private_instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      [:dump]
      [:dump, :load, :restore]
      [1, 2]
      [3, 4]
      [1.5, (0/1)]
      true
      true
      1
      42
      623
      [Array, 3, 623, 42]
      true
      true
      true
      wrong value
      [Integer, Integer]
      [:initialize_copy, :left, :marshal_dump, :marshal_load, :state]
    OUT
  end

  it "method reflection surface" do
    result = zr(<<~'RUBY')
      # Method/UnboundMethod reflection: ==/eql?, original_name, parameters,
      def dbl(n) = n * 2
      class C
        def m(a, b = 1, *r, k: 2, **kw, &blk) = a
        alias_method :m2, :m
      end
      m1 = method(:dbl)
      m2 = method(:dbl)
      p m1 == m2
      p m1.eql?(m2)
      p m1.original_name
      p m1.parameters
      p m1.clone.arity
      u = C.instance_method(:m)
      p u.parameters
      p C.instance_method(:m2).original_name
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      :dbl
      [[:req, :n]]
      1
      [[:req, :a], [:opt, :b], [:rest, :r], [:key, :k], [:keyrest, :kw], [:block, :blk]]
      :m
    OUT
  end

  it "module aliases a kernel row" do
    result = zr(<<~'RUBY')
      # `alias` inside a bare MODULE finds a method of `Object`.
      #
      # A module's ancestry is itself alone, so a `Kernel` row is not in it -- and
      # CRuby's `rb_alias` retries the lookup on `Object` for exactly that case
      # (`vm_method.c`, the `RB_TYPE_P(klass, T_MODULE)` branch before
      # `rb_print_undef`). Zr checked only the ancestry and raised `NameError` at
      # program start.
      #
      # irb opens `IRB::IrbLoader` with two of them -- `alias ruby_load load` and
      # `alias ruby_require require` -- so `require "irb"` died before doing
      # anything.
      #
      # A CLASS gets no such retry: its ancestry already reaches `Object`, and a
      # name that is not there is a real NameError.

      module Loader
        alias ruby_load load
        alias ruby_require require
        alias say puts

        def announce = say("via the alias")
      end

      class Host
        include Loader
      end

      Host.new.announce
      p Loader.private_instance_methods(false).sort
      p Host.new.respond_to?(:ruby_load)
      p Host.new.respond_to?(:ruby_load, true)

      # The retry is for a MISSING name only: a module's own method still wins.
      module Own
        def real = "own"
        alias copy real
      end
      p Own.instance_method(:copy).owner
      p Class.new { include Own }.new.copy

      # A name nowhere at all is still NameError, module or not.
      begin
        Module.new { alias nope no_such_method_anywhere }
      rescue NameError => e
        puts e.message.sub(/for module '.*'/, "for module '<anon>'")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      via the alias
      [:ruby_load, :ruby_require, :say]
      false
      true
      Own
      "own"
      undefined method 'no_such_method_anywhere' for module '<anon>'
    OUT
  end

  it "module function surface" do
    result = zr(<<~'RUBY')
      # `module_function` gives a name TWO copies: a public singleton method on the
      # module, and a PRIVATE instance method that `include` carries into a class.
      # Kernel, Process, FileTest, ObjectSpace and Signal are all built this way in
      # CRuby, so `include Process` must make `pid` callable without a receiver.

      class Host
        include Process

        def report_pid
          pid
        end

        def report_ppid
          ppid
        end
      end

      puts "-- the instance half arrives through include"
      p Host.new.report_pid == Process.pid
      p Host.new.report_ppid == Process.ppid

      puts "-- and it is private: reflection says so, and public_send refuses"
      p Host.private_method_defined?(:pid)
      p Host.new.respond_to?(:pid)
      begin
        Host.new.public_send(:pid)
      rescue NoMethodError => e
        puts e.message
      end
      # The plain `Host.new.pid` call is NOT asserted here: codegen folds an
      # explicit-receiver builtin call without consulting visibility, so it answers
      # instead of raising. See `tests/gaps/module_function_private_receiver.rb`.

      puts "-- the singleton half stays public"
      p Process.respond_to?(:pid)
      p Process.pid.is_a?(Integer)

      puts "-- counts match CRuby's own"
      p Process.private_instance_methods(false).size
      p Process.singleton_methods(false).size
      p Signal.private_instance_methods(false).sort

      puts "-- the eight Process names CRuby keeps singleton-only stay singleton-only"
      %i[_fork abort exec exit exit! fork last_status spawn].each do |m|
        puts "#{m}: singleton=#{Process.singleton_methods(false).include?(m)} " \
             "private=#{Process.private_instance_methods(false).include?(m)}"
      end

      puts "-- FileTest mixes in the same 26 predicates File exposes as class methods"

      class Prober
        include FileTest

        def tmp_there?
          directory?("/tmp")
        end
      end

      p Prober.new.tmp_there?
      p FileTest.private_instance_methods(false).size
      p FileTest.singleton_methods(false).size
      p FileTest.exist?("/tmp")
      p FileTest.identical?("/tmp", "/tmp")

      puts "-- but FileTest is not the whole of File's class surface"
      begin
        FileTest.read("/etc/hosts")
      rescue NoMethodError => e
        puts e.message
      end
      p File.read("/etc/hosts").is_a?(String)

      puts "-- Kernel's converted rows answer as class methods too"
      p Kernel.respond_to?(:format)
      p Kernel.format("%05.2f", 1.5)
      p Kernel.singleton_methods(false).include?(:sprintf)
    RUBY

    _(result).must_answer <<~'OUT'
      -- the instance half arrives through include
      true
      true
      -- and it is private: reflection says so, and public_send refuses
      true
      false
      private method 'pid' called for an instance of Host
      -- the singleton half stays public
      true
      true
      -- counts match CRuby's own
      39
      47
      [:list, :signame, :trap]
      -- the eight Process names CRuby keeps singleton-only stay singleton-only
      _fork: singleton=true private=false
      abort: singleton=true private=false
      exec: singleton=true private=false
      exit: singleton=true private=false
      exit!: singleton=true private=false
      fork: singleton=true private=false
      last_status: singleton=true private=false
      spawn: singleton=true private=false
      -- FileTest mixes in the same 26 predicates File exposes as class methods
      true
      26
      26
      true
      true
      -- but FileTest is not the whole of File's class surface
      undefined method 'read' for module FileTest
      true
      -- Kernel's converted rows answer as class methods too
      true
      "01.50"
      true
    OUT
  end

  it "nested container array surface" do
    result = zr(<<~'RUBY')
      # An Array read out of an Array(Array) or a Hash value has an unknown static
      # type, but it answers all of Array's surface: a Range index, #min / #max on a
      # String array, and the count-taking reads (first(n), last(n), take, drop,
      # rotate, values_at, sample(n)).
      rows = [["a", "b", "c"]]
      r = rows[0]
      p r.class
      p r[0..1]
      p r.slice(0..1)
      p r.min
      p r.max
      p r.first(2)
      p r.last(2)
      p r.take(2)
      p r.drop(1)
      p r.rotate
      p r.values_at(0, 2)
      p r[1..2]
      p r[0..-1]
      p r[0...2]
      p r[1..]
      h = { "row" => ["x", "y", "z"] }
      p h["row"][0..1]
      p h["row"].min
      p h["row"].max
      floats = [[1.5, 2.5]]
      p floats[0][0..1]
      p floats[0].min
      syms = [[:a, :b]]
      p syms[0][0..1]
      ints = [[3, 1, 2]]
      p ints[0][0..1]
      p ints[0].min
      p ints[0].max
      p ints[0].first(2)
      p ints[0].last(2)
      p ints[0].take(2)
      p ints[0].drop(1)
      p ints[0].rotate
      p ints[0].rotate(2)
      p ints[0].values_at(0, 2)
      p ints[0].sample(3).sort
      nested = [["a", "b", "c"]]
      g = nested[0]
      p g[1..2]
      p g[0..-1]
      p g[0...2]
      p g[1..]
      p g[..1]
      p g[5..6]
      p g[3..4]
      p g.first(10)
      p g.drop(10)
      p g.last(10)
      p g.values_at(0, -1, 9)
      p g.slice(1..2)
      a = ["a", "b", "c"]
      p a[0..1]
      p a.first(2)
      p a.min
    RUBY

    _(result).must_answer <<~'OUT'
      Array
      ["a", "b"]
      ["a", "b"]
      "a"
      "c"
      ["a", "b"]
      ["b", "c"]
      ["a", "b"]
      ["b", "c"]
      ["b", "c", "a"]
      ["a", "c"]
      ["b", "c"]
      ["a", "b", "c"]
      ["a", "b"]
      ["b", "c"]
      ["x", "y"]
      "x"
      "z"
      [1.5, 2.5]
      1.5
      [:a, :b]
      [3, 1]
      1
      3
      [3, 1]
      [1, 2]
      [3, 1]
      [1, 2]
      [1, 2, 3]
      [2, 3, 1]
      [3, 2]
      [1, 2, 3]
      ["b", "c"]
      ["a", "b", "c"]
      ["a", "b"]
      ["b", "c"]
      ["a", "b"]
      nil
      []
      ["a", "b", "c"]
      []
      ["a", "b", "c"]
      ["a", "c", nil]
      ["b", "c"]
      ["a", "b"]
      ["a", "b"]
      "a"
    OUT
  end

  it "object defaults parity" do
    result = zr(<<~'RUBY')
      # Object defaults on user classes: is_a?/kind_of? against universal
      # ancestors, default to_s / inspect rendering, and clone(freeze:).

      class Plain; end
      class Sub < Plain; end

      a = Plain.new
      p a.is_a?(Object)
      p a.kind_of?(Object)
      p a.is_a?(BasicObject)
      p a.is_a?(Kernel)
      p a.instance_of?(Object)
      p a.is_a?(Sub)
      s = Sub.new
      p s.is_a?(Plain)
      p s.is_a?(Object)

      # default to_s / inspect: value-shaped class (immutable scalar ivar)
      class Widget
        def initialize = @id = 7
      end
      w = Widget.new
      ws = w.to_s
      wi = w.inspect
      p ws.start_with?("#<Widget:0x")
      p ws.end_with?(">")
      p wi.start_with?("#<Widget:0x")
      p wi.include?("@id=7")

      # default to_s / inspect: heap class (mutable ivars)
      class Counter
        def initialize = @n = 0
        def bump = @n += 1
      end
      cobj = Counter.new
      cobj.bump
      cs = cobj.to_s
      cinsp = cobj.inspect
      p cs.start_with?("#<Counter:0x")
      p cinsp.include?("@n=1")

      # clone with the freeze keyword
      str = "hi"
      p str.clone(freeze: false)
      p str.clone(freeze: false).frozen?
      p str.clone(freeze: true).frozen?
      p str.clone
      arr = [1, 2]
      p arr.clone(freeze: true).frozen?
      p arr.clone(freeze: false).frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      false
      false
      true
      true
      true
      true
      true
      true
      true
      true
      "hi"
      false
      true
      "hi"
      true
      false
    OUT
  end

  it "owner rows class new on builtins" do
    result = zr(<<~'RUBY')
      p Hash.singleton_methods(false).include?(:new)
      p Range.singleton_methods(false).include?(:new)
      p Regexp.singleton_methods(false).include?(:new)
      p Mutex.singleton_methods(false).include?(:new)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
    OUT
  end

  it "owner rows enumerable on array" do
    result = zr(<<~'RUBY')
      p Array.instance_methods(false).include?(:chain)
      p Array.instance_methods(false).include?(:member?)
      p Array.instance_method(:chain).owner
      p Array.instance_method(:member?).owner
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      Enumerable
      Enumerable
    OUT
  end

  it "owner rows numeric on integer" do
    result = zr(<<~'RUBY')
      p Integer.instance_methods(false).include?(:+@)
      p Integer.instance_methods(false).include?(:i)
      p Integer.instance_methods(false).include?(:finite?)
      p Integer.instance_method(:+@).owner
      p Float.instance_methods(false).include?(:div)
      p Float.instance_method(:div).owner
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      Numeric
      false
      Numeric
    OUT
  end

  it "owner rows object methods on builtins" do
    result = zr(<<~'RUBY')
      p Thread.instance_methods(false).include?(:==)
      p Fiber.instance_methods(false).include?(:equal?)
      p Encoding.instance_methods(false).include?(:hash)
      p Module.instance_methods(false).include?(:instance_variable_get)
      p Module.instance_method(:instance_variable_get).owner
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
      Kernel
    OUT
  end

  it "poly hash surface" do
    result = zr(<<~'RUBY')
      # The Hash/Enumerable surface on a value that arrives boxed: a seedless
      # Array#reduce result, a Fiber#resume value, a container read. The receiver's
      # runtime class is unknown at the call site, so each line pins either an arm
      # that pretends the receiver is the general boxed hash, or one that branches on
      # the runtime kind. The array cases below guard the second kind: a name Array
      # also owns must keep answering Array's way.
      def fv(x)
        f = Fiber.new { Fiber.yield(x); nil }
        f.resume
      end

      h = fv({ n: 1, s: 2 })

      p h.dig(:n)
      p h.value?(1)
      p h.invert
      p h.assoc(:n)
      p h.rassoc(1)
      p h.filter_map { |k, v| k }
      p h.each_with_object([]) { |(k, v), a| a << k }
      p h.each_with_object({}) { |(k, v), a| a[v] = k }
      p h.group_by { |k, v| v }
      p h.partition { |k, v| v == 1 }
      p h.zip([9, 8])
      p h.reduce(0) { |a, (k, v)| a + v }
      p h.find { |k, v| k == :n }
      p h.take(1)
      p h.drop(1)
      p h.select { |k, v| k == :n }
      p h.reject { |k, v| k == :n }
      p h.slice(:n)
      p h.slice(:n, :s)
      p h.except(:n)
      p h.values_at(:n, :s)
      p h.fetch_values(:n)
      p h.entries
      p h.flatten
      p h.first
      p h.each_pair.to_a
      p h.each_key.to_a
      p h.each_value.to_a
      p h.each_entry.to_a
      p h.transform_values { |v| v * 2 }
      p h.transform_keys { |k| k.to_s }
      p h.tally.size
      p h.chunk_while { |a, b| true }.to_a
      p h.flat_map { |k, v| [k] }
      p h.none? { |k, v| v > 5 }
      p h.any? { |k, v| v > 1 }
      p h.all? { |k, v| v > 0 }
      p h.one? { |k, v| v == 1 }
      p h.count { |k, v| v > 1 }
      p h.to_h
      p fv({ n: 1, s: nil }).compact

      # the seedless Array#reduce shapes the reports were filed against
      p [{ n: 1 }].reduce { |acc, l| acc }.first
      p [{ n: 1 }, { m: 2 }].reduce { |acc, l| acc.merge(l) }.to_h

      # a boxed Array answers the shared names on its own terms
      a = fv([1, 2, 3])
      p a.select { |x| x > 1 }
      p a.reject { |x| x > 1 }
      p a.first
      p a.last
      p a.slice(1, 2)
      p a.slice(0)
      p a.compact
      p a.flatten
      p a.find { |x| x > 1 }
      p a.flat_map { |x| [x, x] }
      p a.count { |x| x > 1 }
      p a.none? { |x| x > 5 }
      p a.chunk_while { |x, y| y == x + 1 }.to_a

      # and a boxed String keeps the names it shares with them
      s = fv("abcdef")
      p s.slice(1, 2)
      p s.slice(1)
      p s.count("a")
      p s.index("c")
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      {1 => :n, 2 => :s}
      [:n, 1]
      [:n, 1]
      [:n, :s]
      [:n, :s]
      {1 => :n, 2 => :s}
      {1 => [[:n, 1]], 2 => [[:s, 2]]}
      [[[:n, 1]], [[:s, 2]]]
      [[[:n, 1], 9], [[:s, 2], 8]]
      3
      [:n, 1]
      [[:n, 1]]
      [[:s, 2]]
      {n: 1}
      {s: 2}
      {n: 1}
      {n: 1, s: 2}
      {s: 2}
      [1, 2]
      [1]
      [[:n, 1], [:s, 2]]
      [:n, 1, :s, 2]
      [:n, 1]
      [[:n, 1], [:s, 2]]
      [:n, :s]
      [1, 2]
      [[:n, 1], [:s, 2]]
      {n: 2, s: 4}
      {"n" => 1, "s" => 2}
      2
      [[[:n, 1], [:s, 2]]]
      [:n, :s]
      true
      true
      true
      true
      1
      {n: 1, s: 2}
      {n: 1}
      [:n, 1]
      {n: 1, m: 2}
      [2, 3]
      [1]
      1
      3
      [2, 3]
      1
      [1, 2, 3]
      [1, 2, 3]
      2
      [1, 1, 2, 2, 3, 3]
      2
      true
      [[1, 2, 3]]
      "bc"
      "b"
      1
      2
    OUT
  end

  it "poly string surface" do
    result = zr(<<~'RUBY')
      # The String surface on a value that arrives boxed: a Fiber#resume result, a
      # Queue#pop, a Thread#value. Every one of these answers on a plain String
      # local, so each line that disagrees is a missing or wrong arm on the boxed
      # path rather than a String bug.
      def fv(s)
        f = Fiber.new { Fiber.yield(s); nil }
        f.resume
      end

      v = fv("aabbcc")

      # --- methods that must answer ---
      r = (v.squeeze rescue $!.class); p r
      r = (v.index("b") rescue $!.class); p r
      r = (v.rindex("b") rescue $!.class); p r
      r = (v.byteindex("b") rescue $!.class); p r
      r = (v.partition("b") rescue $!.class); p r
      r = (v.rpartition("b") rescue $!.class); p r
      r = (v.slice(1, 2) rescue $!.class); p r
      r = (v.hex rescue $!.class); p r
      r = (v.oct rescue $!.class); p r
      r = (v.tr_s("ab", "x") rescue $!.class); p r
      r = (v.casecmp("AABBCC") rescue $!.class); p r
      r = (v.casecmp?("AABBCC") rescue $!.class); p r
      r = (fv("abc").crypt("ab") rescue $!.class); p r

      # the value-form mutators, which answer the new contents and update an lvalue
      m = fv(String.new("aabbcc"))
      r = (m.insert(1, "X") rescue $!.class); p r
      p m
      m2 = fv(String.new("aabbcc"))
      r = (m2.squeeze! rescue $!.class); p r
      p m2
      m3 = fv(String.new("abc"))
      r = (m3.squeeze! rescue $!.class); p r   # no change -> nil
      p m3
      m4 = fv(String.new(" pad "))
      r = (m4.strip! rescue $!.class); p r
      r = (m4.upcase! rescue $!.class); p r
      p m4

      # --- methods that must give the right count and sum ---
      r = (v.count("a") rescue $!.class); p r
      r = (v.sum rescue $!.class); p r
      r = (v.sum(8) rescue $!.class); p r

      # --- String#% with an array and with one value ---
      f2 = fv("v=%d")
      r = (f2 % [5] rescue $!.class); p r
      r = (f2 % 5 rescue $!.class); p r

      # --- the common methods ---
      p v
      p v[1]
      p v[1, 2]
      p v.length
      p v.ord
      p v.delete("a")
      p v.upcase
      p v.split("b")
      p v.sub("aa", "x")
      p v.gsub("b", "y")
      p v.tr("a", "z")
      p v.squeeze("abc")
      p v.delete_prefix("aa")
      p v.delete_suffix("cc")
      p v.chars
      p v.bytes
      p v.start_with?("aa")
      p v.include?("bb")
      p v.reverse
      p v.center(10, "-")
      p v.to_sym
      p v.each_char.to_a
      p v.each_byte.sum

      # the same value out of a Queue and a Thread
      q = Queue.new
      q.push("aabbcc")
      qv = q.pop
      r = (qv.index("b") rescue $!.class); p r
      r = (qv.count("a") rescue $!.class); p r

      t = Thread.new { "aabbcc" }
      tv = t.value
      r = (tv.partition("b") rescue $!.class); p r
      r = (tv.sum rescue $!.class); p r

      # A boxed Array answers the names it shares with String on its own terms: the
      # String arms must never claim a receiver whose runtime class is unknown.
      a = fv([1, 2, 2, 3])
      p a.count(2)
      p a.index(2)
      p a.rindex(2)
      p a.sum
      p a.slice(1, 2)
      p a.insert(1, 9)
      p a
      p fv({ "a" => 1, "b" => 2 }).count
    RUBY

    _(result).must_answer <<~'OUT'
      "abc"
      2
      3
      2
      ["aa", "b", "bcc"]
      ["aab", "b", "cc"]
      "ab"
      11189196
      0
      "xcc"
      0
      true
      "abFZSxKKdq5s6"
      "aXabbcc"
      "aXabbcc"
      "abc"
      "abc"
      nil
      "abc"
      "pad"
      "PAD"
      "PAD"
      2
      588
      76
      "v=5"
      "v=5"
      "aabbcc"
      "a"
      "ab"
      6
      97
      "bbcc"
      "AABBCC"
      ["aa", "", "cc"]
      "xbbcc"
      "aayycc"
      "zzbbcc"
      "abc"
      "bbcc"
      "aabb"
      ["a", "a", "b", "b", "c", "c"]
      [97, 97, 98, 98, 99, 99]
      true
      true
      "ccbbaa"
      "--aabbcc--"
      :aabbcc
      ["a", "a", "b", "b", "c", "c"]
      588
      2
      2
      ["aa", "b", "bcc"]
      588
      2
      1
      2
      8
      [2, 2]
      [1, 9, 2, 2, 3]
      [1, 9, 2, 2, 3]
      2
    OUT
  end

  it "poly time surface" do
    result = zr(<<~'RUBY')
      # A Time that arrives boxed -- read out of a container, or narrowed out of an
      # untyped value by is_a?(Time) -- answers the full Time surface, not only the
      # scalar accessors. That includes each method that answers a Time, a boolean,
      # an offset, or a formatted string.
      #
      # The array holds mixed types, so every receiver below is boxed. The instant
      # is put in UTC first: zone, iso8601 and the local reads would otherwise answer
      # whatever zone the machine running the suite happens to be in.
      box = [Time.at(1700000000, 123456).utc, "not a time"]
      t = box[0]

      # The ones that answer a Time, which is what the report named. The result stays
      # boxed, so a chained read dispatches through this same surface. These are the
      # non-mutating spellings; the converting ones come last, since in Ruby they
      # change the receiver.
      puts t.getutc.year
      puts t.getgm.year
      puts t.getlocal(0).hour
      puts t.getlocal("+00:00").hour

      # The offsets and the subsecond reads.
      puts t.nsec
      puts t.tv_nsec
      puts t.usec
      puts t.tv_usec
      puts t.utc_offset
      puts t.gmt_offset
      puts t.gmtoff
      puts t.subsec

      # The predicates.
      puts t.utc?
      puts t.gmt?
      puts t.dst?
      puts t.isdst
      puts t.sunday?
      puts t.monday?
      puts t.tuesday?
      puts t.wednesday?
      puts t.thursday?
      puts t.friday?
      puts t.saturday?

      # The formatters.
      puts t.zone
      puts t.iso8601
      puts t.xmlschema

      # localtime / getlocal answer the machine's zone, so only the year is stable
      # enough to assert -- this instant is mid-November in every zone on earth.
      puts t.getlocal.year

      # The scalar half that already worked, so a change here would be visible.
      puts t.year
      puts t.hour
      puts t.to_i

      # A receiver that is not a Time still raises, and the message names the method.
      begin
        box[1].utc
      rescue NoMethodError => e
        puts "raised: #{e.message.include?("utc")}"
      end

      # utc / gmtime / localtime convert the receiver in place and answer it, so they
      # come last: the reads above would see the new zone. The other reference to the
      # same Time sees the conversion too, as it does in Ruby.
      also = t
      puts t.localtime.year
      puts t.utc.year
      puts t.utc?
      puts also.utc?
      puts t.gmtime.hour
    RUBY

    _(result).must_answer <<~'OUT'
      2023
      2023
      22
      22
      123456000
      123456000
      123456
      123456
      0
      0
      0
      1929/15625
      true
      true
      false
      false
      false
      false
      true
      false
      false
      false
      false
      UTC
      2023-11-14T22:13:20Z
      2023-11-14T22:13:20Z
      2023
      2023
      22
      1700000000
      raised: true
      2023
      2023
      true
      true
      22
    OUT
  end

  it "process identity and scheduling surface" do
    result = zr(<<~'RUBY')
      # Process ids/scheduling against libc, plus the PRIO_* selector constants.

      p [Process.uid.class, Process.gid.class, Process.euid.class, Process.egid.class]
      p [Process.getpgrp.class, Process.getsid.class]
      p Process.clock_getres(Process::CLOCK_MONOTONIC).class
      p Process.clock_getres(Process::CLOCK_REALTIME, :nanosecond).class
      p [Process::PRIO_PROCESS, Process::PRIO_PGRP, Process::PRIO_USER]
      p Process.groups.all? { |g| g.is_a?(Integer) }
      p Process.getpriority(Process::PRIO_PROCESS, 0).class
    RUBY

    _(result).must_answer <<~'OUT'
      [Integer, Integer, Integer, Integer]
      [Integer, Integer]
      Float
      Integer
      [0, 1, 2]
      true
      Integer
    OUT
  end

  it "Process::Sys, UID and GID are modules, each naming its own singleton rows" do
    result = zr(<<~'RUBY')

      # `Process::Sys`, `Process::UID` and `Process::GID` -- the identity surface.
      #
      # Every id printed here is compared against one the process already knows,
      # never printed raw, so the output is the same on any machine. Nothing in
      # this file can change an id: an unprivileged process may only re-assert the
      # ids it already holds, and every other request is refused.

      uid = Process.uid
      euid = Process.euid
      gid = Process.gid
      egid = Process.egid

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # The shape: all three are modules, and every name but the two `eid=`
      # writers is a `module_function` -- a singleton method AND a private
      # instance method, so `include Process::Sys` carries them too.
      [Process::Sys, Process::UID, Process::GID].each do |m|
        puts "#{m} class: #{m.class}"
        puts "#{m} singleton: #{m.singleton_methods(false).sort.inspect}"
        puts "#{m} private: #{m.private_instance_methods(false).sort.inspect}"
        puts "#{m} public instance: #{m.instance_methods(false).inspect}"
      end
      puts "Sys respond_to?: #{Process::Sys.respond_to?(:setuid)}"
      puts "Sys included: #{Class.new { include Process::Sys }.new.send(:getuid) == uid}"

    RUBY

    _(result).must_answer <<~'OUT'
      Process::Sys class: Module
      Process::Sys singleton: [:getegid, :geteuid, :getgid, :getuid, :issetugid, :setegid, :seteuid, :setgid, :setregid, :setresgid, :setresuid, :setreuid, :setrgid, :setruid, :setuid]
      Process::Sys private: [:getegid, :geteuid, :getgid, :getuid, :issetugid, :setegid, :seteuid, :setgid, :setregid, :setresgid, :setresuid, :setreuid, :setrgid, :setruid, :setuid]
      Process::Sys public instance: []
      Process::UID class: Module
      Process::UID singleton: [:change_privilege, :eid, :eid=, :from_name, :grant_privilege, :re_exchange, :re_exchangeable?, :rid, :sid_available?, :switch]
      Process::UID private: [:change_privilege, :eid, :from_name, :grant_privilege, :re_exchange, :re_exchangeable?, :rid, :sid_available?, :switch]
      Process::UID public instance: []
      Process::GID class: Module
      Process::GID singleton: [:change_privilege, :eid, :eid=, :from_name, :grant_privilege, :re_exchange, :re_exchangeable?, :rid, :sid_available?, :switch]
      Process::GID private: [:change_privilege, :eid, :from_name, :grant_privilege, :re_exchange, :re_exchangeable?, :rid, :sid_available?, :switch]
      Process::GID public instance: []
      Sys respond_to?: true
      Sys included: true
    OUT
  end

  it "the Sys readers answer what Process already answers" do
    result = zr(<<~'RUBY')

      # `Process::Sys`, `Process::UID` and `Process::GID` -- the identity surface.
      #
      # Every id printed here is compared against one the process already knows,
      # never printed raw, so the output is the same on any machine. Nothing in
      # this file can change an id: an unprivileged process may only re-assert the
      # ids it already holds, and every other request is refused.

      uid = Process.uid
      euid = Process.euid
      gid = Process.gid
      egid = Process.egid

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # The readers, each against the answer `Process` already gives.
      show("Sys.getuid") { Process::Sys.getuid == uid }
      show("Sys.geteuid") { Process::Sys.geteuid == euid }
      show("Sys.getgid") { Process::Sys.getgid == gid }
      show("Sys.getegid") { Process::Sys.getegid == egid }
      show("Sys.issetugid") { Process::Sys.issetugid }
      show("UID.rid") { Process::UID.rid == uid }
      show("UID.eid") { Process::UID.eid == euid }
      show("GID.rid") { Process::GID.rid == gid }
      show("GID.eid") { Process::GID.eid == egid }
      show("UID.sid_available?") { Process::UID.sid_available? }
      show("GID.sid_available?") { Process::GID.sid_available? }

    RUBY

    _(result).must_answer <<~'OUT'
      Sys.getuid: true
      Sys.geteuid: true
      Sys.getgid: true
      Sys.getegid: true
      Sys.issetugid: false
      UID.rid: true
      UID.eid: true
      GID.rid: true
      GID.eid: true
      UID.sid_available?: true
      GID.sid_available?: true
    OUT
  end

  it "from_name resolves a passwd or group name, and passes an Integer straight through" do
    result = zr(<<~'RUBY')

      # `Process::Sys`, `Process::UID` and `Process::GID` -- the identity surface.
      #
      # Every id printed here is compared against one the process already knows,
      # never printed raw, so the output is the same on any machine. Nothing in
      # this file can change an id: an unprivileged process may only re-assert the
      # ids it already holds, and every other request is refused.

      uid = Process.uid
      euid = Process.euid
      gid = Process.gid
      egid = Process.egid

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # `from_name` resolves a passwd or group name; an Integer passes straight
      # through, and anything that is neither takes the Integer conversion's own
      # refusal.
      show("UID.from_name root") { Process::UID.from_name("root") }
      show("UID.from_name self") { Process::UID.from_name(uid) == uid }
      show("GID.from_name self") { Process::GID.from_name(gid) == gid }
      show("UID.from_name float") { Process::UID.from_name(1.9) }
      show("UID.from_name negative") { Process::UID.from_name(-1) }
      show("UID.from_name to_int") do
        o = Object.new
        def o.to_int = 7
        Process::UID.from_name(o)
      end
      show("UID.from_name bignum") { Process::UID.from_name(2**70) }
      show("UID.from_name nil") { Process::UID.from_name(nil) }
      show("UID.from_name symbol") { Process::UID.from_name(:root) }
      show("UID.from_name missing") { Process::UID.from_name("nosuchuser__") }
      show("GID.from_name missing") { Process::GID.from_name("nosuchgroup__") }

    RUBY

    _(result).must_answer <<~'OUT'
      UID.from_name root: 0
      UID.from_name self: true
      GID.from_name self: true
      UID.from_name float: 1
      UID.from_name negative: 4294967295
      UID.from_name to_int: 7
      UID.from_name bignum: RangeError: bignum too big to convert into 'unsigned long'
      UID.from_name nil: TypeError: no implicit conversion of nil into Integer
      UID.from_name symbol: TypeError: no implicit conversion of Symbol into Integer
      UID.from_name missing: ArgumentError: can't find user for nosuchuser__
      GID.from_name missing: ArgumentError: can't find group for nosuchgroup__
    OUT
  end

  it "re-asserting an id the process already holds is the one change it may make" do
    result = zr(<<~'RUBY')

      # `Process::Sys`, `Process::UID` and `Process::GID` -- the identity surface.
      #
      # Every id printed here is compared against one the process already knows,
      # never printed raw, so the output is the same on any machine. Nothing in
      # this file can change an id: an unprivileged process may only re-assert the
      # ids it already holds, and every other request is refused.

      uid = Process.uid
      euid = Process.euid
      gid = Process.gid
      egid = Process.egid

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # Re-asserting the ids the process already holds is the one change it is
      # allowed to make, and it answers what CRuby answers: nil from `Sys`, the
      # argument as written from `UID`/`GID`.
      show("Sys.setuid self") { Process::Sys.setuid(uid) }
      show("Sys.setgid self") { Process::Sys.setgid(gid) }
      show("Sys.seteuid self") { Process::Sys.seteuid(euid) }
      show("Sys.setegid self") { Process::Sys.setegid(egid) }
      show("Sys.setruid self") { Process::Sys.setruid(uid) }
      show("Sys.setrgid self") { Process::Sys.setrgid(gid) }
      show("Sys.setreuid self") { Process::Sys.setreuid(uid, euid) }
      show("Sys.setregid self") { Process::Sys.setregid(gid, egid) }
      show("UID.change_privilege self") { Process::UID.change_privilege(uid) == uid }
      show("GID.change_privilege self") { Process::GID.change_privilege(gid) == gid }
      show("UID.grant_privilege self") { Process::UID.grant_privilege(uid) == uid }
      show("GID.grant_privilege self") { Process::GID.grant_privilege(gid) == gid }
      show("UID.eid= self") { (Process::UID.eid = uid) == uid }
      show("GID.eid= self") { (Process::GID.eid = gid) == gid }

    RUBY

    _(result).must_answer <<~'OUT'
      Sys.setuid self: nil
      Sys.setgid self: nil
      Sys.seteuid self: nil
      Sys.setegid self: nil
      Sys.setruid self: nil
      Sys.setrgid self: nil
      Sys.setreuid self: nil
      Sys.setregid self: nil
      UID.change_privilege self: true
      GID.change_privilege self: true
      UID.grant_privilege self: true
      GID.grant_privilege self: true
      UID.eid= self: true
      GID.eid= self: true
    OUT
  end

  it "a request for an id this process does not hold is refused with EPERM" do
    result = zr(<<~'RUBY')

      # `Process::Sys`, `Process::UID` and `Process::GID` -- the identity surface.
      #
      # Every id printed here is compared against one the process already knows,
      # never printed raw, so the output is the same on any machine. Nothing in
      # this file can change an id: an unprivileged process may only re-assert the
      # ids it already holds, and every other request is refused.

      uid = Process.uid
      euid = Process.euid
      gid = Process.gid
      egid = Process.egid

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # Every request for an id this process does not hold is refused, and by the
      # BARE errno message -- CRuby's `rb_sys_fail(0)` appends no context.
      show("Sys.setuid root") { Process::Sys.setuid(0) }
      show("Sys.setgid wheel") { Process::Sys.setgid(0) }
      show("Sys.seteuid root") { Process::Sys.seteuid(0) }
      show("Sys.setreuid root") { Process::Sys.setreuid(0, 0) }
      show("UID.change_privilege root") { Process::UID.change_privilege(0) }
      show("UID.grant_privilege root") { Process::UID.grant_privilege(0) }
      show("UID.eid= root") { Process::UID.eid = 0 }
      show("UID.switch") { Process::UID.switch }
      show("UID.switch block") { Process::UID.switch { 1 } }
      show("GID.switch") { Process::GID.switch }
      # A name that resolves is still refused; a name that does not never gets
      # as far as the syscall.
      show("Sys.setuid by name") { Process::Sys.setuid("root") }
      show("Sys.setuid bad name") { Process::Sys.setuid("nosuchuser__") }
      show("Sys.setgid bad name") { Process::Sys.setgid("nosuchgroup__") }

    RUBY

    _(result).must_answer <<~'OUT'
      Sys.setuid root: Errno::EPERM: Operation not permitted
      Sys.setgid wheel: Errno::EPERM: Operation not permitted
      Sys.seteuid root: Errno::EPERM: Operation not permitted
      Sys.setreuid root: Errno::EPERM: Operation not permitted
      UID.change_privilege root: Errno::EPERM: Operation not permitted
      UID.grant_privilege root: Errno::EPERM: Operation not permitted
      UID.eid= root: Errno::EPERM: Operation not permitted
      UID.switch: Errno::EPERM: Operation not permitted
      UID.switch block: Errno::EPERM: Operation not permitted
      GID.switch: Errno::EPERM: Operation not permitted
      Sys.setuid by name: Errno::EPERM: Operation not permitted
      Sys.setuid bad name: ArgumentError: can't find user for nosuchuser__
      Sys.setgid bad name: ArgumentError: can't find group for nosuchgroup__
    OUT
  end

  it "setresuid and setresgid raise NotImplementedError" do
    result = zr(<<~'RUBY')

      # `Process::Sys`, `Process::UID` and `Process::GID` -- the identity surface.
      #
      # Every id printed here is compared against one the process already knows,
      # never printed raw, so the output is the same on any machine. Nothing in
      # this file can change an id: an unprivileged process may only re-assert the
      # ids it already holds, and every other request is refused.

      uid = Process.uid
      euid = Process.euid
      gid = Process.gid
      egid = Process.egid

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # `setresuid`/`setresgid` are the not-implemented stubs, which take any
      # arguments at all and still report arity 0.
      show("Sys.setresuid") { Process::Sys.setresuid(0, 0, 0) }
      show("Sys.setresgid") { Process::Sys.setresgid }
      puts "setresuid arity: #{Process::Sys.method(:setresuid).arity}"

    RUBY

    _(result).must_answer <<~'OUT'
      Sys.setresuid: NotImplementedError: setresuid() function is unimplemented on this machine
      Sys.setresgid: NotImplementedError: setresgid() function is unimplemented on this machine
      setresuid arity: 0
    OUT
  end

  it "re_exchangeable? answers for the platform, and UID and GID agree" do
    result = zr(<<~'RUBY')

      # `Process::Sys`, `Process::UID` and `Process::GID` -- the identity surface.
      #
      # Every id printed here is compared against one the process already knows,
      # never printed raw, so the output is the same on any machine. Nothing in
      # this file can change an id: an unprivileged process may only re-assert the
      # ids it already holds, and every other request is refused.

      uid = Process.uid
      euid = Process.euid
      gid = Process.gid
      egid = Process.egid

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # `re_exchangeable?` answers for the platform, so the golden checks that
      # `re_exchange` AGREES with it rather than printing either answer.
      [Process::UID, Process::GID].each do |m|
        swappable = m.re_exchangeable?
        agreed = begin
          m.re_exchange
          swappable
        rescue NotImplementedError
          !swappable
        rescue SystemCallError
          swappable
        end
        puts "#{m} re_exchange agrees: #{agreed}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Process::UID re_exchange agrees: true
      Process::GID re_exchange agrees: true
    OUT
  end

  it "process surface batch1" do
    result = zr(<<~'RUBY')
      # Process syscall-wrapper surface (batch 1): pgid/session queries, resource
      # limits, and the non-effectful setters that return stable values. Output is
      # written as relational/type assertions so it stays byte-identical to CRuby
      # across machines rather than baking in platform-specific numbers.

      # Process-group / session queries agree with the no-arg forms.
      puts Process.getpgid(0) == Process.getpgrp

      # getrlimit returns a [soft, hard] pair of Integers with soft <= hard
      # (RLIM_INFINITY compares greater than any finite limit).
      soft, hard = Process.getrlimit(Process::RLIMIT_NOFILE)
      puts [soft, hard].all? { |v| v.is_a?(Integer) }
      puts soft <= hard

      # The RLIMIT_* / wait-flag constants are defined Integers.
      puts [Process::RLIMIT_NOFILE, Process::RLIMIT_CPU, Process::WNOHANG,
            Process::WUNTRACED].all? { |c| c.is_a?(Integer) }

      # RLIM_INFINITY is the saturating sentinel: greater than any real soft limit.
      puts Process::RLIM_INFINITY >= hard

      # warmup is a no-op hint that answers true.
      puts Process.warmup

      # setproctitle echoes the title string back.
      puts(Process.setproctitle("zr-batch1") == "zr-batch1")

      # maxgroups reads back a positive Integer, and a write is clamped by the OS
      # ceiling (never larger than what we asked for) but stays positive.
      Process.maxgroups = 8
      puts Process.maxgroups.is_a?(Integer) && Process.maxgroups.positive?
      puts Process.maxgroups <= 8

      # The whole new surface answers respond_to? affirmatively.
      puts %i[getpgid setpgid setpgrp setsid setpriority getrlimit setrlimit
              maxgroups warmup setproctitle initgroups daemon].all? { |m|
        Process.respond_to?(m)
      }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "ractor make shareable freezes a proc through the dynamic rows" do
    result = zr(<<~'RUBY')
      # `Ractor.make_shareable` on a Proc freezes it in place (returns the same
      # object) and `shareable?` reports the frozen state -- the ostruct
      # `new_ostruct_member!` shape (`nil.instance_eval { Proc.new { ... } }`
      # then `::Ractor.make_shareable(proc)`), where the `::Ractor` cpath form
      # exercises the runtime class-method rows rather than the static fold.
      # Oracle-verified. (zr freezes without CRuby's isolation check, so the
      # IsolationError arm is deliberately not pinned.)

      name = :a
      pr = nil.instance_eval { Proc.new { name } }
      r = ::Ractor.make_shareable(pr)
      p r.equal?(pr)
      p pr.frozen?
      p ::Ractor.shareable?(pr)
      p ::Ractor.shareable?(proc { 1 })
      p ::Ractor.shareable?(:sym)
      p ::Ractor.shareable?("mut")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      true
      false
    OUT
  end

  it "refinement import methods surface" do
    result = zr(<<~'RUBY')
      # `Refinement#import_methods` copies a module's OWN method entries into the
      # refinement. The runtime did the copying and reported them in
      # `instance_methods(false)`, but two halves were missing: a String receiver has
      # no `RObj` for the copied `MethodImpl` to bind against, and the COMPILER never
      # learned the names -- so no call site a `using` covers was ever nominated and
      # the imported method was unreachable however well it was copied.

      module Helpers
        def helper = :helped
        def shout(s) = s.upcase
        private def secret = :secret
      end

      module R
        refine String do
          import_methods Helpers
          def other = :other
        end
      end

      module Q
        refine Integer do
          import_methods Helpers
        end
      end

      using R
      using Q
      p "x".helper
      p "x".other
      p "ab".shout("hi")
      p 5.helper
      p "x".respond_to?(:helper)

      # An unrefined class is untouched.
      p [].respond_to?(:helper)
      begin
        [].helper
      rescue NoMethodError => e
        p e.class
      end

      # Visibility rides along.
      begin
        "x".secret
      rescue NoMethodError => e
        p e.class
      end
      p "x".send(:secret)

      # The module itself is unchanged.
      p Helpers.instance_methods(false).sort

      # A non-module argument is a TypeError, checked before anything imports.
      module Bad
        refine String do
          begin
            import_methods 42
          rescue TypeError => e
            p e.class
          end
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      :helped
      :other
      "HI"
      :helped
      true
      false
      NoMethodError
      NoMethodError
      :secret
      [:helper, :shout]
      TypeError
    OUT
  end

  it "require gated builtin row is always present" do
    result = zr(<<~'RUBY')
      # zr registers a builtin's require-gated rows unconditionally, so a method
      # that ruby only grows after `require "io/console"` (or `"io/nonblock"`)
      # answers `respond_to?` and appears in `instance_methods(false)` in a program
      # that never required it.
      #
      # The rows come from `ruby_class!` tables compiled into the runtime, and the
      # table is registered with the class. There is a mechanism for exactly this
      # -- `REG_REGISTER_BUILTIN` exists so a require-gated builtin (StringIO, Set,
      # Digest, JSON) registers at its `require` -- and the `io/console` and
      # `io/nonblock` rows simply do not use it: they are defined on `IO` itself
      # rather than as a gated overlay.
      #
      # 36 rows on `IO` today. It matters beyond reflection because
      # `respond_to?(:getch)` is how a library decides whether the console
      # extension is available, and zr answers yes before the require.
      #
      # `IO#to_s` is a different bug in the same list: ruby inherits it from
      # `Object` and zr declares it as IO's own, so it shows up in
      # `instance_methods(false)`. And `pathconf` is MISSING, which is the
      # ordinary direction and belongs to the method census.
      #
      # The census gates the "zr is missing a row" direction only; this EXTRA
      # direction is ungated, which is why a cluster this size went unrecorded.
      #
      # Oracle: none of these rows exist until the library is required.
      p IO.instance_methods(false).include?(:getch)
      p IO.instance_methods(false).include?(:nonblock)
      p IO.instance_methods(false).include?(:to_s)
      p STDOUT.respond_to?(:winsize)
      p STDOUT.respond_to?(:cooked)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
      false
    OUT
  end

  it "require gated row waits for its require" do
    result = zr(<<~'RUBY')
      # `io/console` and `io/nonblock` are require-gated extensions in ruby. zr
      # implements them natively, so their rows sit in `IO`'s own table -- one
      # class owns one table -- but they do not answer before the require.
      #
      # That is observable beyond reflection: `respond_to?(:getch)` is how a
      # library decides whether the console extension is there at all, and a
      # `NoMethodError` is what it expects when it is not.
      #
      # `IO#to_s` is the same list's other half in the opposite direction: ruby
      # inherits it from `Kernel`, so it is not in IO's own list.
      p IO.instance_methods(false).include?(:getch)
      p IO.instance_methods(false).include?(:nonblock)
      p IO.instance_methods(false).include?(:to_s)
      p IO.instance_method(:to_s).owner.to_s
      p STDOUT.respond_to?(:winsize)
      p STDOUT.respond_to?(:cooked)
      p STDOUT.respond_to?(:nonblock)
      p IO.respond_to?(:console)
      p IO.singleton_methods(false).include?(:console)
      begin
        STDOUT.getch
      rescue NoMethodError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      "Kernel"
      false
      false
      false
      false
      false
      "undefined method 'getch' for an instance of IO"
    OUT
  end

  it "safe nav poly builtin surface" do
    result = zr(<<~'RUBY')
      # Every builtin name a `&.` can carry on a boxed receiver. The point is not the
      # values: it is that the program BUILDS and that a nil receiver answers nil.
      # Some names answer a raw scalar, and the safe-navigation guard must box that
      # answer. The list covers every such name, e.g. `begin`, `end`, `count`,
      # `bytes` and `infinite?`.
      VALS = [1, "abc", 1.5, [1], { "a" => 1 }]

      # the Hash/Enumerable face names, whose arm converts the receiver before it
      # re-dispatches: the conversion must sit INSIDE the nil guard, and must happen
      # once
      def face_entries(v) = v&.entries
      def face_to_a(v) = v&.to_a
      def face_keys(v) = v&.keys
      def face_values(v) = v&.values

      p face_entries({ "a" => 1 })
      p face_entries(nil)
      p face_to_a({ "a" => 1 })
      p face_to_a(nil)
      p face_keys({ "a" => 1 })
      p face_keys(nil)
      p face_values({ "a" => 1 })
      p face_values(nil)

      def f_abs(v) = v&.abs
      def f_begin(v) = v&.begin
      def f_bit_length(v) = v&.bit_length
      def f_bytes(v) = v&.bytes
      def f_bytesize(v) = v&.bytesize
      def f_capitalize(v) = v&.capitalize
      def f_ceil(v) = v&.ceil
      def f_chars(v) = v&.chars
      def f_chomp(v) = v&.chomp
      def f_chop(v) = v&.chop
      def f_class(v) = v&.class
      def f_compact(v) = v&.compact
      def f_count(v) = v&.count
      def f_denominator(v) = v&.denominator
      def f_downcase(v) = v&.downcase
      def f_each_char(v) = v&.each_char
      def f_empty_p(v) = v&.empty?
      def f_end(v) = v&.end
      def f_end_with_p(v) = v&.end_with?("a")
      def f_eql_p(v) = v&.eql?("a")
      def f_equal_p(v) = v&.equal?("a")
      def f_even_p(v) = v&.even?
      def f_finite_p(v) = v&.finite?
      def f_first(v) = v&.first
      def f_flatten(v) = v&.flatten
      def f_floor(v) = v&.floor
      def f_frozen_p(v) = v&.frozen?
      def f_hash(v) = v&.hash
      def f_include_p(v) = v&.include?("a")
      def f_infinite_p(v) = v&.infinite?
      def f_inspect(v) = v&.inspect
      def f_instance_of_p(v) = v&.instance_of?(String)
      def f_integer_p(v) = v&.integer?
      def f_is_a_p(v) = v&.is_a?(String)
      def f_keys(v) = v&.keys
      def f_kind_of_p(v) = v&.kind_of?(String)
      def f_last(v) = v&.last
      def f_lazy(v) = v&.lazy
      def f_length(v) = v&.length
      def f_lines(v) = v&.lines
      def f_max(v) = v&.max
      def f_min(v) = v&.min
      def f_nan_p(v) = v&.nan?
      def f_negative_p(v) = v&.negative?
      def f_next(v) = v&.next
      def f_nil_p(v) = v&.nil?
      def f_numerator(v) = v&.numerator
      def f_object_id(v) = v&.object_id
      def f_odd_p(v) = v&.odd?
      def f_ord(v) = v&.ord
      def f_positive_p(v) = v&.positive?
      def f_reverse(v) = v&.reverse
      def f_round(v) = v&.round
      def f_size(v) = v&.size
      def f_sort(v) = v&.sort
      def f_start_with_p(v) = v&.start_with?("a")
      def f_step(v) = v&.step
      def f_strip(v) = v&.strip
      def f_succ(v) = v&.succ
      def f_sum(v) = v&.sum
      def f_to_a(v) = v&.to_a
      def f_to_c(v) = v&.to_c
      def f_to_f(v) = v&.to_f
      def f_to_i(v) = v&.to_i
      def f_to_r(v) = v&.to_r
      def f_to_s(v) = v&.to_s
      def f_to_sym(v) = v&.to_sym
      def f_truncate(v) = v&.truncate
      def f_uniq(v) = v&.uniq
      def f_upcase(v) = v&.upcase
      def f_values(v) = v&.values
      def f_zero_p(v) = v&.zero?

      p f_abs(nil)
      p f_begin(nil)
      p f_bit_length(nil)
      p f_bytes(nil)
      p f_bytesize(nil)
      p f_capitalize(nil)
      p f_ceil(nil)
      p f_chars(nil)
      p f_chomp(nil)
      p f_chop(nil)
      p f_class(nil)
      p f_compact(nil)
      p f_count(nil)
      p f_denominator(nil)
      p f_downcase(nil)
      p f_each_char(nil)
      p f_empty_p(nil)
      p f_end(nil)
      p f_end_with_p(nil)
      p f_eql_p(nil)
      p f_equal_p(nil)
      p f_even_p(nil)
      p f_finite_p(nil)
      p f_first(nil)
      p f_flatten(nil)
      p f_floor(nil)
      p f_frozen_p(nil)
      p f_hash(nil)
      p f_include_p(nil)
      p f_infinite_p(nil)
      p f_inspect(nil)
      p f_instance_of_p(nil)
      p f_integer_p(nil)
      p f_is_a_p(nil)
      p f_keys(nil)
      p f_kind_of_p(nil)
      p f_last(nil)
      p f_lazy(nil)
      p f_length(nil)
      p f_lines(nil)
      p f_max(nil)
      p f_min(nil)
      p f_nan_p(nil)
      p f_negative_p(nil)
      p f_next(nil)
      p f_nil_p(nil)
      p f_numerator(nil)
      p f_object_id(nil)
      p f_odd_p(nil)
      p f_ord(nil)
      p f_positive_p(nil)
      p f_reverse(nil)
      p f_round(nil)
      p f_size(nil)
      p f_sort(nil)
      p f_start_with_p(nil)
      p f_step(nil)
      p f_strip(nil)
      p f_succ(nil)
      p f_sum(nil)
      p f_to_a(nil)
      p f_to_c(nil)
      p f_to_f(nil)
      p f_to_i(nil)
      p f_to_r(nil)
      p f_to_s(nil)
      p f_to_sym(nil)
      p f_truncate(nil)
      p f_uniq(nil)
      p f_upcase(nil)
      p f_values(nil)
      p f_zero_p(nil)

      # the value calls never run; they are what makes each parameter poly
      if false
        p f_abs(VALS[0])
        p f_begin(VALS[0])
        p f_bit_length(VALS[0])
        p f_bytes(VALS[0])
        p f_bytesize(VALS[0])
        p f_capitalize(VALS[0])
        p f_ceil(VALS[0])
        p f_chars(VALS[0])
        p f_chomp(VALS[0])
        p f_chop(VALS[0])
        p f_class(VALS[0])
        p f_compact(VALS[0])
        p f_count(VALS[0])
        p f_denominator(VALS[0])
        p f_downcase(VALS[0])
        p f_each_char(VALS[0])
        p f_empty_p(VALS[0])
        p f_end(VALS[0])
        p f_end_with_p(VALS[0])
        p f_eql_p(VALS[0])
        p f_equal_p(VALS[0])
        p f_even_p(VALS[0])
        p f_finite_p(VALS[0])
        p f_first(VALS[0])
        p f_flatten(VALS[0])
        p f_floor(VALS[0])
        p f_frozen_p(VALS[0])
        p f_hash(VALS[0])
        p f_include_p(VALS[0])
        p f_infinite_p(VALS[0])
        p f_inspect(VALS[0])
        p f_instance_of_p(VALS[0])
        p f_integer_p(VALS[0])
        p f_is_a_p(VALS[0])
        p f_keys(VALS[0])
        p f_kind_of_p(VALS[0])
        p f_last(VALS[0])
        p f_lazy(VALS[0])
        p f_length(VALS[0])
        p f_lines(VALS[0])
        p f_max(VALS[0])
        p f_min(VALS[0])
        p f_nan_p(VALS[0])
        p f_negative_p(VALS[0])
        p f_next(VALS[0])
        p f_nil_p(VALS[0])
        p f_numerator(VALS[0])
        p f_object_id(VALS[0])
        p f_odd_p(VALS[0])
        p f_ord(VALS[0])
        p f_positive_p(VALS[0])
        p f_reverse(VALS[0])
        p f_round(VALS[0])
        p f_size(VALS[0])
        p f_sort(VALS[0])
        p f_start_with_p(VALS[0])
        p f_step(VALS[0])
        p f_strip(VALS[0])
        p f_succ(VALS[0])
        p f_sum(VALS[0])
        p f_to_a(VALS[0])
        p f_to_c(VALS[0])
        p f_to_f(VALS[0])
        p f_to_i(VALS[0])
        p f_to_r(VALS[0])
        p f_to_s(VALS[0])
        p f_to_sym(VALS[0])
        p f_truncate(VALS[0])
        p f_uniq(VALS[0])
        p f_upcase(VALS[0])
        p f_values(VALS[0])
        p f_zero_p(VALS[0])
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [["a", 1]]
      nil
      [["a", 1]]
      nil
      ["a"]
      nil
      [1]
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
    OUT
  end

  it "signal module surface" do
    result = zr(<<~'RUBY')
      # The Signal module surface: list/signame, trap validation and previous-handler
      # return, handler firing via Process.kill, the EXIT pseudo-signal hook, the
      # Signal constant itself, and SignalException/Interrupt objects.
      h = Signal.list
      p h["INT"]
      p h["EXIT"]
      p h["TERM"]
      p Signal.list.class
      p Signal.signame(2)
      p Signal.signame(999)
      p Signal.signame(0)
      p Signal.signame(Signal.list["CHLD"])   # the CHLD number differs per platform
      p Signal.trap("USR1", "IGNORE")
      p Signal.trap("USR1", "DEFAULT")
      p((Signal.trap("NOPE", "IGNORE") rescue $!.class))
      p((Signal.trap("KILL", "IGNORE") rescue $!.class))
      p((Signal.trap(9999, "IGNORE") rescue $!.class))
      old = Signal.trap("USR2") { }
      p Signal.trap("USR2", "DEFAULT").class
      p Signal
      p Signal.class
      p defined?(Signal)
      e = SignalException.new("INT")
      p e.message, e.signo, e.signm, e.class
      p SignalException.new(:TERM).message
      p SignalException.new(2).message
      i = Interrupt.new
      p i.message, i.signo
      p Interrupt.new("stop").message
      p((SignalException.new("NOPE") rescue $!.class))
      begin; raise Interrupt; rescue SignalException => se; p se.class; end
      p Interrupt.superclass
      p Process.kill(0, Process.pid)
      p((Process.kill(0, 99999999) rescue $!.class))
      Signal.trap("USR1") { |n| puts "handler #{n == Signal.list["USR1"]}" }   # the USR1 number differs per platform
      Process.kill("USR1", Process.pid)
      sleep 0.05
      Signal.trap("EXIT") { puts "exit-handler-ran" }
      puts "main"
      Signal.trap("URG", "SYSTEM_DEFAULT")
      p(Signal.trap("URG", "DEFAULT"))
      p(Signal.trap("EXIT", "IGNORE").class)
      hits = 0
      Signal.trap("USR2") { |n| hits += 1 }
      Process.kill("USR2", Process.pid)
      sleep 0.05
      p hits
      log = []
      at_exit { log << "bye"; puts log.length }
    RUBY

    _(result).must_answer <<~'OUT'
      2
      0
      15
      Hash
      "INT"
      nil
      "EXIT"
      "CHLD"
      "DEFAULT"
      "IGNORE"
      ArgumentError
      Errno::EINVAL
      ArgumentError
      Proc
      Signal
      Module
      "constant"
      "SIGINT"
      2
      "SIGINT"
      SignalException
      "SIGTERM"
      "SIGINT"
      "Interrupt"
      2
      "stop"
      ArgumentError
      Interrupt
      SignalException
      1
      Errno::ESRCH
      handler true
      main
      "SYSTEM_DEFAULT"
      Proc
      1
      1
    OUT
  end

  it "symbol to proc arity and io fcntl" do
    result = zr(<<~'RUBY')
      # :name.to_proc reports arity -2 (receiver + optional args); IO#fcntl runs
      # the raw syscall (F_GETFD reads the close-on-exec flag on the open file).

      p :upcase.to_proc.arity
      p ["x", "y"].map(&:upcase)
      pth = "/tmp/sp_e2e_fcntl_#{Process.pid}.tmp"
      File.write(pth, "hi")
      File.open(pth) { |f| p(f.fcntl(1, 0).class) }
      File.delete(pth)
    RUBY

    _(result).must_answer <<~'OUT'
      -2
      ["X", "Y"]
      Integer
    OUT
  end

  it "thread group surface matches the default group model" do
    result = zr(<<~'RUBY')
      # The always-on `ThreadGroup` surface the timeout gem needs:
      # `Thread#group` answers the shared `ThreadGroup::Default`, which is
      # never enclosed, accepts `#add`, and type-checks its argument.

      g = Thread.current.group
      p g.equal?(ThreadGroup::Default)
      p g.enclosed?
      t = Thread.new { 1 }
      p ThreadGroup::Default.add(t).equal?(g)
      t.join
      begin
        g.add(42)
      rescue TypeError => e
        puts e.message
      end
      p Thread.handle_interrupt(Exception => :never) { :ran }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      wrong argument type Integer (expected VM/thread)
      :ran
    OUT
  end

  it "thread surface" do
    result = zr(<<~'RUBY')
      # `Thread`'s scheduling, storage and interrupt surface. Values that differ from
      # run to run (a native thread id, a backtrace's own paths) are asserted by
      # SHAPE, so the file is byte-identical under both engines.

      t = Thread.new { Thread.stop }
      Thread.pass until t.stop?

      # Priority: stored and read back. CRuby's is advisory too.
      puts "priority default: #{t.priority}"
      t.priority = 3
      puts "priority set: #{t.priority}"

      puts "stop?: #{t.stop?}"
      puts "alive?: #{t.alive?}"
      puts "native id: #{t.native_thread_id.is_a?(Integer)}"
      puts "pending?: #{t.pending_interrupt?}"

      # `#run` wakes a stopped thread and lets it finish.
      t.run
      t.join
      puts "after join alive?: #{t.alive?}"
      puts "dead backtrace: #{t.backtrace.inspect}"
      puts "dead native id: #{t.native_thread_id.inspect}"

      # `wakeup` on a dead thread is a ThreadError.
      begin
        t.wakeup
      rescue ThreadError => e
        puts "wakeup dead: #{e.message}"
      end

      # Thread-local storage: `#fetch`'s three-way miss.
      me = Thread.current
      me[:seen] = 1
      puts "fetch hit: #{me.fetch(:seen)}"
      puts "fetch default: #{me.fetch(:nope, :fallback)}"
      puts "fetch block: #{me.fetch(:nope) { |k| "no #{k}" }}"
      begin
        me.fetch(:nope)
      rescue KeyError => e
        puts "fetch miss: #{e.message}"
      end

      # `Thread.start` and `.fork` are `.new` under other names.
      puts "start: #{Thread.start(4) { |n| n * 2 }.value}"
      puts "fork: #{Thread.fork(5) { |n| n + 1 }.value}"

      # `Thread.kill(thr)` is the class spelling of `#kill`.
      victim = Thread.new { sleep 30 }
      Thread.kill(victim)
      victim.join
      puts "killed: #{victim.alive?}"

      puts "ignore_deadlock: #{Thread.ignore_deadlock}"
      Thread.ignore_deadlock = true
      puts "ignore_deadlock set: #{Thread.ignore_deadlock}"
      Thread.ignore_deadlock = false

      puts "abort_on_exception: #{Thread.abort_on_exception}"
      puts "pending_interrupt?: #{Thread.pending_interrupt?}"

      # The caller's own frames, as objects.
      seen = []
      Thread.each_caller_location { |loc| seen << loc.class }
      puts "each_caller_location: #{seen.uniq.inspect}"

      puts "current backtrace: #{me.backtrace.is_a?(Array)}"
      puts "current locations: #{me.backtrace_locations.first.class}"

      # A trace func is refused rather than accepted and never called.
      puts "set_trace_func nil: #{me.set_trace_func(nil).inspect}"
    RUBY

    _(result).must_answer <<~'OUT'
      priority default: 0
      priority set: 3
      stop?: true
      alive?: true
      native id: true
      pending?: false
      after join alive?: false
      dead backtrace: nil
      dead native id: nil
      wakeup dead: killed thread
      fetch hit: 1
      fetch default: fallback
      fetch block: no nope
      fetch miss: key not found: :nope
      start: 8
      fork: 6
      killed: false
      ignore_deadlock: false
      ignore_deadlock set: true
      abort_on_exception: false
      pending_interrupt?: false
      each_caller_location: []
      current backtrace: true
      current locations: Thread::Backtrace::Location
      set_trace_func nil: nil
    OUT
  end

  it "time new is a class method row" do
    result = zr(<<~'RUBY')
      p Time.method(:new).owner
      p Time.singleton_methods(false).sort
      p [Regexp.method(:new).owner, Hash.method(:new).owner, Range.method(:new).owner]
      p [Array.method(:new).owner, String.method(:new).owner]
    RUBY

    _(result).must_answer <<~'OUT'
      Class
      [:at, :gm, :local, :mktime, :now, :utc]
      [Class, Class, Class]
      [#<Class:Array>, #<Class:String>]
    OUT
  end

  it "tracepoint reflection rows" do
    result = zr(<<~'RUBY')
      # The `TracePoint` rows that read nothing off the frame: the reentry guard,
      # the per-VM statistics, and the four accessors a `:line` event refuses in
      # CRuby too.

      # Outside a handler there is nothing to re-enter.
      begin
        TracePoint.allow_reentry { 1 }
      rescue RuntimeError => e
        puts "allow_reentry outside: #{e.message}"
      end

      puts "stat: #{TracePoint.stat.class}"

      seen = []
      tp = TracePoint.new(:line) do |t|
        %i[return_value parameters eval_script instruction_sequence].each do |m|
          begin
            t.public_send(m)
            seen << "#{m}: answered"
          rescue RuntimeError => e
            seen << "#{m}: #{e.message}"
          end
        end
        t.disable
      end

      tp.enable
      x = 1
      tp.disable
      puts seen.uniq.join("\n")

      # Every accessor refuses from outside a handler first, whatever the event.
      %i[return_value parameters self binding].each do |m|
        TracePoint.new(:line) { }.public_send(m)
      rescue RuntimeError => e
        puts "#{m} outside: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      allow_reentry outside: No need to allow reentrance.
      stat: Hash
      return_value: not supported by this event
      parameters: not supported by this event
      eval_script: not supported by this event
      instruction_sequence: not supported by this event
      return_value outside: access from outside
      parameters outside: access from outside
      self outside: access from outside
      binding outside: access from outside
    OUT
  end
end
