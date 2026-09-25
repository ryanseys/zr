# frozen_string_literal: true

require "spec_helper"

describe "Kernel programs" do
  it "adds no constant of its compiler" do
    result = zr(<<~'RUBY')
      # An eval compiles its string here with a compiler in Ruby, over prism,
      # which the program carries. Its constants, Zr and Prism, stay out of
      # the program's sight, as ruby has neither: not in Object.constants, not
      # for defined?, const_get or a string an eval runs, nor after
      # RubyVM::AbstractSyntaxTree's translator loads.
      eval "1"
      p Object.constants.include?(:Prism), defined?(Prism)
      p Object.constants.include?(:Zr), defined?(Zr)

      p Object.const_defined?(:Prism), (Object.const_get(:Prism) rescue $!.class), Module.constants.include?(:Prism)
      p eval("defined?(Prism)"), eval("1 + 2")
      p RubyVM::AbstractSyntaxTree.parse("1").type, defined?(Prism), defined?(Zr)

    RUBY

    _(result).must_answer <<~'OUT'
      false
      nil
      false
      nil
      false
      NameError
      false
      nil
      3
      :SCOPE
      nil
      nil
    OUT
  end

  it "autoload raises from a const added hook" do
    result = zr(<<~'RUBY')
      # `autoload` declares the constant, so a const_added hook that raises
      # raises out of the autoload, as it does out of an assignment.
      module M
        def self.const_added(name) = raise("added #{name}")
        begin
          autoload :Foo, "foo"
        rescue => e
          p e.message
        end
        p autoload?(:Foo)
        p constants
      end

    RUBY

    _(result).must_answer <<~'OUT'
      "added Foo"
      "foo"
      [:Foo]
    OUT
  end

  it "bare super forwards a child optional into a parent required slot" do
    result = zr(<<~'RUBY')
      # The child's and parent's parameter SHAPES differ, so the forwarding
      # must flatten positionally rather than match bucket-for-bucket.

      class Parent
        def greet(name)
          "Parent(#{name})"
        end
      end
      class Child < Parent
        def greet(name = "default")
          super
        end
      end
      puts Child.new.greet
      puts Child.new.greet("given")
    RUBY

    _(result).must_answer "Parent(default)\nParent(given)\n"
  end

  it "break bubbles through nested begins to the outer loop" do
    result = zr(<<~'RUBY')
      # An inner `begin` (loop labels cleared) `?`-propagates the `break` up to
      # the outer `begin`, which -- inline in the loop -- performs the literal
      # translation. The crossing scan descends THROUGH nested begins (H2).

      i = 0
      while i < 4
        begin
          begin
            break if i == 2
            puts "inner #{i}"
          rescue
          end
        rescue
        end
        i += 1
      end
      puts "out"
    RUBY

    _(result).must_answer <<~'OUT'
      inner 0
      inner 1
      out
    OUT
  end

  it "call site splat on an implicit self sibling call" do
    result = zr(<<~'RUBY')
      class Adder
        def add3(a, b, c)
          a + b + c
        end
        def run(arr)
          add3(*arr)
        end
      end
      puts Adder.new.run([1, 2, 3])
    RUBY

    _(result).must_answer "6\n"
  end

  it "caller locations" do
    result = zr(<<~'RUBY')
      # AOT builds keep no runtime call-stack frames (as with Kernel#caller), so
      # caller_locations is an empty array rather than nil. The array-shaped contract
      # still holds: it is an Array, is iterable, and is nil-safe under &..
      def frames = caller_locations(1, 1)

      puts frames.is_a?(Array)
      puts(frames.length >= 0)

      # iterating / mapping the result must not crash regardless of frame count
      frames.each { |loc| }
      puts frames.map { |loc| 1 }.length >= 0

      # the common guard idiom is nil-safe
      label = caller_locations(1, 1)&.first&.label
      puts label.nil? || label.is_a?(String)

      # arguments are still evaluated for their side effects (as CRuby does before the
      # call), even though the result is an empty array
      def noisy_start
        puts "arg evaluated"
        1
      end
      caller_locations(noisy_start, 1)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      arg evaluated
    OUT
  end

  it "catch anonymous tag" do
    result = zr(<<~'RUBY')
      r = catch do |t|
        p t.class
        throw t, :done
      end
      p r
    RUBY

    _(result).must_answer "Object\n:done\n"
  end

  it "catch throw tags values" do
    result = zr(<<~'RUBY')
      # catch/throw: values delivered across method boundaries, non-symbol object
      # tags matched by identity, the auto-tag block-param form, and UncaughtThrowError.

      # throw value crosses a method boundary
      def thrower; throw :done, [1, 2]; end
      def catcher; catch(:done) { thrower }; end
      p catcher

      # non-array value across methods
      def deep_throw; throw :msg, "carried"; end
      def deep_catch; catch(:msg) { deep_throw; "not reached" }; end
      p deep_catch

      # object tag: matched by identity
      tag = Object.new
      r = catch(tag) { throw tag, 7 }
      p r

      # two distinct object tags: inner throw targets the outer catch
      outer = Object.new
      inner = Object.new
      r2 = catch(outer) do
        catch(inner) do
          throw outer, :skipped_inner
        end
        :not_reached
      end
      p r2

      # auto-generated tag bound to the block param
      def auto; catch { |t| throw t, 42 }; end
      p auto

      # auto-tag without a throw returns the block value
      p(catch { |t| 5 })

      # no throw: catch returns the block's last value
      p(catch(:unused) { "fallthrough" })

      # throw with no value delivers nil
      p(catch(:bare) { throw :bare; :after })

      # uncaught throw raises UncaughtThrowError
      begin
        catch(:here) { throw :elsewhere, 1 }
      rescue UncaughtThrowError => e
        puts e.class
        puts e.message
      end

      # int values still ride the channel
      p(catch(:n) { throw :n, 99 })

      # float value
      p(catch(:f) { throw :f, 2.5 })

      # an Integer TAG matches by identity (Fixnum value equality), not content
      p(catch(42) { throw 42, "int-tag" })
      p(catch(7) { 99 })   # no throw: the block value rides through
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      "carried"
      7
      :skipped_inner
      42
      5
      "fallthrough"
      nil
      UncaughtThrowError
      uncaught throw :elsewhere
      99
      2.5
      "int-tag"
      99
    OUT
  end

  it "catch throw uncaught" do
    result = zr(<<~'RUBY')
      # catch/throw delivers a value across method boundaries; a throw whose tag has
      # no live catch raises UncaughtThrowError (rescuable), rather than leaking.

      def thrower; throw :done, [1, 2]; end
      def catcher; catch(:done) { thrower } end
      p catcher                              # [1, 2]

      # object tag matched by identity; inner throw can target an outer catch
      outer = Object.new
      inner = Object.new
      r = catch(outer) do
        catch(inner) { throw outer, :to_outer }
        :not_reached
      end
      p r                                    # :to_outer

      # no matching catch -> UncaughtThrowError, caught by an ordinary rescue
      begin
        throw :nope, 5
        puts "WRONG"
      rescue UncaughtThrowError => e
        puts e.message                       # uncaught throw :nope
      end

      # a throw to a catch that has already exited is also uncaught
      tag = :gone
      catch(tag) { }
      begin
        throw tag
      rescue UncaughtThrowError => e
        puts "gone: #{e.message}"
      end

      # W3e: array pattern with a trailing comma is an implicit (anonymous) rest
      case [0, 1, 2, 3]
      in [0, 1, ] then puts "at-least matched"
      else puts "no"
      end
      case [5]
      in [0, 1, ] then puts "wrong"
      else puts "too short"
      end

      # W3f: splat into a Proc/lambda receiver
      add3 = ->(a, b, c) { a + b + c }
      args = [1, 2, 3]
      p add3.call(*args)                     # 6
      p add3[*args]                          # 6
      p add3.(*args)                         # 6
      prc = proc { |a, b| a * b }
      p prc.call(*[4, 5])                    # 20
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      :to_outer
      uncaught throw :nope
      gone: uncaught throw :gone
      at-least matched
      too short
      6
      6
      6
      20
    OUT
  end

  it "class body require runs in place" do
    result = zr(<<~'RUBY', files: beside("class_body_require/inner.rb"))
      # A `require` written in a `class`/`module` BODY runs AT ITS OWN POSITION in
      # CRuby, at the top-level cref -- not after the whole enclosing file.
      #
      # So `module M; puts "before"; require_relative "x"; puts "after"; end`
      # prints before, then the output of x, then after. The constants that x
      # defines go to Object, not to M.
      #
      # A required FFI vocabulary is also visible to the statements below the
      # `require` (see the ffi test "module body require declares before the next
      # statement").
      module M
        puts "before"
        require_relative "class_body_require/inner"
        puts "after"
        p INNER_TOP
        p InnerClass.hi
      end

      # The constant went to Object, not to M.
      p M.constants
      p Object.const_defined?(:INNER_TOP)
      p defined?(M::INNER_TOP)

      # A second require of the same file is a no-op, and answers false.
      module N
        p require_relative("class_body_require/inner")
      end
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      before
      inner runs
      after
      1
      "inner-class"
      []
      true
      nil
      false
      done
    OUT
  end

  it "const path unresolved require" do
    result = zr(<<~'RUBY')
      # An unresolved qualified constant (`Mylib::VERSION`, Mylib undefined) raises a
      # rescuable runtime NameError. It is not a compile error. In a real program the
      # constant can come from a `require "mylib/version"`; this program only reads
      # the constant, because the rescuable NameError is what matters here.
      begin
        puts Mylib::VERSION
      rescue NameError => e
        puts "rescued: #{e.message}"
      end
      puts "after"
    RUBY

    _(result).must_answer "rescued: uninitialized constant Mylib\nafter\n"
  end

  it "conversion refusal names nil true and false" do
    result = zr(<<~'RUBY')
      # rb_builtin_class_name: a refusal names nil, true and false by themselves
      # rather than by their classes, and an anonymous class by the path
      # `#<Class:0x...>` rather than by a name it has none of.
      #
      # zr interpolated the class at about 76 sites, so `[1] - nil` said
      # "NilClass" where ruby says "nil", and a value of an anonymous class said
      # nothing at all, because `Class#name` answers nil for one.
      #
      # Both message families follow the rule: "no implicit conversion of X into Y"
      # and "wrong argument type X (expected Y)".

      def refusal
        answer = yield
        "no refusal: #{answer.inspect}"
      rescue StandardError => e
        "#{e.class}: #{e.message}"
      end

      # no implicit conversion, over the three values that name themselves
      puts refusal { [1] - nil }
      puts refusal { [1] - true }
      puts refusal { [1] - false }
      puts refusal { {}.merge(false) }
      puts refusal { "a" + nil }
      puts refusal { "a" * nil }

      # wrong argument type, the same rule
      puts refusal { Module.new.include(nil) }
      puts refusal { Module.new.include(true) }
      puts refusal { Struct.new(:a).new(1).values_at(true) }

      # Kernel's own conversions
      puts refusal { Integer(nil) }
      puts refusal { Integer(false) }
      puts refusal { Float(nil) }
      puts refusal { String(nil).class }

      # An ordinary class still names itself.
      puts refusal { [1] - 3.5 }
      puts refusal { Module.new.include(Object.new.freeze.class.new) }

      # An anonymous class has no name, so the refusal carries its path. The
      # address is the object's own, so only the shape is asserted here.
      anonymous = Class.new.new
      begin
        [1] - anonymous
      rescue TypeError => e
        p e.message.start_with?("no implicit conversion of #<Class:0x")
        p e.message.end_with?("> into Array")
      end
      begin
        Module.new.include(anonymous)
      rescue TypeError => e
        p e.message.start_with?("wrong argument type #<Class:0x")
        p e.message.end_with?("> (expected Module)")
      end

    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: no implicit conversion of nil into Array
      TypeError: no implicit conversion of true into Array
      TypeError: no implicit conversion of false into Array
      TypeError: no implicit conversion of false into Hash
      TypeError: no implicit conversion of nil into String
      TypeError: no implicit conversion from nil to integer
      TypeError: wrong argument type nil (expected Module)
      TypeError: wrong argument type true (expected Module)
      TypeError: no implicit conversion of true into Integer
      TypeError: can't convert nil into Integer
      TypeError: can't convert false into Integer
      TypeError: can't convert nil into Float
      no refusal: String
      TypeError: no implicit conversion of Float into Array
      TypeError: wrong argument type Object (expected Module)
      true
      true
      true
      true
    OUT
  end

  it "equal p boxed argument" do
    result = zr(<<~'RUBY')
      # `equal?` with a boxed argument compares addresses: the same call reached
      # with an object and with a symbol widens the parameter to poly. An object
      # compared with itself gives true.
      Pad = Struct.new(:name)

      class Plain
        def initialize(n)
          @n = n
        end
      end

      def same?(a, b)
        a.equal?(b)
      end

      pad = Pad.new('p1')
      other = Pad.new('p1')
      p same?(pad, pad)
      p same?(pad, other)
      p same?(pad, :sym)
      p same?(pad, 7)
      p same?(pad, nil)

      def same_plain?(a, b)
        a.equal?(b)
      end

      x = Plain.new(1)
      y = Plain.new(1)
      p same_plain?(x, x)
      p same_plain?(x, y)
      p same_plain?(x, 'str')
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      false
      false
      true
      false
      false
    OUT
  end

  it "eval caller locals" do
    result = zr(<<~'RUBY')
      # A bare `eval` runs in the CALLER's frame, so a dynamic source reads and
      # writes the locals around it -- and a local the source introduces stays
      # afterwards. The compiler reaches this by materializing the calling scope as
      # a Binding at the `eval` site, the same machinery `Kernel#binding` uses.
      n = 2
      src = "n * 10"

      puts "-- reading the caller's locals --"
      p eval(src)
      p eval("n + 1", nil)

      puts "-- writing them --"
      eval("n = 40")
      p n

      puts "-- inside a method, with parameters --"
      def scaled(factor, code)
        base = 3
        eval(code)
      end
      p scaled(4, "base * factor")

      puts "-- inside a block --"
      [5].each do |item|
        total = 1
        p eval("item + total")
      end

      puts "-- self, ivars and lexical constants come along --"
      class Widget
        SIDES = 4
        def initialize
          @label = "w"
        end

        def describe(code)
          eval(code)
        end
      end
      w = Widget.new
      p w.describe("[@label, SIDES, self.class]")

      puts "-- reached reflectively, through send --"
      p send(:eval, "n * 3")
      p __send__(:eval, "n * 4")
      class Tallied
        def initialize = @total = 6
      end
      t = Tallied.new
      p t.send(:eval, "self.class")
      p t.send(:eval, "@total")
      p t.send(:eval, "@total + n")

      puts "-- a local the source introduces is the eval's own --"
      p eval("introduced = 9; introduced * 2")
      p eval("defined?(introduced)")
      p defined?(introduced)
    RUBY

    _(result).must_answer <<~'OUT'
      -- reading the caller's locals --
      20
      3
      -- writing them --
      40
      -- inside a method, with parameters --
      12
      -- inside a block --
      6
      -- self, ivars and lexical constants come along --
      ["w", 4, Widget]
      -- reached reflectively, through send --
      120
      160
      Tallied
      6
      46
      -- a local the source introduces is the eval's own --
      18
      nil
      nil
    OUT
  end

  it "eval while loop in the vm" do
    result = zr(<<~'RUBY')
      src = "s = 0; i = 1; while i <= 4; s = s + i; i = i + 1; end; s"; puts eval(src)
    RUBY

    _(result).must_answer "10\n"
  end

  it "for loops over hashes and parenthesized collections" do
    result = zr(<<~'RUBY')
      total = 0
      for k, v in { "a" => 1, "b" => 2, "c" => 3 }
        total += v
        puts "#{k}:#{v}"
      end
      p total
      for pair in { x: 10, y: 20 }
        p pair
      end
      for k, v in {}
        puts "unreachable"
      end
      sum = 0
      for i in (1..3)
        sum += i
      end
      p sum
      for e in ([9, 8])
        p e
      end
      for last in [7, 8, 9]
      end
      p last
    RUBY

    _(result).must_answer <<~'OUT'
      a:1
      b:2
      c:3
      6
      [:x, 10]
      [:y, 20]
      6
      9
      8
      9
    OUT
  end

  it "implicit alloc site escape layout" do
    result = zr(<<~'RUBY')
      RowA = Struct.new(:id, :name)
      RowB = Struct.new(:id, :label)

      class Store
        def initialize
          @records = []
        end

        def add(record)
          @records << record
          record
        end

        def first
          @records[0]
        end
      end

      def first_record(store)
        store.first
      end

      left = Store.new
      right = Store.new

      left.add(RowA.new(1, "alpha"))
      right.add(RowB.new(2, "beta"))

      puts first_record(left).name
      puts first_record(right).label
    RUBY

    _(result).must_answer "alpha\nbeta\n"
  end

  it "implicit alloc site escape param" do
    result = zr(<<~'RUBY')
      class Store
        def initialize
          @records = []
        end

        def add(record)
          @records << record
          record
        end

        def count
          @records.length
        end
      end

      def use(store)
        store.add(1)
        store.count
      end

      left = Store.new
      right = Store.new
      left.add(10)
      right.add(20)

      puts use(left)
      puts use(right)
    RUBY

    _(result).must_answer "2\n2\n"
  end

  it "implicit alloc site escape scoped locals" do
    result = zr(<<~'RUBY')
      class Store
        def initialize
          @records = []
        end

        def add(record)
          @records << record
          record
        end

        def count
          @records.length
        end
      end

      class Other
        def initialize
          @records = []
        end
      end

      def make_store
        item = Store.new
        item.add(1)
        item
      end

      def make_other
        item = Other.new
        item
      end

      def use(store)
        store.add(1)
        store.count
      end

      left = make_store
      right = Store.new
      make_other
      right.add(2)

      puts use(left)
      puts use(right)
    RUBY

    _(result).must_answer "2\n2\n"
  end

  it "implicit alloc site holder shared method" do
    result = zr(<<~'RUBY')
      RowA = Struct.new(:id, :name)
      RowB = Struct.new(:id, :label)

      class Holder
        def initialize(record)
          @record = record
        end

        def record
          @record
        end
      end

      def unwrap(holder)
        holder.record
      end

      holder_a = Holder.new(RowA.new(1, "alpha"))
      holder_b = Holder.new(RowB.new(2, "beta"))

      puts unwrap(holder_a).name
      puts unwrap(holder_b).label
      puts unwrap(holder_a).id + unwrap(holder_b).id
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      beta
      3
    OUT
  end

  it "implicit new local method scope" do
    result = zr(<<~'RUBY')
      # Implicit-new local class resolution must be method-scoped. A local's
      # type can never come from a same-named local in a *different* method.
      #
      # `accept_loop` binds `conn` to a Fiber and forwards it into
      # Sched.spawn -> Slot.new (a Fiber-typed constructor). A sibling method
      # `handle` binds a same-named `conn` to a Probe -- a class that gets an
      # implicit-new specialization (>= 2 zero-arg `.new` sites whose
      # initialize seeds an empty-array ivar). With a name-keyed (un-scoped)
      # implicit-new-local lookup, accept_loop's Fiber `conn` leaked to the
      # Probe type, mis-widening Sched.spawn's `f` param and (at full program
      # scale) breaking the generated C. Authoritative repro: OriPekelman/tep
      # (Tep::Scheduler.spawn_fiber). This is path coverage, not a
      # fails-without-fix minimal repro -- the build break needs a
      # fixpoint-ordering asymmetry that does not survive shrinking.
      class Slot
        def initialize(f)
          @f = f
        end
        def run
          @f.resume
        end
      end

      class Probe
        def initialize
          @items = []
        end
        def go
          @items.length
        end
      end

      class Sched
        def self.spawn(f)
          s = Slot.new(f)
          s.run
        end
      end

      def run_worker
        f = Fiber.new { 10 }
        Sched.spawn(f)
      end

      def accept_loop
        conn = Fiber.new { 20 }
        Sched.spawn(conn)
      end

      def handle
        conn = Probe.new
        conn.go
      end

      def warmup
        q = Probe.new
        q.go
      end

      a = run_worker
      b = accept_loop
      handle
      warmup
      puts a
      puts b
    RUBY

    _(result).must_answer "10\n20\n"
  end

  it "implicit self call dispatches to a sibling method" do
    result = zr(<<~'RUBY')
      class Greeter
        def greet
          hello
        end

        def hello
          "hi from hello"
        end
      end

      puts Greeter.new.greet
    RUBY

    _(result).must_answer "hi from hello\n"
  end

  it "implicit self call in a class method resolves against the receiver" do
    result = zr(<<~'RUBY')
      # `self` in a class method is the class it was CALLED on, not the one
      # whose body the method was written in. Both of these were silently wrong
      # (no error, just the wrong object) while implicit-self resolution used
      # the lexical `defining_class`:
      # - `Sub.create` built a Base;
      # - `Ext.helped` answered "Helper".

      class Base
        def self.create; new; end
        def self.who; name; end
      end
      class Sub < Base; end
      p Base.create.class
      p Sub.create.class
      p Sub.who

      module Helper
        def helped; "helped-#{name}"; end
      end
      class Ext
        extend Helper
      end
      p Ext.helped
    RUBY

    _(result).must_answer <<~'OUT'
      Base
      Sub
      "Sub"
      "helped-Ext"
    OUT
  end

  it "implicit self call with args can mutate an ivar" do
    result = zr(<<~'RUBY')
      class Counter
        def initialize
          @count = 0
        end

        def bump(n)
          add(n)
          @count
        end

        def add(n)
          @count = @count + n
        end
      end

      c = Counter.new
      puts c.bump(5)
      puts c.bump(2)
    RUBY

    _(result).must_answer "5\n7\n"
  end

  it "OpenStruct without its require raises NameError rather than failing to compile" do
    result = zr(<<~'RUBY')
      # OpenStruct without `require "ostruct"` must raise a clean NameError (the same
      # path as any undefined constant), not fail C compilation. The general shape --
      # an unresolved call in `p`'s argument position -- must compile to its diverging
      # NoMethodError/NameError raise. Rescue so the output is deterministic.
      begin
        o = OpenStruct.new(a: 1)
        p o.a
      rescue NameError => e
        puts "NameError: #{e.message}"
      end

      begin
        x = [1, "s"].first
        p x.no_such_method
      rescue NoMethodError
        puts "NoMethodError caught"
      end
      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      NameError: uninitialized constant OpenStruct
      NoMethodError caught
      ok
    OUT
  end

  it "a Binding names the whole frame, so writes flow both ways and a local declared later is already in it" do
    result = zr(<<~'RUBY')
      # `Kernel#binding` at the top level: the Binding shares the frame's slots, so
      # every write is visible through both sides -- and a local declared LATER in
      # the scope is already in it, because a Binding names the whole frame rather
      # than a snapshot of it.
      x = 100
      b = binding

      puts "-- identity --"
      p b.class
      p b.frozen?
      p b.receiver.equal?(self)
      p b.inspect.start_with?("#<Binding:0x")
      p b.to_s == b.inspect
      p b.source_location.first.end_with?("kernel_test.rb")
      p b.source_location.last

      puts "-- the frame's own locals --"
      p b.local_variables
      p b.local_variable_get(:x)
      p b.local_variable_defined?(:x)
      p b.local_variable_defined?(:nope)

      puts "-- writes flow both ways --"
      b.local_variable_set(:x, 5)
      p x
      x = 7
      p b.local_variable_get(:x)
      b.eval("x = 42")
      p x
      p b.eval("x + 1")

      puts "-- a name the frame has no slot for is the Binding's own --"
      b.local_variable_set(:added, 7)
      p b.local_variable_get(:added)
      b.eval("evaled = 3")
      p b.local_variables
      p defined?(added)

      puts "-- errors --"
      begin
        b.local_variable_get(:nope)
      rescue NameError => e
        p [e.class, e.message.sub(/0x\h+/, "0xADDR")]
      end
      begin
        b.local_variable_get(1)
      rescue TypeError => e
        p [e.class, e.message]
      end
      begin
        Binding.new
      rescue NoMethodError => e
        p [e.class, e.message]
      end

      puts "-- declared after the capture --"
      later = 9
      p b.local_variable_get(:later)
    RUBY

    _(result).must_answer <<~'OUT'
      -- identity --
      Binding
      false
      true
      true
      true
      true
      6
      -- the frame's own locals --
      [:x, :b, :e, :later]
      100
      true
      false
      -- writes flow both ways --
      5
      7
      42
      43
      -- a name the frame has no slot for is the Binding's own --
      7
      [:evaled, :added, :x, :b, :e, :later]
      nil
      -- errors --
      [NameError, "local variable 'nope' is not defined for #<Binding:0xADDR>"]
      [TypeError, "1 is not a symbol nor a string"]
      [NoMethodError, "undefined method 'new' for class Binding"]
      -- declared after the capture --
      9
    OUT
  end

  it "caller answers an empty Array, and the private conversion helpers resolve through every dispatch path" do
    result = zr(<<~'RUBY')
      # `caller`/`caller_locations` answer an empty Array (no runtime frames in an
      # AOT build), and the private Kernel conversion/format helpers resolve as
      # real methods -- so a splat call, `method(:Integer)`, or a forwarded block
      # reach them, not only the codegen fast-path. Byte-verified against ruby 4.0.6.

      def frames; caller; end
      p frames.is_a?(Array)
      p caller_locations(1, 1).is_a?(Array)
      args = ["%d-%s", 3, "x"]
      puts format(*args)
      p [1, 2, 3].map(&method(:Integer))
      p ["1", "0xff"].map(&method(:Integer))
      def wrap(&b); proc(&b); end
      p wrap { |x| x + 100 }.call(1)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      3-x
      [1, 2, 3]
      [1, 255]
      101
    OUT
  end

  it "Hash(), warn, printf, putc and p answer in value position what ruby answers" do
    result = zr(<<~'RUBY')
      # Kernel#Hash / #warn / #printf / #putc / p() value position
      p(Hash(nil))
      p(Hash([]))
      p(Hash({a: 1}))
      begin; Hash([1, 2]); rescue => e; p e.class; end
      w = warn("to stderr")
      p(w)
      f = printf("%d-%s\n", 7, "x")
      p(f)
      y = p()
      p(y)
      z = putc(65); puts
      p(z)
    RUBY

    _(result).must_answer <<~'OUT', stderr: "to stderr\n"
      {}
      {}
      {a: 1}
      TypeError
      nil
      7-x
      nil
      nil
      A
      65
    OUT
  end

  it "a proc calls, warn writes to stderr, __method__ names the method, and a bare new builds the class" do
    result = zr(<<~'RUBY')
      sq = proc { |x| x * x }
      puts sq.call(5)
      warn "to stderr"
      def who = __method__
      p who
      GC.start
      class F
        def self.create
          new
        end
      end
      puts F.create.class
    RUBY

    _(result).must_answer <<~'OUT', stderr: "to stderr\n"
      25
      :who
      F
    OUT
  end

  it "a def written inside module Kernel reaches every class and is emitted once" do
    result = zr(<<~'RUBY')
      # A `def` written inside `module Kernel` reaches every class in the program,
      # and zr emits its body ONCE. This is the same rule as a top-level `def`
      # (see `a_toplevel_def_is_one_body_for_every_class`), reached by the other
      # spelling -- and the spelling mattered: the spine lookup asks a map that
      # was filled from TOP-LEVEL defs only, so a
      # `def` inside `module Kernel` was never in it and every builtin carrier
      # took a private copy. `Kernel#URI` cost 85 of them on a program that only
      # requires uri.
      #
      # The carriers here are deliberately of every kind: a user class, an
      # immediate, a builtin with a payload, and an exception.

      module Kernel
        def tagged(x) = "#{self.class}:#{x}"
        def reads_toplevel = TOP

        private

        def hushed = "quiet"
      end

      TOP = "top-level"

      class Widget; end

      w = Widget.new
      p [w.tagged(1), 5.tagged(2), "s".tagged(3), [1].tagged(4), :sym.tagged(5), nil.tagged(6)]
      p [w.reads_toplevel, 5.reads_toplevel]

      begin
        raise ArgumentError, "boom"
      rescue => e
        p [e.tagged(7), e.reads_toplevel]
      end

      # `Kernel`'s `private` reaches every carrier, and none of them answers
      # `respond_to?`.
      p [w.respond_to?(:hushed), 5.respond_to?(:hushed), "s".respond_to?(:hushed)]
      p [w.send(:hushed), 5.send(:hushed)]

      # Every carrier really does reach it through Kernel.
      p [Widget.include?(Kernel), Integer.include?(Kernel), String.include?(Kernel)]
      p [w.is_a?(Kernel), 5.is_a?(Kernel)]
      # `Method#owner` answers the CARRIER here, not Kernel -- a separate,
      # pre-existing divergence with its own gap file
      # (`a_kernel_reopen_reports_its_owner`), deliberately not printed.
    RUBY

    _(result).must_answer <<~'OUT'
      ["Widget:1", "Integer:2", "String:3", "Array:4", "Symbol:5", "NilClass:6"]
      ["top-level", "top-level"]
      ["ArgumentError:7", "top-level"]
      [false, false, false]
      ["quiet", "quiet"]
      [true, true, true]
      [true, true]
    OUT
  end

  it "a method added by reopening Kernel reports Kernel as its owner, from every carrier" do
    result = zr(<<~'RUBY')
      module Kernel
        def tagged(x) = x
      end

      class Widget; end

      p Widget.new.method(:tagged).owner
      p 5.method(:tagged).owner
      p "s".method(:tagged).owner
      p Widget.instance_method(:tagged).owner
      p Integer.instance_method(:tagged).owner

      p [Widget.include?(Kernel), Integer.include?(Kernel), Widget.new.is_a?(Kernel)]
      p Kernel.instance_method(:tagged).owner
    RUBY

    _(result).must_answer <<~'OUT'
      Kernel
      Kernel
      Kernel
      Kernel
      Kernel
      [true, true, true]
      Kernel
    OUT
  end

  it "__callee__ and __method__ agree without an alias, and a private or missing call names the class" do
    result = zr(<<~'RUBY')
      # __callee__ / __method__ (identical without aliases)
      def who
        [__method__, __callee__]
      end
      p who

      # putc: Integer writes the low byte, String writes the first character;
      # both return their argument.
      putc 72
      putc 105
      putc "!"
      putc "\n"
      p putc(321).class   # 321 & 0xff = 65 -> "A"
      puts
      p putc("BC")        # writes "B", returns "BC"
      puts

      # public_method binds public methods, refuses private ones
      class Widget
        def render = "drawn"
        private
        def secret = 42
      end
      w = Widget.new
      p w.public_method(:render).call
      begin
        w.public_method(:secret)
      rescue NameError => e
        puts e.message
      end
      begin
        w.public_method(:missing)
      rescue NameError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:who, :who]
      Hi!
      AInteger

      B"BC"

      "drawn"
      method 'secret' for class 'Widget' is private
      undefined method 'missing' for class 'Widget'
    OUT
  end

  it "lambda requires a literal block" do
    result = zr(<<~'RUBY')
      # `Kernel#lambda` accepts a block WRITTEN AT THE SITE THAT INVOKES IT and
      # refuses one that arrives any other way.
      #
      # The rule is a run-time property of the BLOCK HANDLER, not of the block, the
      # receiver, or the method name. CRuby's frame carries either an iseq block
      # handler (a literal `{ }` at this very call) or a proc handler (a `&expr`, a
      # forwarded `&blk` parameter, a `Method#call`), and `rb_block_lambda` refuses
      # the second kind. Nothing about the VALUE distinguishes them: the proc a
      # refused `lambda(&pr)` hands over was itself built from a literal block.
      #
      # So the mark rides on the HANDLE. `ProcData::literal_block` is set for every
      # proc the emitter builds -- each one came from a block written in the source
      # -- and cleared where a handle turns into CRuby's proc handler: the `&expr`
      # conversion (`zr_rt_block_arg_to_proc`), `public_send`, and `Method#call`.
      # `send` forwards the iseq handler unchanged, which is the CRuby wart that
      # makes it and `public_send` disagree about the same block.
      #
      # The compile-time half could not have answered it. `Kernel.send(m) { 1 }`
      # with a computed `m` is accepted, and so is `"x".send(:lambda) { 1 }` --
      # `lambda` is a private instance method of Kernel, so any receiver reaches it.
      #
      # `a_lambda_takes_a_literal_block_or_a_lambda.rb` carries the widened sweep,
      # including the third outcome this file does not reach: a proc handler that
      # is ALREADY a lambda comes back unchanged.

      def try(label)
        p [label, yield]
      rescue ArgumentError => e
        p [label, :raised, e.message]
      end

      pr = proc { |a| a }
      def wrapper(&b) = lambda(&b)

      # Accepted by CRuby: the block is literal at the site that invokes `lambda`.
      try(:bare)          { lambda { 1 }.lambda? }
      try(:kernel_recv)   { Kernel.lambda { 1 }.lambda? }
      try(:send_sym)      { Kernel.send(:lambda) { 1 }.lambda? }
      try(:computed_send) { m = :lambda; Kernel.send(m) { 1 }.lambda? }
      try(:any_receiver)  { "x".send(:lambda) { 1 }.lambda? }

      # Refused by CRuby: the block arrives as a proc handler.
      try(:forwarded)     { lambda(&pr).lambda? }
      try(:wrapper)       { wrapper { 1 }.lambda? }
      try(:method_object) { Kernel.method(:lambda).call { 1 }.lambda? }
      try(:public_send)   { Kernel.public_send(:lambda) { 1 }.lambda? }
    RUBY

    _(result).must_answer <<~'OUT'
      [:bare, true]
      [:kernel_recv, true]
      [:send_sym, true]
      [:computed_send, true]
      [:any_receiver, true]
      [:forwarded, :raised, "the lambda method requires a literal block"]
      [:wrapper, :raised, "the lambda method requires a literal block"]
      [:method_object, :raised, "the lambda method requires a literal block"]
      [:public_send, :raised, "the lambda method requires a literal block"]
    OUT
  end

  it "loop swallows stop iteration and returns its result" do
    result = zr(<<~'RUBY')
      # `loop`'s full StopIteration contract (CRuby kernel.rb:151): a manual
      # `raise StopIteration` returns nil (no result set), `break value` still
      # carries its value out, and every OTHER exception propagates.

      p(loop { raise StopIteration })
      p(loop { break 42 })
      begin
        loop { raise ArgumentError, "boom" }
      rescue ArgumentError => e
        puts "arg: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      42
      arg: boom
    OUT
  end

  it "nested catch" do
    result = zr(<<~'RUBY')
      # A catch whose body's value is another catch: the inner one's setup was
      # appended in the middle of the outer's assignment, so the C did not compile.
      p(catch(:outer) { catch(:inner) { 1 } })
      p(catch(:a) { catch(:b) { throw :b, 5 } })
      p(catch(:a) { catch(:b) { throw :a, 9 } })
      p(catch(:x) { 3 })
    RUBY

    _(result).must_answer <<~'OUT'
      1
      5
      9
      3
    OUT
  end

  it "p as expression" do
    result = zr(<<~'RUBY')
      # Kernel#p returns its argument, so it composes as an expression:
      # x = p(y), puts p(y), f(p(y)). Statement-position p is unchanged.
      x = p(42)
      puts x
      puts p("s")
      def f(v) = v * 2
      puts f(p(5))
      y = p([1, 2])
      puts y.length
      h = p({ a: 1 })
      puts h[:a]
      z = p(3.5)
      puts z + 0.5
      p 7
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      "s"
      s
      5
      10
      [1, 2]
      2
      {a: 1}
      1
      3.5
      4.0
      7
    OUT
  end

  it "pattern implicit rest" do
    result = zr(<<~'RUBY')
      # A trailing comma in an array pattern (`in [0, 1, ]`) is an implicit rest:
      # at-least length semantics, binding nothing.
      case [0, 1, 2, 3]
      in [0, 1, ] then puts "matched"
      else puts "no"
      end
      case [5]
      in [0, 1, ] then puts "wrong"
      else puts "no2"
      end
    RUBY

    _(result).must_answer "matched\nno2\n"
  end

  it "poly empty p user length" do
    result = zr(<<~'RUBY')
      # Asking whether a user class owns the CALLED name: a class that defines
      # `length` does not change `empty?` on an Array or a String. The receiver
      # at run time decides the answer.
      class Sized
        def length
          0
        end
      end

      class Baggy
        def empty?
          true
        end
      end

      opts = { n: 1, list: [2], s: 'ab', e: [] }
      p opts[:list].empty?
      p opts[:e].empty?
      p opts[:s].empty?
      p [2].empty?

      # a user class that owns the name wins
      things = [Baggy.new, [1]]
      p things.first.empty?

      # and a user object with no #empty? raises rather than answering true
      sized = [Sized.new, 1]
      begin
        p sized.first.empty?
      rescue NoMethodError => e
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      false
      true
      NoMethodError
    OUT
  end

  it "private method callable via implicit self and explicit self dot" do
    result = zr(<<~'RUBY')
      # Real Ruby (2.7+): a private method IS callable with an explicit
      # receiver as long as it's a literal `self` -- not just implicit-self
      # (no receiver at all).

      class Box
        def run
          self.helper + implicit_helper
        end

        private

        def helper
          10
        end

        def implicit_helper
          helper
        end
      end

      puts Box.new.run
    RUBY

    _(result).must_answer "20\n"
  end

  it "proc compose requires a callable" do
    result = zr(<<~'RUBY')
      # `Proc#>>`/`#<<` type-check their operand AT COMPOSE TIME ("callable
      # object is expected"); zr builds the composite and would only fail when
      # called. (Found by the 2026-08-24 probe sweep.)
      begin
        p(->(x) { x } >> 5)
      rescue TypeError => e
        puts e.message
      end
      begin
        p(->(x) { x } << "s")
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer "callable object is expected\ncallable object is expected\n"
  end

  it "proc to proc self" do
    result = zr(<<~'RUBY')
      p(->(x) { x }.to_proc.call(3))
      l001 = ->(x) { x }; p l001.to_proc.call(3)
      p l001.to_proc.arity
      p l001.to_proc.lambda?
      pr = proc { |x| x * 2 }
      p pr.to_proc.call(4)
      p [1,2].map(&l001.to_proc)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      1
      true
      8
      [1, 2]
    OUT
  end

  it "program that requires prism after an eval sees it" do
    result = zr(<<~'RUBY')
      # The prism an eval compiles with is the one a program requires: the
      # require answers true once, and Prism then stands in Object as ruby
      # stands it, while the compiler goes on working.
      eval "1"
      p defined?(Prism)
      p require("prism"), require("prism")
      p defined?(Prism), Object.constants.include?(:Prism), Prism.parse("1 + 2").value.class
      p eval("[defined?(Prism), 4]")
      p defined?(Zr)

    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      false
      "constant"
      true
      Prism::ProgramNode
      ["constant", 4]
      nil
    OUT
  end

  it "public def hides a private kernel name" do
    result = zr(<<~'RUBY')
      # One name resolves to ONE definition, so the class that defines it decides
      # which reflection list it lands in. `private_methods` walked the whole chain
      # and let Kernel's private `exec` back onto the list under a class that had
      # just defined a PUBLIC `exec` -- the name went unclaimed whenever the filter
      # rejected it, so the next ancestor took it.
      #
      # thor asks exactly this before it runs a command (`instance.private_methods &
      # [name]`), so `bundle exec` answered `Could not find command "exec"` for a
      # command bundler defines in the ordinary way.

      class Runner
        def exec(*args) = [:mine, *args]
        def load(f) = [:loaded, f]
      end

      r = Runner.new
      p r.private_methods.include?(:exec)
      p r.public_methods.include?(:exec)
      p r.private_methods.include?(:load)
      p r.public_methods.include?(:load)
      p Runner.private_instance_methods.include?(:exec)
      p Runner.public_instance_methods.include?(:exec)
      p r.exec(1)

      # A class that does NOT redefine one keeps Kernel's own visibility.
      class Bare; end
      p Bare.new.private_methods.include?(:exec)
      p Bare.new.public_methods.include?(:exec)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      false
      true
      [:mine, 1]
      true
      false
    OUT
  end

  it "puts and p through a replaced stdout" do
    result = zr(<<~'RUBY')
      # puts, print and p reach whatever $stdout is: an object with only
      # write, a StringIO, and a pipe with sync off; and puts of a String
      # subclass, a symbol and an object with to_s take the line walk.
      require "stringio"
      class Sink
        attr_reader :got
        def initialize = @got = []
        def write(*parts) = (@got.concat(parts.map(&:to_s)); parts.sum { |x| x.to_s.bytesize })
      end
      old = $stdout
      sink = $stdout = Sink.new
      puts "a"
      puts "b\n"
      print "c", "d"
      p 1, :two
      puts [3, [4, nil]], nil
      $stdout = old
      p sink.got
      $stdout = StringIO.new
      puts "into a string"
      puts "twice".dup << "!"
      text = $stdout.string
      $stdout = old
      p text
      class Line < String; end
      class Thing
        def to_s = "thing"
      end
      puts Line.new("line"), :sym, Thing.new, 1.5, nil
      r, w = IO.pipe
      w.sync = false
      w.puts "pipe"
      w.print "no newline"
      w.close
      p r.read
      $stdout.puts
      STDOUT.print "x\n"
      $stderr.puts "err"

    RUBY

    _(result).must_answer <<~'OUT', stderr: "err\n"
      ["a", "\n", "b\n", "c", "d", "1", "\n", ":two", "\n", "3", "\n", "4", "\n", "\n", "\n"]
      "into a string\ntwice!\n"
      line
      sym
      thing
      1.5

      "pipe\nno newline"

      x
    OUT
  end

  it "rand prng stream" do
    result = zr(<<~'RUBY')
      # The PRNG contract: same seed -> same stream, for every consumer of the
      # Kernel-level stream (rand in all its forms, shuffle, sample, the Random
      # default instance). The values can differ from CRuby's MT19937 values,
      # so the test checks only the invariants.

      srand(42); a = rand(100)
      srand(42); b = rand(100)
      p a == b
      p a >= 0 && a < 100

      srand(42); f1 = rand
      srand(42); f2 = rand
      p f1 == f2
      p f1 >= 0.0 && f1 < 1.0
      p rand(0).is_a?(Float)

      # a dynamic (non-literal) bound goes through the boxed emission
      n = 50
      srand(9); d1 = rand(n)
      srand(9); d2 = rand(n)
      p d1 == d2
      p d1.is_a?(Integer)

      # ranges draw from the same stream, so srand governs them too
      srand(3); r1 = rand(1..1000)
      srand(3); r2 = rand(1..1000)
      p r1 == r2
      p r1 >= 1 && r1 <= 1000
      srand(3); fr1 = rand(1.5..2.5)
      srand(3); fr2 = rand(1.5..2.5)
      p fr1 == fr2
      p fr1 >= 1.5 && fr1 < 2.5

      # shuffle/sample across the typed-array variants share the stream as well
      ints = (1..16).to_a
      srand(7); s1 = ints.shuffle
      srand(7); s2 = ints.shuffle
      p s1 == s2
      p s1.sort == ints
      strs = %w[a b c d e f g h]
      srand(7); t1 = strs.shuffle
      srand(7); t2 = strs.shuffle
      p t1 == t2
      mixed = [1, "x", :y, 2.5, nil, true, 7, "z"]
      srand(11); m1 = mixed.shuffle
      srand(11); m2 = mixed.shuffle
      p m1 == m2
      srand(13); v1 = ints.sample
      srand(13); v2 = ints.sample
      p v1 == v2

      # srand returns the PREVIOUS seed
      srand(5)
      p srand(9)
      p srand

      # per-instance Random streams are independent and reproducible
      p Random.new(42).rand(1000) == Random.new(42).rand(1000)
      p Random.new(42).rand(1000) != Random.new(43).rand(1000)
      r = Random.new(42)
      p r.seed
      p Random.new(42).bytes(8) == Random.new(42).bytes(8)
      p Random.new(42).bytes(8).length
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
      true
      true
      true
      true
      true
      true
      5
      9
      true
      true
      42
      true
      8
    OUT
  end

  it "random methods" do
    result = zr(<<~'RUBY')
      # Random / Kernel#rand semantics
      srand(5)
      p(srand(10))                 # returns previous seed (5)
      p(rand(0).class)             # rand(0) -> Float
      p(rand(-3).class)            # rand(neg) -> Integer
      p(rand(-3) >= 0 && rand(-3) < 3)
      p(rand(5...5))               # empty range -> nil
      p(rand(5..3))                # reversed range -> nil
      r = Random.new(42)
      p(r.rand(1.0..2.0).class)    # Float range -> Float
      p(r.seed)                    # 42
      p(Random.new_seed.class)     # Integer
      p(r.class)                   # Random
      p(r == r)                    # true
      p(r.equal?(r))               # true
      p(Random.new(1) == Random.new(1))  # distinct objects -> false
      Random.srand(7)
      p(rand(100).class)           # Integer
      p(Random.urandom(8).bytesize) # 8 bytes. NOT .length: the random bytes can
                                    # make multi-byte UTF-8 chars, so .length
                                    # can be less than 8
      p(Random.urandom(8).class)
      begin; rand(1..); rescue => e; p e.class; end   # Errno::EDOM
      begin; rand(..5); rescue => e; p e.class; end
    RUBY

    _(result).must_answer <<~'OUT'
      5
      Float
      Integer
      true
      nil
      nil
      Float
      42
      Integer
      Random
      true
      true
      true
      Integer
      8
      String
      Errno::EDOM
      Errno::EDOM
    OUT
  end

  it "random prng" do
    result = zr(<<~'RUBY')
      # `Random` -- a seedable PRNG. zr's generator is xorshift64*, not CRuby's
      # MT19937, so raw sequences differ; this example prints only the DETERMINISTIC
      # guarantees that hold for any correct PRNG (reproducibility, ranges, return
      # types), never a raw random value.

      # Same seed -> same sequence; different seeds -> (almost surely) different.
      p(Random.new(42).rand(1000) == Random.new(42).rand(1000))
      p(Random.new(1).rand(1000) != Random.new(2).rand(1000))

      # Return types follow the bound: Integer bound -> Integer, Float bound ->
      # Float, no bound -> a Float in [0, 1).
      p Random.new(5).rand(10).class
      p Random.new(5).rand(2.5).class
      p Random.new(5).rand.class

      # Ranges are respected.
      p((r = Random.new(9).rand(6)) >= 0 && r < 6)
      p(Random.new(9).rand < 1.0)
      p((v = Random.new(3).rand(5..9)) >= 5 && v <= 9)

      # `bytes` returns exactly n bytes.
      p Random.new(1).bytes(8).bytesize

      # `seed` reports the integer seed it was built with (a Float is truncated).
      p Random.new(123).seed
      p Random.new(3.9).seed

      # A non-positive bound is an ArgumentError, not a silent 0.
      begin; Random.new(1).rand(0); rescue ArgumentError => e; puts e.message; end
      begin; Random.new(1).rand(-3); rescue ArgumentError => e; puts e.message; end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      Integer
      Float
      Float
      true
      true
      true
      8
      123
      3
      invalid argument - 0
      invalid argument - -3
    OUT
  end

  it "random rand argument" do
    result = zr(<<~'RUBY')
      # Random#rand validates its bound and preserves a Float bound's return type. A
      # non-positive bound (Integer or Float) silently returned 0; MRI raises
      # ArgumentError "invalid argument - <n>". A Float bound was truncated to an
      # integer bound and dispatched to the integer path, losing the Float return.
      def ri(x); Random.new(5).rand(x); end
      begin; ri(0); rescue ArgumentError => e; puts e.message; end       # invalid argument - 0
      begin; ri(-12); rescue ArgumentError => e; puts e.message; end     # invalid argument - -12

      def rf(x); Random.new(5).rand(x); end
      begin; rf(-1.5); rescue ArgumentError => e; puts e.message; end    # invalid argument - -1.5

      # A Float bound returns a Float in [0, bound); an Integer bound returns an Integer.
      def clsf(x); Random.new(5).rand(x).class; end
      p clsf(20.43)                       # Float
      def clsi(x); Random.new(5).rand(x).class; end
      p clsi(5)                           # Integer

      def inrange(x); v = Random.new(5).rand(x); v >= 0.0 && v < 20.43; end
      p inrange(20.43)                    # true
      def ltbound(x); Random.new(5).rand(x) < 10; end
      p ltbound(10)                       # true
    RUBY

    _(result).must_answer <<~'OUT'
      invalid argument - 0
      invalid argument - -12
      invalid argument - -1.5
      Float
      Integer
      true
      true
    OUT
  end

  it "random rejects non positive bounds" do
    result = zr(<<~'RUBY')
      begin; Random.new(1).rand(0); rescue ArgumentError => e; puts e.message; end
      begin; Random.new(1).rand(-3); rescue ArgumentError => e; puts e.message; end
    RUBY

    _(result).must_answer "invalid argument - 0\ninvalid argument - -3\n"
  end

  it "random seeded sequence" do
    result = zr(<<~'RUBY')
      # A seed only means anything if it replays somebody else's numbers: a test
      # fixture, a shuffled deck rebuilt from a log, a property-test seed pasted out
      # of a failure report. So `Random.new(42)` here draws ruby's own MT19937
      # sequence, read through ruby's own three draws -- masked rejection for an
      # integer bound, a 53-bit pair for a Float, and a `[0, 1]` variant for an
      # INCLUSIVE range, which is what lets such a range reach its own endpoint.

      r = Random.new(42)
      p r.rand(100)
      p r.rand(100)
      p r.rand
      p Random.new(42).rand(1000000)

      # --- every seed shape reaches the same generator -----------------------------
      [0, 1, 7, 12345, 2**31, 2**32, 2**32 + 1, 2**64 + 7, 2**128, -99, 3.9].each do |s|
        p [s, Random.new(s).rand(1000)]
      end

      # --- bounds ------------------------------------------------------------------
      r = Random.new(5)
      p r.rand(1)
      p r.rand(2)
      p r.rand(2.5)
      p r.rand(2..9)
      p r.rand(2...9)
      p r.rand(1.0..2.0)
      p r.rand(1.0...2.0)
      p Random.new(5).rand(2**80)
      p Random.new(5).rand(10**30)
      p Random.new(5).bytes(16).unpack1("H*")

      # --- the process-wide generator, which `srand` reseeds -----------------------
      srand(1234)
      p rand(100)
      p rand(100)
      p rand
      p rand(1..6)
      p 10.times.map { rand(6) + 1 }
      p srand(99).class
      p rand(100)

      # --- shuffle and sample draw from the same stream ----------------------------
      p [1, 2, 3, 4, 5].shuffle(random: Random.new(42))
      p (1..12).to_a.shuffle(random: Random.new(3))
      p [1, 2, 3, 4, 5].sample(random: Random.new(42))
      # Ruby has two ways of turning a draw into a distinct index, and switches
      # between them at eleven picks; both sides of that line are pinned.
      (1..14).each { |n| p (1..50).to_a.sample(n, random: Random.new(n)) }
      p [].sample(random: Random.new(1))
      p [].shuffle(random: Random.new(1))

      # --- two generators on the same seed stay in step ----------------------------
      a = Random.new(77)
      b = Random.new(77)
      p 5.times.map { a.rand(1000) } == 5.times.map { b.rand(1000) }
      p Random.new(42) == Random.new(42)
      p Random.new(42) == Random.new(43)
    RUBY

    _(result).must_answer <<~'OUT'
      51
      92
      0.1834347898661638
      121958
      [0, 684]
      [1, 37]
      [7, 175]
      [12345, 482]
      [2147483648, 282]
      [4294967296, 973]
      [4294967297, 501]
      [18446744073709551623, 264]
      [340282366920938463463374607431768211456, 558]
      [-99, 641]
      [3.9, 874]
      0
      1
      0.13795030993842133
      7
      8
      1.36373689559256
      1.979444999161446
      658236186675747056275439
      242056307132997733637495580349
      "638bd438ce48200eef4fe8debde6d1d4"
      47
      83
      0.6221087710398319
      5
      [5, 1, 2, 2, 2, 3, 4, 5, 5, 3]
      Integer
      1
      [2, 5, 3, 1, 4]
      [6, 5, 2, 3, 12, 7, 8, 1, 4, 10, 9, 11]
      4
      [38]
      [41, 16]
      [43, 25, 4]
      [47, 6, 2, 43]
      [36, 15, 50, 41, 18]
      [11, 10, 38, 23, 47, 18]
      [48, 5, 27, 4, 22, 28, 45]
      [4, 22, 44, 7, 30, 11, 24, 48]
      [29, 23, 2, 25, 45, 32, 39, 35, 34]
      [10, 38, 17, 1, 32, 29, 35, 36, 11, 13]
      [26, 18, 30, 21, 2, 5, 40, 15, 27, 34, 39]
      [12, 29, 9, 6, 8, 3, 19, 30, 14, 23, 36, 46]
      [19, 50, 13, 20, 43, 40, 32, 5, 35, 12, 48, 25, 23]
      [44, 26, 15, 2, 12, 1, 49, 36, 19, 4, 37, 11, 8, 46]
      nil
      []
      true
      true
      false
    OUT
  end

  it "recursive implicit yield value" do
    result = zr(<<~'RUBY')
      # A self-recursive method that uses implicit `yield` and forwards its
      # block down the recursion (`countdown(n - 1) { yield }`) carries the
      # block's value back at the block's real type. The nested `{ yield }`
      # yields to the block of the outer call.

      def countdown(n)
        return yield if n <= 0
        countdown(n - 1) { yield }
      end
      puts countdown(2) { "done" }   # string block
      puts countdown(3) { 42 }       # int block at the same method
      puts countdown(0) { "base" }   # base case taken immediately

      # Non-recursive yield methods are unaffected (still inlined).
      def twice
        yield
        yield
      end
      twice { puts "tick" }

      def give
        yield 5
      end
      puts give { |x| x + 1 }

      # Instance-method implicit-yield recursion.
      class Counter
        def countdown(n)
          return yield if n <= 0
          countdown(n - 1) { yield }
        end
      end
      puts Counter.new.countdown(2) { "inst" }
    RUBY

    _(result).must_answer <<~'OUT'
      done
      42
      base
      tick
      tick
      6
      inst
    OUT
  end

  it "super with no literal block forwards the callers block" do
    result = zr(<<~'RUBY')
      class Parent
        def run
          yield
        end
      end
      class Child < Parent
        def run
          super
        end
      end
      puts(Child.new.run { "from-caller" })
    RUBY

    _(result).must_answer "from-caller\n"
  end

  it "top level def overrides a kernel function" do
    result = zr(<<~'RUBY')
      # Sibling/top-level resolution runs BEFORE the Kernel function set --
      # real Ruby's rule (a user `def rand` wins over Kernel#rand).

      def rand
        7
      end
      puts rand
    RUBY

    _(result).must_answer "7\n"
  end

  it "try convert across types" do
    result = zr(<<~'RUBY')
      # `Klass.try_convert(obj)` for the other three types that expose the
      # check-conversion protocol. All four doors share one implementation, and its
      # defining property is that the answer keeps the class it arrived with: the
      # type check is on the underlying representation, which a subclass instance
      # satisfies without needing a conversion at all.

      class Rows < Array; end
      class Index < Hash; end

      rows = Rows.new([1, 2])
      p Array.try_convert(rows).class
      p Array.try_convert(rows).equal?(rows)

      index = Index.new
      index[:a] = 1
      p Hash.try_convert(index).class
      p Hash.try_convert(index).equal?(index)

      # The duck side of each protocol.
      class Pair
        def to_ary = [:l, :r]
      end
      p Array.try_convert(Pair.new)

      class Config
        def to_hash = { mode: :fast }
      end
      p Hash.try_convert(Config.new)

      class Pattern
        def to_regexp = /ab+/i
      end
      p Regexp.try_convert(Pattern.new)
      p Regexp.try_convert(/lit/)

      # ...and a duck answering a SUBCLASS still satisfies the check as itself.
      class Wrapped
        def to_ary = Rows.new([:only])
      end
      p Array.try_convert(Wrapped.new).class

      # No conversion available: nil, never an exception.
      p Array.try_convert(nil)
      p Array.try_convert("abc")
      p Hash.try_convert([[1, 2]])
      p Regexp.try_convert("ab+")
      p Regexp.try_convert(nil)

      # A lying converter is the one raising case, per protocol.
      class Fibber
        def to_ary = :nope
      end
      begin
        Array.try_convert(Fibber.new)
      rescue TypeError => e
        puts e.message
      end

      # ...and one answering nil reads as "no conversion", not as a lie.
      class Silent
        def to_hash = nil
      end
      p Hash.try_convert(Silent.new)
    RUBY

    _(result).must_answer <<~'OUT'
      Rows
      true
      Index
      true
      [:l, :r]
      {mode: :fast}
      /ab+/i
      /lit/
      Rows
      nil
      nil
      nil
      nil
      nil
      can't convert Fibber to Array (Fibber#to_ary gives Symbol)
      nil
    OUT
  end

  it "until loop and modifier forms" do
    result = zr(<<~'RUBY')
      n = 5
      until n == 0
        n -= 1
      end
      puts n

      count = 0
      count += 1 while count < 3
      puts count

      x = 10
      x -= 1 until x <= 5
      puts x
    RUBY

    _(result).must_answer <<~'OUT'
      0
      3
      5
    OUT
  end

  it "value subclass conversions demote but mutators rewrap" do
    result = zr(<<~'RUBY')
      # A value subclass (`class S < String`) carries its payload behind a bridge
      # that re-wraps a builtin's return value into the subclass when it hands back
      # the SAME handle -- the no-allowlist heuristic for self-returning mutators
      # (`push`/`concat`). The identity CONVERSIONS return that same handle too but
      # must DEMOTE to the base class, and CRuby draws the line precisely: `to_s`/
      # `to_str`/`to_a`/`to_h` demote, while `to_ary`/`to_hash` return self. Getting
      # it wrong was not merely a wrong class -- a subclass whose `<=>` read
      # `o.to_s <=> to_s` never reached a plain String, so the user method
      # re-dispatched until the stack overflowed.

      class S < String; end
      class A < Array; end
      class H < Hash; end
      s = S.new("x"); a = A.new([1]); h = H.new
      puts s.to_s.class
      puts s.to_str.class
      puts a.to_a.class
      puts h.to_h.class
      puts a.to_ary.class
      puts h.to_hash.class
      puts a.dup.push(2).class
      puts s.dup.concat("y").class
      puts s.upcase.class
      puts a.map { |v| v }.class
      class Backwards < String
        def <=>(o); o.to_s <=> to_s; end
      end
      p [Backwards.new("aaa"), Backwards.new("bbb")].sort.map(&:to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      String
      String
      Array
      Hash
      A
      H
      A
      S
      String
      Array
      ["bbb", "aaa"]
    OUT
  end

  it "value subclass conversions protocol" do
    result = zr(<<~'RUBY')
      # A String/Array subclass satisfies the implicit-conversion protocol AS itself
      # -- `to_str`/`to_ary` answer the object, not a fresh builtin -- so every site
      # that asks for one has to unwrap the payload it carries.
      class MyStr < String; end
      class MyArr < Array; end
      s = MyStr.new("ab")
      p "x" + s
      p "abcab".gsub(s, "-")
      p File.join(s, "c")
      a = MyArr.new([1, 2])
      p [0].concat(a)
      p [[1, 2]].assoc(1)
      p Array(a)
      p Array(nil)
      p Array({a: 1})
      p Array(1..3)
      p Array(5)
      p String(s)
    RUBY

    _(result).must_answer <<~'OUT'
      "xab"
      "-c-"
      "ab/c"
      [0, 1, 2]
      [1, 2]
      [1, 2]
      []
      [[:a, 1]]
      [1, 2, 3]
      [5]
      "ab"
    OUT
  end

  it "warn answers its ruby parameters" do
    result = zr(<<~'RUBY')
      # CRuby writes Kernel#warn in Ruby, so its parameters are the Ruby
      # ones, not the `[[:rest]]` a method written in C answers. A library
      # that checks for the category keyword (prism's polyfill does) must
      # find it, or it prepends a wrapper to Kernel and Object.
      p Kernel.instance_method(:warn).parameters
      p Kernel.method(:warn).parameters
      p Kernel.instance_method(:warn).arity
      p Object.ancestors
      p Kernel.instance_method(:puts).parameters
    RUBY

    _(result).must_answer <<~'OUT'
      [[:rest, :msgs], [:key, :uplevel], [:key, :category]]
      [[:rest, :msgs], [:key, :uplevel], [:key, :category]]
      -1
      [Object, Kernel, BasicObject]
      [[:rest]]
    OUT
  end

  it "warn kernel" do
    result = zr(<<~'RUBY')
      # `warn arg, ...` writes each arg to stderr with a newline, as
      # Kernel#warn does.
      #
      # The test checks the stderr output of warn too. at_exit blocks run in
      # LIFO order after the main program ends.
      at_exit { puts "from at_exit" }
      warn "hello stderr"
      puts "after warn"
      warn "two", "args"
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT', stderr: "hello stderr\ntwo\nargs\n"
      after warn
      done
      from at_exit
    OUT
  end

  it "while loop with break and next values" do
    result = zr(<<~'RUBY')
      i = 0
      sum = 0
      while i < 10
        i += 1
        next if i == 5
        break if i == 8
        sum += i
      end
      puts sum
      puts i
    RUBY

    _(result).must_answer "23\n8\n"
  end

  it "pp's backtrace has no bind_call frame" do
    result = zr(<<~'RUBY')
      class Bad
        def pretty_print(q) = raise("in pp")
      end
      begin
        pp Bad.new
      rescue => e
        puts e.backtrace.grep_v(/prettyprint|pp\.rb/).first(3)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      core/kernel/kernel_test.rb:2:in 'Bad#pretty_print'
      core/kernel/kernel_test.rb:5:in 'Kernel#pp'
      core/kernel/kernel_test.rb:5:in '<main>'
    OUT
  end

  it "a Symbol block of pp is a private call" do
    result = zr(<<~'RUBY')
      begin
        [[1] * 3].each(&:pp)
      rescue NoMethodError => e
        p [e.class, e.message]
      end
      p [1].respond_to?(:pp)
    RUBY

    _(result).must_answer <<~'OUT'
      [NoMethodError, "private method 'pp' called for an instance of Array"]
      false
    OUT
  end
end
