# frozen_string_literal: true

require "spec_helper"

describe "Object: comparison and equality" do
  it "bool case equality" do
    result = zr(<<~'RUBY')
      # TrueClass#=== / FalseClass#=== is case equality: true only when the
      # argument is a boolean with the same value.
      p(true === true)
      p(true === false)
      p(true === 1)
      p(false === false)
      p(false === true)
      x = true
      p(x === true)
      p(x === false)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      false
      true
      false
    OUT
  end

  it "case equality boxed receiver" do
    result = zr(<<~'RUBY')
      # `===` on a boxed receiver dispatches on the receiver's runtime class the way
      # CRuby does: a Range covers, a Regexp matches, a Class tests membership. It
      # used to compile as plain equality, so all three answered false (#3963).
      p [1..10].map { |r| r === 5 }
      p [/b/].map  { |r| r === "abc" }
      p [Integer].map { |c| c === 5 }
      p [1..10].map { |r| r.===(5) }
      p ["a".."e"].map { |r| r === "c" }
      h = { a: 1..10 }
      p h.map { |k, r| r === 5 }
      p [1..10].map { |r| 5.then { |v| r === v } }
      p [1..10].select { |r| r === 5 }
      p [1..10, 20..30].map { |r| r === 5 }
      p [1..5, /b/, Integer, "x"].map { |pat| pat === 3 }
      p [1..5, /b/, Integer, "x"].map { |pat| pat === "abc" }
      p [->(x) { x * 2 }].map { |f| f === 5 }

      # The Regexp surface on a boxed receiver (#3961)
      p [/b/].map { |re| re.source }
      p [/b/].map { |re| re.match?("abc") }
      p [/b/].map { |re| "abc".match?(re) }
      p [/b/].map { |re| re.options }
      p [/b/i].map { |re| re.casefold? }
      p({ a: /b/ }.map { |k, re| re.source })
      p [/b/].map { |re| re.match("abc")[0] }
      p [/b/].map { |re| ("abc" =~ re) }
      p [/b/].map { |re| (re =~ "abc") }
      p [/z/].map { |re| ("abc" =~ re) }
      p [/(?<x>b)/].map { |re| re.names }
    RUBY

    _(result).must_answer <<~'OUT'
      [true]
      [true]
      [true]
      [true]
      [true]
      [true]
      [true]
      [1..10]
      [true, false]
      [true, false, true, false]
      [false, true, false, false]
      [10]
      ["b"]
      [true]
      [true]
      [0]
      [true]
      ["b"]
      ["b"]
      [1]
      [1]
      [nil]
      [["x"]]
    OUT
  end

  it "case equality dispatch" do
    result = zr(<<~'RUBY')
      class Even
        def ===(n); n.even?; end
      end
      e = Even.new

      puts(case 4 when e then "when-obj" else "when-missed" end)
      puts(case 3 when e then "when-obj" else "when-missed" end)

      r = case 4
          in ^e then "pin"
          else "pin-missed"
          end
      puts r

      puts [1, 2, 3, 4].grep(e).inspect
      puts (1..4).lazy.grep(e).to_a.inspect

      class Trip; end
      def Trip.===(n); n % 3 == 0; end
      puts(case 9 when Trip then "singleton" else "singleton-missed" end)

      puts(case 5 when Integer then "builtin-class" else "no" end)
      puts(case "hi" when /h/ then "regexp" else "no" end)
      puts(case 3 when 1..5 then "range" else "no" end)
      puts(case 2 when 1, 2, 3 then "listed" else "no" end)
      cands = [7, 8]
      puts(case 8 when *cands then "splat" else "no" end)
    RUBY

    _(result).must_answer <<~'OUT'
      when-obj
      when-missed
      pin
      [2, 4]
      [2, 4]
      singleton
      builtin-class
      regexp
      range
      listed
      splat
    OUT
  end

  it "case equality dispatches a user defined triple equals" do
    result = zr(<<~'RUBY')
      # `case`/`when`, an `in` value/pin pattern, and `grep` all dispatch the
      # pattern's own `===`. A shared native ladder bottoming out in `==` would
      # make a user class whose `===` differs from its `==` silently take the
      # WRONG branch, ignore a singleton `===` on a class, and make `lazy.grep`
      # disagree with eager `grep` on the same pattern. An Object-typed pin is
      # worse than wrong: emitting a bare `Arc<Even>` makes the GENERATED program
      # fail to compile. The builtin pattern shapes must keep their meaning.

      class Even
        def ===(n); n.even?; end
      end
      e = Even.new
      puts(case 4 when e then "when-obj" else "when-missed" end)
      puts(case 3 when e then "when-obj" else "when-missed" end)
      r = case 4
          in ^e then "pin"
          else "pin-missed"
          end
      puts r
      puts [1, 2, 3, 4].grep(e).inspect
      puts (1..4).lazy.grep(e).to_a.inspect
      class Trip; end
      def Trip.===(n); n % 3 == 0; end
      puts(case 9 when Trip then "singleton" else "singleton-missed" end)
      puts(case 5 when Integer then "builtin-class" else "no" end)
      puts(case "hi" when /h/ then "regexp" else "no" end)
      puts(case 3 when 1..5 then "range" else "no" end)
      puts(case 2 when 1, 2, 3 then "listed" else "no" end)
      cands = [7, 8]
      puts(case 8 when *cands then "splat" else "no" end)
    RUBY

    _(result).must_answer <<~'OUT'
      when-obj
      when-missed
      pin
      [2, 4]
      [2, 4]
      singleton
      builtin-class
      regexp
      range
      listed
      splat
    OUT
  end

  it "case when user equality" do
    result = zr(<<~'RUBY')
      # `case obj when other` asks `other === obj`, which for a class defining #==
      # is that method; comparing the C structs did not compile for a value type and
      # compared addresses for a heap object (#3820).
      class Eq1
        def initialize(v); @v = v; end
        def v; @v; end
        def ==(o); v == o.v; end
      end
      a = Eq1.new(1)
      b = Eq1.new(1)
      c = Eq1.new(2)
      p(case b when a then "eq" else "ne" end)
      p(case c when a then "eq" else "ne" end)
      case b
      when a then puts "stmt eq"
      else puts "stmt ne"
      end

      class Ce
        def initialize(v); @v = v; end
        def v; @v; end
        def ===(o); v == o.v; end
      end
      x = Ce.new(5)
      y = Ce.new(5)
      p(case y when x then "ceq" else "cne" end)
    RUBY

    _(result).must_answer <<~'OUT'
      "eq"
      "ne"
      stmt eq
      "ceq"
    OUT
  end

  it "count uses equality" do
    result = zr(<<~'RUBY')
      # Enumerable#count(item) counts elements EQUAL to its argument; the predicates
      # take a pattern and match with ===. A class argument told them apart (#3817).
      h = { a: 1, b: 2 }
      p h.count(Array)
      p h.count([:a, 1])
      p h.any?(Array)
      p h.none?(Array)
      p h.one?(Array)
      xs = [[1], [2], 3]
      p xs.count(Array)
      p xs.count([1])
      p xs.any?(Array)
      p [1, 2, 2].count(2)
      p [1, 2, 2].count(Integer)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      true
      false
      false
      0
      1
      true
      2
      0
    OUT
  end

  it "dup runs copy hooks the program wrote" do
    result = zr(<<~'RUBY')
      # `dup`/`clone` run the copy hooks only where CRuby's road would reach code
      # the program wrote. A NATIVE receiver's own initialize_copy row guards the
      # direct spelling on a built receiver -- dup's fresh copy is not that, so
      # Time#dup works while Time#initialize_copy on a built Time still refuses.
      t = Time.utc(2026, 1, 2, 3, 4, 5)
      d = t.dup
      p d == t
      p d.equal?(t)
      begin
        t.send(:initialize_copy, d)
      rescue TypeError => e
        p e.message
      end

      class Carrier
        attr_reader :log
        def initialize = @log = []
        def initialize_copy(other)
          @log = other.log + [:copied]
          super
        end
      end

      c = Carrier.new
      p c.dup.log
      p c.clone.log
      p c.log
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      "already initialized Time"
      [:copied]
      [:copied]
      []
    OUT
  end

  it "eql equal" do
    result = zr(<<~'RUBY')
      # Integer/String #eql? and #equal? on typed receivers.
      # eql?/equal? are value-equality with NO numeric coercion, unlike ==.

      a = 1
      b = 1
      c = 2
      f = 1.0
      s = "x"
      t = "x"
      u = "y"

      # Integer#eql? : true only for an Integer-typed, value-equal arg
      puts a.eql?(b)      # true
      puts a.eql?(c)      # false
      puts a.eql?(f)      # false  (no coercion: 1 != 1.0)
      puts 1.eql?(1)      # true   (bare literals)
      puts 1.eql?(1.0)    # false

      # Integer#equal? : value identity for fixnums (same as eql? here)
      puts a.equal?(b)    # true
      puts a.equal?(c)    # false
      puts 5.equal?(5)    # true

      # String#eql? : byte-equal only for a String-typed arg
      puts s.eql?(t)      # true
      puts s.eql?(u)      # false
      puts "x".eql?("x")  # true

      # String#equal? : object identity is POINTER identity. Each literal
      # OCCURRENCE is its own static object (no cross-occurrence merging), so two
      # textually equal literals are distinct objects, matching plain CRuby.
      # Aliasing (t = s) still answers truthfully. The one residue: re-evaluating
      # the SAME occurrence (a literal in a loop) yields one object -- the
      # frozen-string-literal semantics spinel's immutable strings always had.
      puts s.equal?(s)    # true   (same variable)
      puts s.equal?(t)    # false  (two occurrences: distinct objects)
      puts s.equal?(u)    # false  (different value)
      puts "x".equal?("x") # false (two occurrences: distinct objects)

      # typed receiver, polymorphic arg (element drawn from a mixed array)
      mix = [1, "x", 1.0]
      puts a.eql?(mix[0]) # true
      puts a.eql?(mix[1]) # false  (arg is a String)
      puts s.eql?(mix[1]) # true
      puts s.eql?(mix[0]) # false  (arg is an Integer)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      false
      true
      false
      true
      true
      false
      true
      true
      false
      false
      false
      true
      false
      true
      false
    OUT
  end

  it "eql on chain result" do
    result = zr(<<~'RUBY')
      # Array#eql? compares element-wise, like ==, including on a method-chain result.
      def s(x); x; end
      p s([2, 1]).sort.eql?([1, 2])
      p [1, 2].eql?([1, 2])
      p [1, 2].eql?([1, 3])
      p [1, 2].eql?([1, 2, 3])
      p s([1, 2]).eql?([1, 2])
      p s([1, 2]).eql?([9, 9])
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      true
      false
    OUT
  end

  it "exc eq clone shadow" do
    result = zr(<<~'RUBY')
      # Three surfaces from the conformance wave.

      # A user Exception subclass keeps Exception#== -- class plus message -- rather
      # than falling back to Object#== identity
      class OvB < StandardError; end
      p(OvB.new("t") == OvB.new("t"))
      a = OvB.new("t")
      b = OvB.new("t")
      p(a == b)
      p(a == OvB.new("u"))
      p(a == a)
      p(a != b)
      p(a.equal?(b))

      class WithIvar < StandardError
        def initialize(m, code)
          super(m)
          @code = code
        end
        def code; @code; end
      end
      p(WithIvar.new("m", 1) == WithIvar.new("m", 2))
      p(WithIvar.new("m", 1) == WithIvar.new("n", 1))

      # Hash#clone carries the frozen flag over, Hash#dup drops it (Array and String
      # already did)
      h = { a: 1 }.freeze
      v = h.clone
      p v.frozen?
      r = ((v[:b] = 2) rescue $!.class); p r
      p h.dup.frozen?
      p({ a: 1 }.clone.frozen?)
      p [1, 2].freeze.clone.frozen?
      p "ab".freeze.clone.frozen?

      # The shadow copy of an included module's method (the super target) is
      # implementation detail: reflection must not see it
      module Inc; def tag; "inc"; end; end
      class Sub
        include Inc
        def tag; "sub(" + super + ")"; end
      end
      p Sub.instance_methods(false)
      p Sub.method_defined?(:__inc_0_tag)
      p Sub.new.respond_to?(:__inc_0_tag)
      p Sub.new.tag
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
      false
      true
      false
      true
      FrozenError
      false
      false
      true
      true
      [:tag]
      false
      false
      "sub(inc)"
    OUT
  end

  it "explicit triple equals on class values checks ancestry" do
    result = zr(<<~'RUBY')
      class Widget
      end

      puts Integer === 5
      puts Widget === Widget.new
      puts Widget === 5
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
    OUT
  end

  it "is a descendant runtime" do
    result = zr(<<~'RUBY')
      # Static-vs-runtime class lattice for `is_a?` / `kind_of?` /
      # `instance_of?` when the recv's static type is a parent class but
      # the runtime instance can be any descendant. Previously spinel
      # collapsed the descendant-target case to literal FALSE because
      # is_class_or_ancestor(parent, child) returns 0; the recv's runtime
      # cls_id was never consulted.
      #
      # Fix: when the target is identical to, ancestor of, or descendant
      # of the static recv type, consult the actual cls_id slot.
      # `is_a?` / `kind_of?` use ancestor-walk (sp_class_le); `instance_of?`
      # uses exact equality.

      class Animal
      end
      class Dog < Animal
      end
      class Cat < Animal
      end
      class Puppy < Dog
      end

      # is_a? / kind_of? — recv typed Animal, target a proper descendant.
      def kind(a)
        if a.is_a?(Dog)
          "dog"
        elsif a.kind_of?(Cat)
          "cat"
        else
          "animal"
        end
      end

      puts kind(Dog.new)      # dog
      puts kind(Cat.new)      # cat
      puts kind(Animal.new)   # animal
      puts kind(Puppy.new)    # dog (Puppy is_a? Dog)

      # instance_of? — recv typed Animal, target a proper descendant.
      # Pre-fix this collapsed to literal FALSE; runtime instance is
      # never consulted.
      def exact_is_dog(a)
        a.instance_of?(Dog)
      end

      puts exact_is_dog(Dog.new)      # true  — runtime cls_id matches Dog
      puts exact_is_dog(Puppy.new)    # false — Puppy is_a? Dog but not instance_of? Dog
      puts exact_is_dog(Cat.new)      # false — unrelated descendant
      puts exact_is_dog(Animal.new)   # false — runtime cls_id is Animal, not Dog

      # instance_of? — recv typed Animal, target IS the static type.
      # Pre-fix this collapsed to literal TRUE (`cname == arg0`); a
      # parent-typed local holding a descendant should fail this.
      def exact_is_animal(a)
        a.instance_of?(Animal)
      end

      puts exact_is_animal(Animal.new)  # true  — runtime cls_id matches Animal
      puts exact_is_animal(Dog.new)     # false — runtime cls_id is Dog, not Animal
      puts exact_is_animal(Puppy.new)   # false — runtime cls_id is Puppy
    RUBY

    _(result).must_answer <<~'OUT'
      dog
      cat
      animal
      dog
      true
      false
      false
      false
      true
      false
      false
    OUT
  end

  it "issue method object equality" do
    result = zr(<<~'RUBY')
      # Method#== compares receiver IDENTITY (`equal?`) as well as the bound method
      # entry, so two Methods over two distinct String receivers are unequal even
      # though both call the same String#upcase.
      m1 = "abc".method(:upcase)
      m2 = "abc".method(:upcase)
      p m1 == m2
    RUBY

    _(result).must_answer "false\n"
  end

  it "main object identity" do
    result = zr(<<~'RUBY')
      # The top-level `self` renders as `main`, not as an address. ruby gets there
      # by installing `to_s`/`inspect` singletons on the object; zr asks by
      # identity, because installing a singleton at startup would mark the
      # runtime-overlay maps live for every program.

      p self
      p self.to_s
      p self.inspect
      p "#{self}"
      p [self.class, self.frozen?]

      # Every route to the same object renders the same way.
      def top_helper = self
      p top_helper
      p self.equal?(top_helper)
      p [self]
      p({ self => 1 }.keys)

      # An ivar does not turn it back into the `#<Object:0x... @x=1>` form.
      p self.instance_variables
      @x = 1
      p self.instance_variables
      p self

      # An ORDINARY Object still renders with its address and ivars.
      o = Object.new
      p o.to_s.start_with?("#<Object:")
      p o.inspect.start_with?("#<Object:")
      class Holder
        def initialize = @a = 1
      end
      p Holder.new.inspect.include?("@a=1")

      # `TOPLEVEL_BINDING`'s receiver IS main, and reading the constant is what
      # makes zr materialize the top-level frame at all.
      b = TOPLEVEL_BINDING
      p b.class
      p b.receiver
      p b.receiver.equal?(self)
    RUBY

    _(result).must_answer <<~'OUT'
      main
      "main"
      "main"
      "main"
      [Object, false]
      main
      true
      [main]
      [main]
      []
      [:@x]
      main
      true
      true
      true
      Binding
      main
      true
    OUT
  end

  it "method receiver equal self" do
    result = zr(<<~'RUBY')
      # method(:m).receiver of a bare top-level method IS the main object, so the
      # identity test against self folds to true (#3245).
      def d(n) = n
      p(method(:d).receiver.equal?(self))
      p(method(:d).receiver == self)

      class C
        def m = 1
      end
      o = C.new
      p(o.method(:m).receiver.equal?(o))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
    OUT
  end

  it "more truthies nil compare" do
    result = zr(<<~'RUBY')
      # #562 (gurgeous / Adam Doppelt). A corpus of `<container_op>
      # == nil` predicates that CRuby answers as true but spinel
      # previously emitted as false. Root cause: typed-array /
      # typed-hash returns can't represent nil at the value level
      # (sp_IntArray_get returns 0 on out-of-range, sp_StrIntHash_get
      # returns 0 on missing key, etc.), so the existing
      # `int == nil` short-circuit in compile_eq folded the
      # predicate to FALSE.
      #
      # compile_container_op_nil_check recognizes specific call
      # shapes on the lhs of `== nil` and emits a CRuby-equivalent
      # runtime predicate:
      #   arr[i] / arr.delete_at(i) -> (i < 0 || i >= len)
      #   arr.first / arr.last / arr.pop -> (len == 0)
      #   arr.find_index(x) -> !arr.include?(x)
      #   hash[k] -> !hash.has_key?(k)
      #   regex.match(s) -> !regex.match?(s)
      #
      # Plus `Array.new.instance_of?(Array)` folds to TRUE: every
      # Array variant (int_array / str_array / etc.) is
      # conceptually `Array`; same for Hash variants.

      p ([1, 2, 3][99] == nil)          # 01
      p Array.new.instance_of?(Array)   # 02
      p ([1, 2].delete_at(3) == nil)    # 03
      p ([].first == nil)               # 04
      p ([].last == nil)                # 05
      p ([].pop == nil)                 # 06
      p ([1, 2].find_index(3) == nil)   # 07
      p ({0 => 0}[5] == nil)            # 08
      p (/xyz/.match("abxyc") == nil)   # 09
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
    OUT
  end

  it "nullable obj nil compare" do
    result = zr(<<~'RUBY')
      # Issue #423. `if c != nil` (or `while c != nil`) on a nullable
      # user-class local emitted the body unconditionally -- the `!=
      # nil` comparison was constant-folded to TRUE, the surrounding
      # `if` was collapsed (compile_if_stmt's "static TRUE fold"), and
      # the body ran even when c was NULL. Found in tep's route
      # dispatch loop: `while route != nil && !served` entered with
      # route = NULL after a no-match POST and segfaulted.
      #
      # Root cause: `compile_eq`'s cross-type fold treated `obj_<C>? ==
      # nil` and `obj_<C>? != nil` as type-strict pairs (LHS is obj,
      # RHS is nil-typed; the existing fold returned "FALSE" / "TRUE"
      # because "obj vs nil are different types, always unequal").
      # That's right for a non-nullable `obj_<C>` -- the C pointer is
      # never NULL by design -- but wrong for `obj_<C>?` where NULL is
      # the runtime nil sentinel.
      #
      # Fix: in compile_eq's cross-type-prim-vs-obj branch, when
      # other_t == "nil", check is_nullable_type on the obj side. If
      # nullable, emit the actual pointer comparison (`obj == NULL` /
      # `obj != NULL`); fall through to the original FALSE/TRUE fold
      # only for non-nullable obj types.
      #
      # Coverage:
      #   - if c != nil / if c / if !c.nil? on a function returning
      #     nil-or-Foo: all three forms agree.
      #   - while c != nil on the same shape: loop terminates instead
      #     of spinning forever.
      #   - non-nullable obj_<C> (c = Foo.new) still folds to TRUE for
      #     != nil (no pointer-vs-NULL emit needed; the value is never
      #     NULL).

      class Box
        attr_accessor :tag
        def initialize(tag)
          @tag = tag
        end
      end

      def find_or_nil(want)
        if want == "yes"
          return Box.new("found")
        end
        nil
      end

      # 1. nil branch -- all three forms should agree.
      c = find_or_nil("no")
      puts "c=" + (c.nil? ? "nil" : "non-nil")     # c=nil

      if c != nil
        puts "ne-nil: ENTERED"
      else
        puts "ne-nil: skipped"                      # skipped (correct)
      end

      if c
        puts "tr: ENTERED"
      else
        puts "tr: skipped"                          # skipped
      end

      if !c.nil?
        puts "not-nilq: ENTERED"
      else
        puts "not-nilq: skipped"                    # skipped
      end

      # 2. non-nil branch -- all three forms enter the body.
      d = find_or_nil("yes")
      puts "d=" + (d.nil? ? "nil" : "non-nil")     # d=non-nil

      if d != nil
        puts "d-ne-nil: ENTERED"                    # ENTERED
      else
        puts "d-ne-nil: skipped"
      end

      # 3. while loop terminates instead of spinning.
      n = 0
      while c != nil
        n += 1
        break if n > 3
      end
      puts "n=" + n.to_s                            # n=0

      # 4. non-nullable obj (Foo.new is always non-nil) still folds.
      e = Box.new("eager")
      if e != nil
        puts "e-ne-nil: ENTERED"                    # ENTERED (non-nullable, always true)
      else
        puts "e-ne-nil: skipped"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      c=nil
      ne-nil: skipped
      tr: skipped
      not-nilq: skipped
      d=non-nil
      d-ne-nil: ENTERED
      n=0
      e-ne-nil: ENTERED
    OUT
  end

  it "display writes, clone(freeze:) answers, and instance_variable_defined? takes a String or a Symbol" do
    result = zr(<<~'RUBY')
      # Kernel#display, String clone(freeze:), equal?/eql? on nil/bool/symbol,
      # and instance_variable_defined? with string/symbol names.
      5.display
      puts
      "str".display
      puts
      s = "x".freeze.clone(freeze: false)
      s << "y"
      p s
      p(nil.equal?(nil))
      p(nil.equal?(0))
      p(true.equal?(true))
      p(true.equal?(false))
      p(false.equal?(false))
      p(:a.equal?(:a))
      p(:a.equal?(:b))
      class C; def initialize; @x = 7; end; end
      o = C.new
      p o.instance_variable_defined?('@x')
      p o.instance_variable_defined?(:@x)
      p o.instance_variable_defined?('@nope')
    RUBY

    _(result).must_answer <<~'OUT'
      5
      str
      "xy"
      true
      false
      true
      false
      true
      true
      false
      true
      true
      false
    OUT
  end

  it "dup answers a separate object that is neither == nor equal? to the receiver" do
    result = zr(<<~'RUBY')
      o = Object.new
      p(o.dup == o)
      p(o.dup.equal?(o))
      class C
        def initialize
          @v = 1
        end
      end
      c = C.new
      p(c.dup == c)
      p(c.clone == c)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
    OUT
  end

  it "dup and clone answer a separate instance and call a user initialize_copy" do
    result = zr(<<~'RUBY')
      # dup/clone of a user object must produce a SEPARATE instance (not alias the
      # original), and must invoke a user-defined initialize_copy hook so deep-copy
      # semantics work. Previously dup/clone fell through to an identity shortcut and
      # returned the receiver itself, silently aliasing mutable ivars.

      # No hook: shallow copy still yields independent objects for scalar ivars.
      class Counter
        attr_accessor :n
        def initialize(n); @n = n; end
      end
      a = Counter.new(5)
      b = a.dup
      b.n = 99
      p [a.n, b.n]              # [5, 99]

      # initialize_copy hook: deep-copy a mutable ivar so mutation does not leak back.
      class Box
        attr_accessor :items
        def initialize(items); @items = items; end
        def initialize_copy(orig); @items = orig.items.dup; end
      end
      src = Box.new([1])
      cp = src.dup
      cp.items << 2
      p [src.items, cp.items]   # [[1], [1, 2]]

      # clone goes through the same hook.
      cl = src.clone
      cl.items << 9
      p [src.items, cl.items]   # [[1], [1, 9]]

      # Multiple ivars are all copied.
      class Point
        attr_accessor :x, :y
        def initialize(x, y); @x = x; @y = y; end
      end
      p1 = Point.new(1, 2)
      p2 = p1.dup
      p2.x = 10
      p [p1.x, p1.y, p2.x, p2.y]  # [1, 2, 10, 2]

      # Hook defined on a parent, dup of a subclass instance.
      class Base
        attr_accessor :v
        def initialize(v); @v = v; end
        def initialize_copy(o); @v = o.v.dup; end
      end
      class Child < Base; end
      ch = Child.new([7])
      ch2 = ch.dup
      ch2.v << 8
      p [ch.v, ch2.v]          # [[7], [7, 8]]

      # Hook on a parent, with BOTH the parent and the subclass dup'd. Dup'ing both
      # unifies initialize_copy's param to the parent class, so the subclass dup must
      # still reach the hook (the original is cast to the param's class).
      b0 = Base.new([1])
      b1 = b0.dup
      b1.v << 2
      c0 = Child.new([3])
      c1 = c0.dup
      c1.v << 4
      p [b0.v, b1.v, c0.v, c1.v]  # [[1], [1, 2], [3], [3, 4]]
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 99]
      [[1], [1, 2]]
      [[1], [1, 9]]
      [1, 2, 10, 2]
      [[7], [7, 8]]
      [[1], [1, 2], [3], [3, 4]]
    OUT
  end

  it "the identity and reflection rows answer what CRuby answers" do
    result = zr(<<~'RUBY')
      # Object identity/reflection conformance (KieranP #2281-2286)
      a = ->(x) { x }
      p a.equal?(a)                       # #2281 Proc equal?
      p a.frozen?                         # #2282 Proc frozen?
      b = ->(x) { x }
      p a.equal?(b)
      e = [1].each
      p e.equal?(e)                       # Enumerator equal?
      p e.frozen?
      r = /a/
      p r.equal?(r)                       # Regexp equal?
      p r.frozen?                         # a Regexp literal is frozen
      class C
        def initialize; @n = 5; end
      end
      o = C.new
      p o.object_id.is_a?(Integer)        # #2283 object_id -> stable Integer
      p o.object_id == o.object_id
      p o.hash == o.hash                  # #2284 hash is stable
      p Object.new.is_a?(Object)          # #2286 is_a?(Object)
      p Object.new.is_a?(Kernel)
      p Enumerable.ancestors              # #2285 module ancestors
      p Comparable.ancestors
      class MyColl
        include Enumerable
        def each; yield 1; yield 2; end
      end
      p MyColl.ancestors.include?(Enumerable)
      p(Enumerable.superclass) rescue p($!.class)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      false
      true
      true
      true
      true
      true
      true
      true
      [Enumerable]
      [Comparable]
      true
      NoMethodError
    OUT
  end

  it "== with no user == is identity, so an instance equals only itself" do
    result = zr(<<~'RUBY')
      # Object#== with no user-defined == is identity comparison: an instance is
      # equal only to itself, and two distinct instances are never equal. Receivers
      # go through method params so the compare hits the runtime object path (and so
      # the class stays pointer-backed rather than a by-value type).
      class Widget
        def initialize(n)
          @n = n
        end

        def n
          @n
        end
      end

      def same?(a, b)
        a == b
      end

      def diff?(a, b)
        a != b
      end

      w = Widget.new(1)
      x = Widget.new(1)

      puts same?(w, w)   # same object -> true
      puts same?(w, x)   # distinct objects, same contents -> false (identity)
      puts diff?(w, x)   # true
      puts diff?(w, w)   # false
      puts(w.n == x.n)   # ivar values compared, not identity -> true
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      true
    OUT
  end

  it "equal? is reference identity, and freeze answers the receiver" do
    result = zr(<<~'RUBY')
      # Object#equal? is reference identity (a heap instance is its pointer);
      # freeze is a no-op returning self, so frozen? consistently reports false.
      class Foo
        def initialize(v)
          @v = v
        end
      end
      a = Foo.new(1)
      b = a
      c = Foo.new(1)
      p a.equal?(b)
      p a.equal?(c)
      p a.equal?(a)
      p c.freeze.equal?(c)
      p 1.equal?(1)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
    OUT
  end

  it "poly equality mixed sites" do
    result = zr(<<~'RUBY')
      def same(a, b)
        a == b
      end

      puts same(1, 1)
      puts same("x", "x")
      puts same(1, 1.0)

      def less_or_equal(a, b)
        a <= b
      end

      puts less_or_equal(1, 2.0)
      begin
        puts less_or_equal(1, "x")
      rescue
        puts false
      end
      begin
        puts less_or_equal(false, true)
      rescue
        puts false
      end
      begin
        puts less_or_equal(nil, nil)
      rescue
        puts false
      end

      def maybe_string(flag)
        if flag
          "actual"
        else
          nil
        end
      end

      puts same(maybe_string(false), nil)
      puts same(maybe_string(true), nil)
      puts same(maybe_string(false), "")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      false
      false
      false
      true
      false
      false
    OUT
  end

  it "uniq uses eql identity for user class defining only eq" do
    result = zr(<<~'RUBY')
      # uniq (and Array#eql?) dedup by eql?/hash, not ==. A class that defines
      # only == keeps every instance distinct (Object#eql? is identity), so
      # two equal-by-== Points both survive uniq -- unlike include?/index,
      # which do use ==.

      class Point
        attr_reader :x
        def initialize(x) = @x = x
        def ==(o) = o.is_a?(Point) && @x == o.x
      end
      pts = [Point.new(1), Point.new(2), Point.new(3)]
      p pts.include?(Point.new(2))
      p pts.index(Point.new(3))
      p [Point.new(1), Point.new(1), Point.new(2)].uniq.map(&:x)
      p [1.0, 1, 1, 2].uniq
      p [1].eql?([1])
      p [1].eql?([1.0])
    RUBY

    _(result).must_answer <<~'OUT'
      true
      2
      [1, 1, 2]
      [1.0, 1, 2]
      true
      false
    OUT
  end

  it "user defined equality dispatches everywhere" do
    result = zr(<<~'RUBY')
      class Point
        attr_reader :x

        def initialize(x)
          @x = x
        end

        def ==(other)
          other.is_a?(Point) && x == other.x
        end
      end

      puts Point.new(1) == Point.new(1)
      puts Point.new(1) == Point.new(2)
      puts Point.new(1) == 5
      puts Point.new(1) != Point.new(2)
      puts [Point.new(1), Point.new(2)] == [Point.new(1), Point.new(2)]
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      true
    OUT
  end

  it "value type identity" do
    result = zr(<<~'RUBY')
      a = Complex(2, 3)
      p a == Complex(2, 3)
      p a.eql?(Complex(2, 3))
      p a.equal?(a)
      r = Rational(1, 2)
      p r == Rational(1, 2)
      p r.equal?(r)
      g = (1..3)
      p g == (1..3)
      p g.eql?(1..3)
      p g.equal?(g)
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
    OUT
  end
end
