# frozen_string_literal: true

require "spec_helper"

describe "Classes: dispatch" do
  it "boxed arg int parameter" do
    result = ze0(<<~'RUBY')
      # A value with no static type (an sp_RbVal) reaching a builtin parameter
      # declared mrb_int was emitted with no unbox step, so the generated C did not
      # compile. An empty array literal as a parameter default is the shortest way to
      # produce one: the parameter has no element type, so a read of it answers the
      # polymorphic accessor's boxed value.
      def bytes_of(bytes: [])
        s = String.new("\xFF\xFF\xFF\xFF")
        4.times { |i| s.setbyte(i, bytes[i]) }
        s.bytes
      end
      p bytes_of(bytes: [1, 2, 3, 4])

      def string_ops(a: [])
        s = "hello world"
        [s.byteslice(a[0], a[1]),
         s.byteslice(a[0]),
         s.rindex("l", a[2]),
         s.split("o", a[1]),
         "ff".to_i(a[3])]
      end
      p string_ops(a: [1, 3, 8, 16])

      def array_ops(a: [])
        arr = [1, 2, 3, 4]
        combos = arr.combination(a[1]).to_a.length
        perms = arr.permutation(a[1]).to_a.length
        rot = [1, 2, 3].rotate!(a[0])
        dropped = [9, 8, 7].delete_at(a[0])
        [combos, perms, rot, dropped, arr.dig(a[0])]
      end
      p array_ops(a: [1, 2])

      def num_ops(a: [])
        [1234.round(a[0]), Integer.sqrt(a[1])]
      end
      p num_ops(a: [-2, 17])

      # A split with a limit inside a block form takes the same route.
      def split_limit(a: [])
        out = []
        "a,b,c,d".split(",", a[0]).each { |part| out << part }
        out
      end
      p split_limit(a: [2])
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      ["ell", "e", 3, ["hell", " w", "rld"], 255]
      [6, 12, [2, 3, 1], 8, 2]
      [1200, 4]
      ["a", "b,c,d"]
    OUT
  end

  it "poly array clear expr" do
    result = ze0(<<~'RUBY')
      # `Array#clear` in *expression* position on a poly_array. The
      # stmt-form was already supported; the expr-form fell through
      # to the unresolved-call warning and emitted literal 0, which
      # made `c = a.clear` mistype `c` as int.
      #
      # Surfaced via optcarrot's `@sp_visible ||= @sp_map.clear` shape
      # (the `||=` form needs a typed initializer here so Spinel's
      # per-variable type inference has a concrete poly_array tag to
      # unify with — Ruby allows type changes across reassignment but
      # Spinel doesn't).

      a = [1, "two", :three, [4, 5]]
      b = a.clear

      puts a.length    # 0
      puts b.length    # 0 (b is a, just emptied — same array, just mutated)

      # Subsequent push refills from index 0.
      a.push(99)
      puts a.length    # 1
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      1
    OUT
  end

  it "poly array eq all nil literal" do
    result = ze0(<<~'RUBY')
      # `<poly_array> == [nil, nil, ...]` shape. The RHS array literal
      # would otherwise lower to int_array of zeros and fall through to
      # a raw pointer compare. The contextual lift at the == call site
      # rebuilds the RHS as a poly_array of box_nil() and dispatches
      # through sp_PolyArray_eq, matching the CRuby semantic that
      # `Array.new(N) == [nil] * N` is true. Issue #619 puzzle 4.
      p Array.new(3) == [nil, nil, nil]   # true
      p Array.new(0) == []                # true (empty arrays: handled by the IntArray fallback)
      p Array.new(2) == [nil, nil]        # true
      p Array.new(3) != [nil, nil, nil]   # false
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
    OUT
  end

  it "class basicobject superclass" do
    result = ze0(<<~'RUBY')
      p BasicObject.superclass
      v = BasicObject.superclass; p v
      p BasicObject.superclass.nil?
      p Object.superclass
      p Object.superclass.nil?
      # nullable class value works through a variable-held receiver too
      w = BasicObject
      p w.superclass
      p w.superclass.nil?
      # and boxed into a container / walked up a user chain to the root
      p [Object.superclass, BasicObject.superclass]
      class A; end
      class B < A; end
      p B.superclass.superclass.superclass.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      true
      BasicObject
      false
      nil
      true
      [BasicObject, nil]
      nil
    OUT
  end

  it "class object dispatch" do
    result = ze0(<<~'RUBY')
      # A user class method called on a Class-object value: dispatch on the boxed
      # class id (models Rails' `model.table_name`).
      class A
        def self.table_name; "as"; end
      end
      class B
        def self.table_name; "bs"; end
      end
      class Rel
        def initialize(model); @model = model; @table = model.table_name; end
        def table; @table; end
      end
      puts Rel.new(A).table
      puts Rel.new(B).table

      # a class method WITH an argument, dispatched through an ivar-held Class value
      # (the row-hydration half of the Relation pattern) -- the argument is
      # evaluated once even across the per-class switch.
      class Row
        attr_reader :v
        def initialize(v); @v = v; end
        def self.build(row); new("Row:#{row}"); end
      end
      class Col
        attr_reader :v
        def initialize(v); @v = v; end
        def self.build(row); new("Col:#{row}"); end
      end
      class Hydrator
        def initialize(model); @model = model; end
        def hydrate(rows); rows.map { |r| @model.build(r) }; end
      end
      puts Hydrator.new(Row).hydrate(["x"]).first.v
      puts Hydrator.new(Col).hydrate(["y"]).first.v
    RUBY

    _(result).must_answer <<~'OUT'
      as
      bs
      Row:x
      Col:y
    OUT
  end

  it "Kernel#method answers a Method that reports its name and calls" do
    result = ze0(<<~'RUBY')
      # Kernel#method returns a Method object (not Integer 0). .class and
      # .name dispatch; for a top-level user method, .call works too.
      m = method(:puts)
      puts m.class
      puts m.name

      def dbl(x)
        x * 2
      end
      d = method(:dbl)
      puts d.class
      puts d.name
      puts d.call(21)
    RUBY

    _(result).must_answer <<~'OUT'
      Method
      puts
      Method
      dbl
      42
    OUT
  end

  it "mega" do
    result = ze0(<<~'RUBY')
      # Test megamorphic dispatch (3+ types)

      class Dog
        def speak; "Woof!"; end
        def name; "Dog"; end
      end

      class Cat
        def speak; "Meow!"; end
        def name; "Cat"; end
      end

      class Bird
        def speak; "Tweet!"; end
        def name; "Bird"; end
      end

      def make_noise(animal)
        puts animal.speak
      end

      make_noise(Dog.new)   # Woof!
      make_noise(Cat.new)   # Meow!
      make_noise(Bird.new)  # Tweet!

      # Also test with name method
      def identify(animal)
        puts animal.name
      end

      identify(Dog.new)   # Dog
      identify(Cat.new)   # Cat
      identify(Bird.new)  # Bird

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      Woof!
      Meow!
      Tweet!
      Dog
      Cat
      Bird
      done
    OUT
  end

  it "obj class dispatch" do
    result = ze0(<<~'RUBY')
      # Issue #419. `obj.class` was unresolved on an instance -- emitted
      # `cannot resolve call to 'class' on obj_<C> (emitting 0)` and
      # downstream methods cascaded through int -> 0. Sibling to #404
      # Phase 1 (which closed the literal-reference direction `c = Foo`):
      # this is the reflection direction, fetching the class FROM an
      # instance.
      #
      # Fix:
      #   - Codegen (compile_object_method_expr's is_obj_type arm): when
      #     mname is "class", emit `((sp_Class){<cls_idx>LL})`.
      #   - Codegen (compile_object_method_expr's recv_type=="class"
      #     arm): detect chained `<obj>.class.<cmeth>` via AST shape
      #     (recv is a `class` CallNode whose own recv has a known
      #     obj_<C> type) and dispatch directly to `sp_<C>_cls_<m>`,
      #     bypassing the runtime sp_Class value.
      #   - Inference: infer_method_name_type returns "class" for `obj.class`
      #     and the cmeth's return type for `<obj>.class.<cmeth>`.
      #   - DCE (collect_cls_calls): when the recv is a `class` CallNode,
      #     mark cmeth live on every class that defines one. Over-
      #     approximates because LocalVariableReadNode types aren't
      #     resolvable at DCE time (they're intentionally not cached
      #     by walk_and_cache), but DCE prefers a kept-but-unused
      #     method over a stripped live one.
      #   - String interpolation (`"#{self.class}"`): treat sp_Class
      #     value via sp_class_to_s, not (long long)-cast which is
      #     wrong for a struct.
      #
      # Coverage: chained .class.<cmeth>, plain `obj.class.to_s`
      # (uses the recv_type=="class" -> to_s arm from #404), and the
      # string-interpolation form `"#{self.class}"` that optcarrot's
      # default inspect uses.

      class Foo
        def self.greet
          "hello-from-foo"
        end
      end

      f = Foo.new
      puts f.class.greet              # hello-from-foo
      puts f.class.to_s               # Foo

      class Bar
        attr_accessor :v
        def initialize
          @v = 0
        end
        def describe
          "#<#{ self.class }>"
        end
      end

      b = Bar.new
      puts b.describe                 # #<Bar>

      # Subclass: dispatch should pick up the cmeth defined on the
      # inherited class. Spinel's cmeth lookup walks parents via
      # cls_cmethod_owner, mirroring CRuby's dispatch.
      class Base
        def self.kind
          "base-kind"
        end
      end

      class Child < Base
      end

      c = Child.new
      puts c.class.kind               # base-kind
    RUBY

    _(result).must_answer <<~'OUT'
      hello-from-foo
      Foo
      #<Bar>
      base-kind
    OUT
  end

  it "object new builds a distinct boxed sentinel" do
    result = ze0(<<~'RUBY')
      # `Object.new` emitted `Arc::new(zeo_rt::Object)` -- using the struct
      # `Object` (a private-field struct, not a unit struct) as a value, an
      # E0423 that never compiled. It must be `Object::default()`. Each call is
      # a fresh Arc, so two sentinels are distinct by identity.

      A = Object.new
      B = Object.new
      p A == B
      p A == A
      p A.is_a?(Object)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
    OUT
  end

  it "object reopen poly dispatch" do
    result = ze0(<<~'RUBY')
      # A method reopened on Object is callable on ANY receiver, including a boxed
      # scalar inside a poly value: the poly dispatch needs it as its default arm
      # (an empty cls_id switch left NULL and segfaulted).
      class Tag
        def initialize(v)
          @v = v
        end
        def show
          "tag(#{@v.inspect})"
        end
      end
      class Object
        def tagged
          Tag.new(self)
        end
      end
      x = case 1
          when 2 then false
          when 1 then true
          end
      puts x.tagged.show
      y = case 3
          when 3 then "str"
          end
      puts y.tagged.show
      puts 42.tagged.show
      puts nil.tagged.show
    RUBY

    _(result).must_answer <<~'OUT'
      tag(true)
      tag("str")
      tag(42)
      tag(nil)
    OUT
  end

  it "poly builtin arm container read" do
    result = ze0(<<~'RUBY')
      # The poly dispatch records what the BUILTIN surface alone would answer, to
      # shape its builtin arm. That re-derivation is defined as "if no user class
      # owned the name", but the helper it went through still took the union with a
      # user return -- so the recorded type came back poly and the builtin arm
      # assigned sp_poly_values()'s raw sp_PolyArray * into the boxed slot the user
      # arms need, and the C build stopped. It takes one user definition to see it.
      class Flash
        def initialize
          @h = { "a" => "b" }
        end

        def values = @h.values
        def keys = @h.keys
        def to_a = @h.to_a
      end

      def vals(x) = x.values
      def ks(x) = x.keys
      def entries(x) = x.to_a

      p vals(Flash.new)
      p vals({ a: 1 })
      p ks(Flash.new)
      p ks({ "c" => 2 })
      p entries(Flash.new)
      p entries({ "c" => 2 })
    RUBY

    _(result).must_answer <<~'OUT'
      ["b"]
      [1]
      ["a"]
      ["c"]
      [["a", "b"]]
      [["c", 2]]
    OUT
  end

  it "poly class dispatch" do
    result = ze0(<<~'RUBY')
      # poly.class — runtime dispatch on the sp_RbVal tag. Heterogeneous
      # array elements were previously emitting "0" through the
      # unresolved-call path.
      a = [1, "hello", 2.0, :sym, nil, true, false]
      puts a[0].class
      puts a[1].class
      puts a[2].class
      puts a[3].class
      puts a[4].class
      puts a[5].class
      puts a[6].class
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      String
      Float
      Symbol
      NilClass
      TrueClass
      FalseClass
    OUT
  end

  it "poly container delete" do
    result = ze0(<<~'RUBY')
      require 'set'

      # Array#delete on a poly (mixed-element) array: returns the deleted value,
      # or nil when the value is absent, and shrinks the array in place.
      class Marker
        def initialize(tag)
          @tag = tag
        end
      end

      m = Marker.new(1)
      arr = [1, "two", :three, m]
      p arr.delete("two")
      p arr.length
      p arr.delete(1)
      v = arr.delete(m)
      p v.nil?
      p arr.length
      p arr.delete(99)
      p arr.length

      # Hash#delete on a sym-keyed poly-valued hash: returns the value or nil.
      h = { alpha: 30, beta: "door", gamma: 2.5 }
      p h.delete(:beta)
      p h.key?(:beta)
      p h.delete(:missing)
      p h.length

      # Hash#delete on a poly-keyed poly-valued hash.
      ph = { 1 => "one", "two" => 2, :three => 30 }
      p ph.delete("two")
      p ph.key?("two")
      p ph.delete(9)
      p ph.length

      # Set#delete through the bundled stdlib package (array-backed).
      s = Set.new([1, "a", :b])
      s.delete("a")
      p s.include?("a")
      p s.size
      s.delete(99)
      p s.size
    RUBY

    _(result).must_answer <<~'OUT'
      "two"
      3
      1
      false
      1
      nil
      1
      "door"
      false
      nil
      2
      2
      false
      nil
      2
      false
      2
      2
    OUT
  end

  it "poly dispatch long class name" do
    result = ze0(<<~'RUBY')
      # The boxed receiver's cast is built into a fixed buffer that both the call and
      # g_self read. At 64 bytes a long class name truncated
      # `(sp_Long... *)_t2.v.p` to `..._t2.v`, and the C build stopped on an
      # identifier that does not exist. snprintf truncates silently, so nothing said
      # so until the generated C would not compile.

      class PolyDispatchReceiverWithAnExceedinglyLongClassNameForTheBuffer
        def initialize(n)
          @n = n
        end

        def size
          @n
        end

        def process(x)
          x + @n
        end
      end

      class AnotherPolyDispatchReceiverWhoseNameIsAlsoWellPastSixtyFourBytes
        def size
          2
        end

        def process(x)
          x * 2
        end
      end

      def sized(v) = v.size
      def run(v, x) = v.process(x)

      p sized(PolyDispatchReceiverWithAnExceedinglyLongClassNameForTheBuffer.new(7))
      p sized(AnotherPolyDispatchReceiverWhoseNameIsAlsoWellPastSixtyFourBytes.new)
      p sized([1, 2, 3])
      p run(PolyDispatchReceiverWithAnExceedinglyLongClassNameForTheBuffer.new(3), 4)
      p run(AnotherPolyDispatchReceiverWhoseNameIsAlsoWellPastSixtyFourBytes.new, 4)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      2
      3
      7
      8
    OUT
  end

  it "poly dispatch multilevel inheritance" do
    result = ze0(<<~'RUBY')
      # Three-level inheritance (Base -> Child -> GrandChild) plus a
      # Sibling. All inherit #greet from Base without overriding it.
      # Calling via a poly-typed parameter must dispatch correctly for
      # every level in the chain.

      class Base
        def greet
          "hello"
        end
      end

      class Child < Base
      end

      class GrandChild < Child
      end

      class Sibling < Base
      end

      def call_greet(e)
        e.greet
      end

      puts call_greet(Base.new)
      puts call_greet(Child.new)
      puts call_greet(GrandChild.new)
      puts call_greet(Sibling.new)
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      hello
      hello
      hello
    OUT
  end

  it "poly int bitops auto unify" do
    result = ze0(<<~'RUBY')
      # Same operator-site auto-unbox, but for bit operators (`<<`,
      # `>>`, `&`, `|`, `^`). int recv + poly arg previously failed C
      # compile; the poly arg is now unboxed via .v.i.

      # Heterogeneous poly_array of [user-class-with-[], IntArray] —
      # the outer `arr[i]` dispatch returns poly, then `[j]` on the
      # poly returns poly (since spinel statically types `[]` as poly).
      class Bits
        def [](i); [0xff, 0x0a, 0x10][i]; end
      end

      arr = [Bits.new, [0xff, 0x0a, 0x10]]

      # Each `arr[k][j]` is `int + poly` style: addr is int, the
      # heterogeneous dispatch result is statically poly.
      puts(1   << arr[1][1])     # 1 << 0x0a = 1024
      puts(0xf0 & arr[1][0])     # 0xf0 & 0xff = 0xf0 = 240
      puts(0x05 | arr[1][1])     # 0x05 | 0x0a = 0x0f = 15
      puts(0xff ^ arr[1][2])     # 0xff ^ 0x10 = 0xef = 239
      puts(arr[1][1] >> 1)       # 0x0a >> 1 = 5  (recv-poly + arg-int already routes to sp_poly_shr)
    RUBY

    _(result).must_answer <<~'OUT'
      1024
      240
      15
      239
      5
    OUT
  end

  it "poly merge arm" do
    result = ze0(<<~'RUBY')
      # A user class owning `merge` replaces the whole poly dispatch with its arms,
      # so a Hash arriving at the same call matched nothing and raised NoMethodError
      # naming its own class. And where that user arm was ALSO dropped because its
      # parameter is a concretely different hash kind, the switch came out EMPTY and
      # the call quietly answered the result temp's zero initializer (#4033).
      class Flash
        def merge(other)
          other.size
        end
      end

      def pick(f) = f ? {a: 1} : Flash.new

      p pick(true).merge(b: 2)
      p pick(true).merge({b: 2})
      p pick(false).merge({"x" => "y"})
      p pick(true).merge({a: 9})
      p pick(true).merge(b: 2, c: 3)

      # a hash whose keys are not symbols, through the same dispatch
      def pick2(f) = f ? {"a" => 1} : Flash.new
      p pick2(true).merge({"b" => 2})

      # and the ordinary typed receivers, unchanged
      p({a: 1}.merge(b: 2))
      p({"a" => 1}.merge({"b" => 2}))
      p Flash.new.merge({"a" => "b"})
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2}
      {a: 1, b: 2}
      1
      {a: 9}
      {a: 1, b: 2, c: 3}
      {"a" => 1, "b" => 2}
      {a: 1, b: 2}
      {"a" => 1, "b" => 2}
      1
    OUT
  end

  it "poly recv to i user" do
    result = ze0(<<~'RUBY')
      class Money
        def initialize(cents)
          @cents = cents
        end

        def to_i
          @cents
        end

        def to_f
          @cents / 100.0
        end
      end

      # a mixed poly container: the user conversion and the builtin one both answer
      [Money.new(250), 7, "9", 3.7].each do |v|
        p v.to_i
        p v.to_f
      end

      # a poly slot whose user method returns a value that outgrew Integer
      class Big
        def initialize(v)
          @v = v
        end

        def to_i
          @v & 0xFFFFFFFFFFFFFFFF
        end
      end

      def pick(f)
        f ? Big.new(-5) : nil
      end

      p pick(true).to_i
      p(-5 & 0xFFFFFFFFFFFFFFFF)
      p(-1 | 0xFFFFFFFFFFFFFFFF)
      p(-2 & (2**70 - 1))
      p "big=#{2**80}"
    RUBY

    _(result).must_answer <<~'OUT'
      250
      2.5
      7
      7.0
      9
      9.0
      3
      3.7
      18446744073709551611
      18446744073709551611
      -1
      1180591620717411303422
      "big=1208925819614629174706176"
    OUT
  end

  it "poly sym index with user aref" do
    result = ze0(<<~'RUBY')
      # Defining an instance `[]` must not drop the builtin Hash#[] case from the
      # polymorphic `[]` dispatch: a symbol-keyed Hash indexed through a poly (block
      # param) receiver was lowered to a cls_id switch built only from user `[]`
      # methods, so the Hash receiver fell through to nil. The dispatch must also
      # carry the SymPolyHash arm.
      class Box
        def [](key)
          nil
        end
      end

      pins = [{ name: "app", path: "/a.js" }, { name: "lib", path: "/b.js" }]
      pins.each { |p| puts p[:name] + " -> " + p[:path] }
      puts pins.map { |p| p[:name] }.join(",")

      # the user-defined [] still dispatches for a real Box receiver
      b = Box.new
      p b[:anything].nil?
    RUBY

    _(result).must_answer <<~'OUT'
      app -> /a.js
      lib -> /b.js
      app,lib
      true
    OUT
  end

  it "poly2" do
    result = ze0(<<~'RUBY')
      # Test Phase 2: heterogeneous arrays, bimorphic dispatch

      # Heterogeneous array
      arr = [1, "two", 3.0, true, nil]
      arr.each do |x|
        puts x
      end
      # 1, two, 3.0, true, (blank)

      # Array with mixed types
      nums = [10, 20, 30]
      puts nums.length  # 3

      # Duck typing (bimorphic)
      class Dog
        def speak
          "Woof!"
        end
      end

      class Cat
        def speak
          "Meow!"
        end
      end

      def make_noise(animal)
        puts animal.speak
      end

      make_noise(Dog.new)  # Woof!
      make_noise(Cat.new)  # Meow!

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1
      two
      3.0
      true

      3
      Woof!
      Meow!
      done
    OUT
  end

  it "reopening object defines methods reachable everywhere" do
    result = ze0(<<~'RUBY')
      # An Object reopen is top-level `def` by another name: its methods
      # land on arena slot 0, materialize into every user class, and
      # dispatch on the runtime `main` object at top-level call sites.

      class Object
        def double(x)
          x * 2
        end
      end
      puts double(21)
      class Widget
        def go
          double(4)
        end
      end
      puts Widget.new.go
    RUBY

    _(result).must_answer "42\n8\n"
  end

  it "self class cmethod dispatch" do
    result = ze0(<<~'RUBY')
      # `self.class.<class method>` from an instance method dispatches on the runtime
      # class, and that switch broke three ways at once. The base class's copy was
      # DCE'd as a transplanted source once a subclass got a specialization, though
      # the switch's default arm still calls it. An arm whose return type was not in a
      # hand-listed set of box functions -- a Symbol among them -- assigned its raw
      # value to the sp_RbVal result. And a class method widened to poly after the
      # fixpoint (its value is a class-level ivar that can be nil) left the method
      # returning the dispatch declared with the narrower type. (#4053)
      class Base
        def self.key(k = nil)
          @key = k if k
          @key
        end
        def key_from_instance = self.class.key
      end
      class A < Base; end

      A.key :a
      p A.key
      p A.new.key_from_instance
      p Base.new.key_from_instance

      # `class << self` reaches the same dispatch.
      class Ring
        class << self
          def slot(v = nil)
            @slot = v if v
            @slot
          end
        end
        def slot_from_instance = self.class.slot
      end
      class Ring2 < Ring; end
      Ring.slot :outer
      Ring2.slot :inner
      p Ring.new.slot_from_instance
      p Ring2.new.slot_from_instance

      # Arms that disagree on return type unify to poly, and each arm boxes its own.
      class Tag
        def self.label = :base
        def label_from_instance = self.class.label
      end
      class Tag2 < Tag
        def self.label = "sub"
      end
      p Tag.new.label_from_instance
      p Tag2.new.label_from_instance

      # Arms that agree on a non-poly scalar stay that type.
      class Kind
        def self.kind = :one
        def kind_of_self = self.class.kind
      end
      class Kind2 < Kind
        def self.kind = :two
      end
      p Kind.new.kind_of_self
      p Kind2.new.kind_of_self
    RUBY

    _(result).must_answer <<~'OUT'
      :a
      :a
      nil
      :outer
      :inner
      :base
      "sub"
      :one
      :two
    OUT
  end

  it "user class aset dispatch" do
    result = ze0(<<~'RUBY')
      # Issue #413. A class method `def []=(key, value)` that dispatches
      # on `key` and assigns into ivars of mixed types (Integer #@id,
      # String @name) emitted with the `[]=` body present in C but the
      # call site `f[:id] = 42` silently dropped — `compile_bracket_assign`
      # fell through every typed-array / hash arm and had no arm for a
      # user-class receiver, so the IndexAssignNode produced no output.
      #
      # Fix: add an `is_obj_type(rt)` arm at the end of
      # `compile_bracket_assign`. It looks the user class up via
      # `find_class_idx`, walks the inheritance chain via
      # `find_method_owner` for `"[]="`, and emits the typed dispatch
      # (`sp_<owner>__aset(recv, key, value)`) with arg boxing matched
      # to the method's declared param types via the existing
      # `compile_typed_call_args` helper. So a `value` param widened
      # to `sp_RbVal` (because the case branches assign to ivars of
      # different concrete types) takes a boxed rhs; a homogeneously-
      # typed param takes it raw.
      #
      # The accompanying `lv_value` parameter monomorphisation
      # concern from the issue body (the function signature was said
      # to commit `lv_value` to `mrb_int`) was already addressed by
      # unrelated inference passes by the time this fix landed — the
      # signature now correctly reads `sp_RbVal lv_value` for the
      # multi-type-ivar shape. The remaining gap was purely the
      # missing dispatch at the call site.
      #
      # Coverage:
      #   - Mixed-type ivars (`@id` int, `@name` string) — the
      #     canonical Rails-fixture shape from the issue's repro.
      #   - Homogeneous-type ivars to verify the dispatch still
      #     works through the simpler typed-param path.

      class Foo
        attr_reader :id, :name
        def initialize
          @id = 0
          @name = ""
        end
        def []=(key, value)
          case key
          when :id
            @id = value
          when :name
            @name = value
          end
        end
      end

      f = Foo.new
      f[:id] = 42
      f[:name] = "alice"
      puts f.id.to_s              # 42
      puts f.name                 # alice

      class Bag
        attr_reader :a, :b
        def initialize
          @a = 0
          @b = 0
        end
        def []=(key, value)
          case key
          when :a
            @a = value
          when :b
            @b = value
          end
        end
      end

      bg = Bag.new
      bg[:a] = 7
      bg[:b] = 11
      puts (bg.a + bg.b).to_s     # 18

    RUBY

    _(result).must_answer <<~'OUT'
      42
      alice
      18
    OUT
  end
end
