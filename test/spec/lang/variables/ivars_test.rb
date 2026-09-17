# frozen_string_literal: true

require "spec_helper"

describe "Variables: instance and class variables" do
  it "boxs class ivar and class variable are its own" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"})
      # Class ivars and class variables, which live in tables of their own.



      b = Ruby::Box.new
      b.eval("class Array; @civ = 7; def self.civ = @civ; end")
      b.eval("class Array; @@cv = 3; def self.cv = @@cv; end")
      p(begin; Array.civ; rescue NoMethodError; :nome; end)
      p b.eval("Array.civ")
      p b.eval("Array.cv")
    RUBY

    _(result).must_answer <<~'OUT'
      :nome
      7
      3
    OUT
  end

  it "builtin reopen cvars consts and class methods" do
    result = ze0(<<~'RUBY')
      # Class-level state on a builtin: `@@cvar` + `CONST` in the body (ordinary
      # ownership machinery, owner = the builtin's ClassId), `def self.x` via the
      # generated `__bm_Array` container, and `Array::LIMIT` readable externally.

      class Array
        @@made = 0
        LIMIT = 3

        def self.tally_up
          @@made = @@made + 1
          @@made
        end

        def under_limit?
          length < LIMIT
        end
      end

      puts Array.tally_up
      puts Array.tally_up
      puts [1, 2].under_limit?
      puts [1, 2, 3, 4].under_limit?
      puts Array::LIMIT
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      true
      false
      3
    OUT
  end

  it "class method defined and class variable reflection" do
    result = ze0(<<~'RUBY')
      class Base
        @@shared = 1
        def inherited_m; end
      end
      class Sub < Base
        def own_m; end
      end
      p Sub.method_defined?(:own_m)
      p Sub.method_defined?(:inherited_m)
      p Sub.method_defined?(:frozen?)
      p Sub.method_defined?(:nope)
      p Base.class_variable_defined?(:@@shared)
      p Base.class_variable_get(:@@shared)
      Base.class_variable_set(:@@shared, 42)
      p Base.class_variable_get(:@@shared)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      true
      1
      42
    OUT
  end

  it "class objects answer the instance variable reflection family" do
    result = ze0(<<~'RUBY')
      class K
        @a = 1
      end
      p K.instance_variable_get(:@a)
      p K.instance_variable_get("@a")
      p K.instance_variable_get(:@nope)
      p K.instance_variables
      p K.instance_variable_set(:@b, 2)
      p K.instance_variables
      p K.instance_variable_defined?(:@a)
      p K.instance_variable_defined?(:@zz)
      begin
        K.instance_variable_get(:a)
      rescue NameError => e
        puts "NameError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      nil
      [:@a]
      2
      [:@a, :@b]
      true
      false
      NameError: 'a' is not allowed as an instance variable name
    OUT
  end

  it "class shift self methods can read and write class variables" do
    _(ze0(<<~'RUBY')).must_answer "2\n"
      class Counter
        class << self
          def reset
            @@total = 0
          end
          def bump
            @@total += 1
          end
          def total
            @@total
          end
        end
      end
      Counter.reset
      Counter.bump
      Counter.bump
      puts Counter.total
    RUBY
  end

  it "class variable is shared with a subclass that never declares its own" do
    result = ze0(<<~'RUBY')
      class Base
        @@count = 0
        def bump
          @@count += 1
        end
        def count
          @@count
        end
      end
      class Sub < Base
        def bump_twice
          @@count += 1
          @@count += 1
        end
      end
      b = Base.new
      s = Sub.new
      b.bump
      s.bump_twice
      puts b.count
      puts s.count
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
    OUT
  end

  it "class variables" do
    result = ze0(<<~'RUBY')
      # A class variable belongs to the class its source is written in, and the
      # storage is ONE slot the whole ancestry shares.
      class Counter
        @@total = 0
        @@names = []

        def self.total = @@total

        def initialize(name)
          @@total += 1
          @@names << name
        end

        def seen = @@names.dup
      end

      Counter.new("a")
      Counter.new("b")
      p Counter.total
      p Counter.new("c").seen
      p Counter.class_variables.sort
      p Counter.class_variable_get(:@@total)

      # A method written in a SUBCLASS reaches the superclass's slot, because
      # that is where ruby's own lookup stops.
      class Sub < Counter
        def self.bump = @@total += 10
        def self.peek = @@total
      end

      Sub.bump
      p Counter.total
      p Sub.peek
      p Sub.class_variables.sort

      # `||=` is the one read that tolerates a name nobody assigned.
      class Lazy
        def self.memo = @@memo ||= :made
        def self.again = @@memo
      end
      p Lazy.memo
      p Lazy.memo
      p Lazy.again

      # Every other read of one raises.
      class Missing
        def self.peek = @@never

        def self.bumped
          @@nope += 1
        end
      end

      [-> { Missing.peek }, -> { Missing.bumped }].each do |go|
        go.call
      rescue NameError => e
        p e.message
      end

      # A module's class variables are its own.
      module Tally
        @@hits = 0

        def self.hit = @@hits += 1
        def self.hits = @@hits
      end

      Tally.hit
      Tally.hit
      p Tally.hits
      p Tally.class_variables

      # A write answers the value assigned, and reaches the same slot from a
      # class body as from a method.
      class Direct
        @@here = :body

        def self.set(v)
          @@here = v
        end

        def self.here = @@here
      end
      p Direct.here
      p Direct.set(:method)
      p Direct.here
    RUBY

    _(result).must_answer <<~'OUT'
      2
      ["a", "b", "c"]
      [:@@names, :@@total]
      3
      13
      13
      [:@@names, :@@total]
      :made
      :made
      :made
      "uninitialized class variable @@never in Missing"
      "uninitialized class variable @@nope in Missing"
      2
      [:@@hits]
      :body
      :method
      :method
    OUT
  end

  it "class variables at module and top level scope" do
    result = ze0(<<~'RUBY')
      # `@@x` written in a module body and read back through its own `def self.`
      # accessors. Bare at the TOP LEVEL it raises instead -- see
      # `top_level_class_variable_raises` below.

      module Conf
        @@secret = ""
        def self.secret; @@secret; end
        def self.secret=(v); @@secret = v; end
      end
      puts Conf.secret.length
      Conf.secret = "hi"
      puts Conf.secret
    RUBY

    _(result).must_answer <<~'OUT'
      0
      hi
    OUT
  end

  it "cvar empty container" do
    result = ze0(<<~'RUBY')
      # An empty `[]` / `{}` assigned to a class variable carries no element or key
      # type, so the slot was declared sp_int (the codegen fallback) while the write
      # emitted a real container -- the C build failed on the store. The variant now
      # comes from the class variable's own usage, the way a global's and a
      # constant's already did (#4054).

      # a bare `{}` with no index writes at all still needs a declarable slot
      class Empty
        @@h = {}
        def self.h = @@h
      end
      puts Empty.h.size

      # String keys
      class StrKeyed
        @@h = {}
        def self.add(k, v) = @@h[k] = v
        def self.get(k) = @@h[k]
        def self.size = @@h.size
      end
      StrKeyed.add("a", 1)
      StrKeyed.add("b", 2)
      puts StrKeyed.get("a")
      puts StrKeyed.get("b")
      puts StrKeyed.size

      # Symbol keys take the symbol-keyed variant, not the String default
      class SymKeyed
        @@h = {}
        def self.add(k) = @@h[k] = true
        def self.on?(k) = @@h[k] ? true : false
      end
      SymKeyed.add(:x)
      puts SymKeyed.on?(:x)
      puts SymKeyed.on?(:y)

      # an empty `[]` holds whatever is pushed later
      class Bag
        @@a = []
        def self.add(x) = @@a.push(x)
        def self.all = @@a
      end
      Bag.add("s")
      Bag.add(2)
      p Bag.all

      # a bare `[]` never pushed to
      class EmptyBag
        @@a = []
        def self.all = @@a
      end
      p EmptyBag.all

      # `Hash.new` with no arguments is the same empty producer
      class Made
        @@h = Hash.new
        def self.add(k, v) = @@h[k] = v
        def self.get(k) = @@h[k]
      end
      Made.add("k", "v")
      puts Made.get("k")

      # a non-empty literal keeps working
      class Seeded
        @@h = {"a" => 1}
        @@a = [1, 2]
        def self.h = @@h
        def self.a = @@a
      end
      puts Seeded.h["a"]
      p Seeded.a
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
      2
      true
      false
      ["s", 2]
      []
      v
      1
      [1, 2]
    OUT
  end

  it "defined cvar is runtime" do
    result = ze0(<<~'RUBY')
      # `defined?(@@x)` answers at RUNTIME: nil before the first assignment, then
      # "class variable" -- a static answer breaks every runs-once guard of the
      # shape rspec's ensure_example_groups_are_configured uses.
      class Config
        def self.check
          unless defined?(@@configured)
            puts "configuring"
            @@configured = true
          end
          puts "checked: #{defined?(@@configured).inspect}"
        end
      end

      p defined?(@@nowhere)
      Config.check
      Config.check
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      configuring
      checked: "class variable"
      checked: "class variable"
    OUT
  end

  it "defined instance variable reflects assignment" do
    result = ze0(<<~'RUBY')
      # defined?(@iv) is "instance-variable" only once assigned, else nil.
      # (A never-assigned ivar referenced ONLY inside a class body's defined?
      # hits the documented assigned-nil-vs-never-assigned limitation for
      # struct-backed objects; top-level ivars use a dynamic map and are exact.)

      p defined?(@never)
      @written = 1
      p defined?(@written)
      class C
        def initialize; @a = 1; end
        def check; defined?(@a); end
      end
      p C.new.check
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "instance-variable"
      "instance-variable"
    OUT
  end

  it "globals and cvars are mutex protectable across threads" do
    result = ze0(<<~'RUBY')
      $total = 0
      class Counter
        @@n = 0
        def self.bump
          @@n = @@n + 1
        end
        def self.n
          @@n
        end
      end
      m = Mutex.new
      t1 = Thread.new { 100.times { m.synchronize { $total += 1 } } }
      t2 = Thread.new { 100.times { m.synchronize { Counter.bump } } }
      t1.join
      t2.join
      puts $total
      puts Counter.n
    RUBY

    _(result).must_answer <<~'OUT'
      100
      100
    OUT
  end

  it "instance variable reflection on objects" do
    result = ze0(<<~'RUBY')
      # get/set/list over a concrete receiver, a poly receiver, missing names,
      # an empty object, and a malformed-name NameError.

      class Box
        def initialize(v); @v = v; @tag = "b"; end
      end
      b = Box.new(7)
      p b.instance_variables
      p b.instance_variable_get(:@v)
      b.instance_variable_set(:@v, 70)
      p b.instance_variable_get("@v")
      p b.instance_variable_get(:@missing)
      class Bare; end
      p Bare.new.instance_variables
      def peek(o) = o.instance_variable_get(:@v)
      p peek(Box.new(99))
      begin
        b.instance_variable_get(:v)
      rescue NameError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:@v, :@tag]
      7
      70
      nil
      []
      99
      'v' is not allowed as an instance variable name
    OUT
  end

  it "ivar in a class eval nested def targets the instance not the class" do
    result = ze0(<<~'RUBY')
      # Ivar codegen resolves a RUNTIME `self` ahead of the LEXICAL class context
      # it inherited. A `def` nested in a `class_eval` block sits inside
      # `Gadget`'s body (so `class_self` is set) but runs under a dynamic self, and
      # its `@v` must reach the INSTANCE, not the class's own ivar table. Read and
      # write must agree on this: when only the read was fixed, `@v += 1` read the
      # instance and wrote the class table, so the increment vanished.
      #
      # The `Counter`/`Mixed` halves pin the other direction -- a real class-method
      # `self` still reaches the class's own table, and a class-level `@cls` stays
      # distinct from an instance's same-named ivar.

      class Gadget
        def initialize(v); @v = v; end
        class_eval do
          def doubled; @v * 2; end
          def bump!; @v += 1; self; end
        end
      end
      g = Gadget.new(10)
      p g.doubled
      p g.bump!.doubled

      class Counter
        def self.tick; @n = (@n || 0) + 1; end
        def self.n; @n; end
      end
      Counter.tick; Counter.tick
      p Counter.n

      class Mixed
        @cls = "class-level"
        def self.cls; @cls; end
        def initialize; @cls = "instance-level"; end
        def inst; @cls; end
      end
      p Mixed.cls
      p Mixed.new.inst
      p Mixed.cls
    RUBY

    _(result).must_answer <<~'OUT'
      20
      22
      2
      "class-level"
      "instance-level"
      "class-level"
    OUT
  end

  it "ivar read of a ractor from another ractor raises isolation error" do
    _(ze0(<<~'RUBY', path: "lang/variables/an_ivar_read_of_a_ractor_from_another_ractor_raises_isolation_error.rb")).must_answer "[Ractor::IsolationError, \"can not access instance variables of shareable objects from non-main Ractors\"]\n", stderr: "lang/variables/an_ivar_read_of_a_ractor_from_another_ractor_raises_isolation_error.rb:7: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      # Reading an instance variable of a Ractor from a non-main ractor is an
      # IsolationError, and the raise must leave `@peek` with no value at
      # all: the read is a call the runtime checks like any other.
      class Ractor
        def peek = [@peek, :after]
      end
      r = Ractor.new do
        begin
          Ractor.current.peek
        rescue Ractor::IsolationError => e
          [e.class, e.message]
        end
      end
      p r.value


    RUBY
  end

  it "ivar site shared by an object and a module writes the modules table" do
    result = ze0(<<~'RUBY')
      # One `@x ||= v` site serves a plain object, then a module and a class that
      # extend the same helper. The object's rows live in its cell; a module's or
      # class's live in its extension, so a site that has learned the object's
      # rows must not write a module's cell as if it were an object's.
      module Tagging
        def tag!
          @first ||= 1
          @second ||= 2
          @third ||= 3
          [@first, @second, @third]
        end
      end
      class Obj; include Tagging; end
      module M; extend Tagging; end
      class K; extend Tagging; end

      p Obj.new.tag!
      p M.tag!
      p [M.name, M.ancestors, M.instance_variables, M.class]
      p K.tag!
      p [K.name, K.superclass, K.ancestors, K.instance_variables, K.new.class]
      p [M.tag!, K.tag!, Obj.new.tag!]
      module M
        def self.more = [@first, @fourth ||= 4, instance_variables]
      end
      p M.more

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      ["M", [M], [:@first, :@second, :@third], Module]
      [1, 2, 3]
      ["K", Object, [K, Object, Kernel, BasicObject], [:@first, :@second, :@third], K]
      [[1, 2, 3], [1, 2, 3], [1, 2, 3]]
      [1, 4, [:@first, :@second, :@third, :@fourth]]
    OUT
  end

  it "ivar write on a frozen object raises and leaves the ivar unchanged" do
    result = ze0(<<~'RUBY')
      # The message carries the receiver's real `#<Pt:0xADDR @x=1>` inspect
      # (address normalized in-program). Semantics oracle-verified: a catchable
      # FrozenError, the ivar keeps its old value, readers still work.

      class Pt
        def initialize(x)
          @x = x
        end
        def set_x(v)
          @x = v
        end
        def x
          @x
        end
      end
      p1 = Pt.new(1)
      p1.freeze
      puts p1.frozen?
      begin
        p1.set_x(5)
      rescue FrozenError => e
        puts e.send(:message).gsub(/0x[0-9a-f]+/, "0xADDR")
      end
      puts p1.x
    RUBY

    _(result).must_answer <<~'OUT'
      true
      can't modify frozen Pt: #<Pt:0xADDR @x=1>
      1
    OUT
  end

  it "ivars from a three level plain inheritance chain are all present on the leaf" do
    _(ze0(<<~'RUBY')).must_answer "6\n"
      # A REAL bug found while adding this test: ivar-flattening originally
      # only scanned the MRO-winning materialized methods, missing any ivar
      # only ever touched through a `super`-reachable (but shadowed, not
      # winning) ancestor body -- `B#initialize`/`C#initialize` both call
      # `super` and their OWN bodies don't textually mention `@a`, only
      # `A#initialize`'s spliced-in body does. Fixed by collecting ivars from
      # EVERY ancestor's own methods, not just the ones that end up
      # materialized as the winning definition.

      class A
        def initialize
          @a = 1
        end
      end
      class B < A
        def initialize
          super
          @b = 2
        end
      end
      class C < B
        def initialize
          super
          @c = 3
        end
        def total
          @a + @b + @c
        end
      end
      puts C.new.total
    RUBY
  end

  it "ivars store real per instance state" do
    _(ze0(<<~'RUBY')).must_answer "5\n"
      class Point
        def initialize(x)
          @x = x
        end

        def x
          @x
        end
      end

      puts Point.new(5).x
    RUBY
  end

  it "module class variable is shared across every including class" do
    result = ze0(<<~'RUBY')
      # Verified against real Ruby first: `@@total` declared inside the
      # MODULE's own body is genuinely owned by the module itself -- every
      # class that includes it (even two entirely unrelated classes) shares
      # the SAME storage, not one copy per includer. The owner is the module a
      # materialized method's body actually came from, not whichever class it is
      # materialized onto.

      module Shared
        @@total = 0
        def add(n)
          @@total += n
        end
        def total
          @@total
        end
      end
      class Left
        include Shared
      end
      class Right
        include Shared
      end
      l = Left.new
      r = Right.new
      l.add(5)
      r.add(7)
      puts l.total
      puts r.total
    RUBY

    _(result).must_answer <<~'OUT'
      12
      12
    OUT
  end

  it "multi assign to ivar and global targets" do
    result = ze0(<<~'RUBY')
      class Thing
        attr_reader :x
        def set_both(g)
          @x, $g2 = 10, g
        end
      end
      t = Thing.new
      t.set_both(99)
      puts t.x
      puts $g2
    RUBY

    _(result).must_answer <<~'OUT'
      10
      99
    OUT
  end

  it "reading the same ivar or captured local twice in one expression does not deadlock" do
    result = ze0(<<~'RUBY')
      # CRITICAL bug, found via the operator-method test above (`@x * @x`
      # inside `Vector#<=>`): the old emitter's `IvarRead` and
      # captured-`LocalRead` lowerings both emitted a bare, UNNAMED
      # `#expr.lock().clone()`. An unnamed lock guard stays alive until the end
      # of the ENCLOSING STATEMENT, so referencing the SAME ivar or captured
      # local TWICE in one expression/statement (a very common shape: squaring,
      # self-comparison, `total - total`, not just the already-audited
      # read-modify-WRITE case) silently deadlocked the whole generated program
      # forever -- no abort, no error, just a permanent hang. Fixed by binding
      # the guard to an explicit named local INSIDE its own block (confirmed
      # empirically that a bare `{ }` wrapper alone does NOT change the release
      # timing -- only a named binding does).

      class Squarer
        def initialize(n)
          @n = n
        end
        def square
          @n * @n
        end
      end
      puts Squarer.new(7).square

      class Once
        def run
          yield
        end
      end
      total = 5
      block_result = 0
      Once.new.run { block_result = total * total }
      puts block_result
    RUBY

    _(result).must_answer <<~'OUT'
      49
      25
    OUT
  end

  it "top level class variable raises" do
    result = ze0(<<~'RUBY')
      # A bare `@@x` outside any class/module body has no owning cref, and ruby
      # 4.0.6 raises `RuntimeError: class variable access from toplevel` for both
      # the write and the read (it was only a warning in older rubies). zeo used
      # to store it on `Object` and read it back; this pins the corrected
      # behaviour, message included.

      begin
        @@plain = 42
      rescue RuntimeError => e
        puts e.message
      end
      begin
        puts @@plain
      rescue RuntimeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      class variable access from toplevel
      class variable access from toplevel
    OUT
  end

  it "unrelated class own cvar is independent storage" do
    result = ze0(<<~'RUBY')
      class Base
        @@count = 0
        def count
          @@count
        end
      end
      class Other
        @@count = 100
        def count
          @@count
        end
      end
      puts Base.new.count
      puts Other.new.count
    RUBY

    _(result).must_answer <<~'OUT'
      0
      100
    OUT
  end
end
