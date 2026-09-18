# frozen_string_literal: true

require "spec_helper"

describe "Methods: searching and matching" do
  it "anonymous rest and keyword rest are values" do
    result = ze0(<<~'RUBY')
      # A bare `*` or `**` stands for the anonymous rest parameters wherever
      # a splat can: in an array literal and as an index.
      def m(*) = [*]
      p m(1, 2), m

      def n(*) = (h = {k: 1}; h[*] += 1; h)
      p n(:k)

      def o(**) = [**]
      p o, o(a: 1)

      def mixed(*, **) = [0, *, **]
      p mixed(1, b: 2), mixed

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      []
      {k: 2}
      []
      [{a: 1}]
      [0, 1, {b: 2}]
      [0]
    OUT
  end

  it "class method additions" do
    result = ze0(<<~'RUBY')
      # A batch of builtin class/instance methods: the `Hash[]` constructor,
      # `Array`/`Hash.try_convert`, `Complex.polar`, `Module#include?`, and
      # `Regexp.last_match`.

      # Hash[] -- the class constructor (distinct from the instance Hash#[]).
      p Hash[]
      p Hash[1, 2, 3, 4]
      p Hash[[[:a, 1], [:b, 2]]]
      p Hash[{ x: 1, y: 2 }]

      # try_convert -- the arg if already the type, its to_ary/to_hash, else nil.
      p Array.try_convert([1, 2, 3])
      p Array.try_convert("not an array")
      p Hash.try_convert({ a: 1 })
      p Hash.try_convert(5)

      # Complex.polar(abs, arg) -- the polar constructor.
      p Complex.polar(2, 0)

      # Module#include? -- true only for an included MODULE in the ancestry.
      module Greetable; end
      class Person
        include Greetable
      end
      p Person.include?(Greetable)
      p Person.include?(Comparable)
      begin
        Person.include?(Object)
      rescue TypeError => e
        puts e.message
      end

      # Regexp.last_match -- the thread-local $~ and its capture groups.
      "abc123" =~ /([a-z]+)(\d+)/
      p Regexp.last_match(1)
      p Regexp.last_match(2)
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      {1 => 2, 3 => 4}
      {a: 1, b: 2}
      {x: 1, y: 2}
      [1, 2, 3]
      nil
      {a: 1}
      nil
      (2+0.0i)
      true
      false
      wrong argument type Class (expected Module)
      "abc"
      "123"
    OUT
  end

  it "codegen const lookup in toplevel method" do
    result = ze0(<<~'RUBY')
      # Regression for the `String#index` nil-guard in
      # `current_lexical_scope_name`. A toplevel `def show` body that
      # reads a CONSTANT routes through `resolve_const_read_name`, which
      # calls `current_lexical_scope_name`. Inside that helper,
      # `@current_method_name.index("_cls_")` looks for the class-method
      # name marker — for a toplevel def the marker isn't present, so
      # CRuby's `String#index` returns nil while spinel's runtime
      # returns -1. The pre-fix `if cls_idx >= 0` crashed on the CRuby
      # path with `NoMethodError: undefined method '>=' for nil`.

      FOO = 42
      def show; puts FOO; end
      show
    RUBY

    _(result).must_answer "42\n"
  end

  it "find ifnone" do
    result = ze0(<<~'RUBY')
      # find/detect with an ifnone proc: called only when no element matches;
      # a match (including a nil element) ignores it. The result carries whatever
      # the proc returns.
      def f_int(a) = a.find(-> { -1 }) { |x| x > 10 }
      p f_int([1, 2, 3])
      p f_int([1, 20, 3])

      def f_str(a) = a.detect(-> { "none" }) { |s| s.start_with?("z") }
      p f_str(["ab", "cd"])
      p f_str(["ab", "zx"])

      def f_poly(a) = a.find(-> { :missing }) { |x| x == 42 }
      p f_poly([1, "two", :three])
      p f_poly([1, 42, "three"])

      def f_nil_ret(a) = a.find(-> { nil }) { |x| x > 99 }
      p f_nil_ret([1, 2])

      def f_nil_elem(a) = a.find(-> { :fallback }) { |x| x.nil? }
      p f_nil_elem([1, nil, 3])

      ifnone_ran = 0
      counter = -> { ifnone_ran += 1; :ran }
      p [5, 6].find(counter) { |x| x > 5 }
      p ifnone_ran
      p [5, 6].find(counter) { |x| x > 9 }
      p ifnone_ran

      def f_raise(a)
        a.find(-> { raise ArgumentError, "empty search" }) { |x| x > 9 }
      rescue => e
        "#{e.class}: #{e.message}"
      end
      p f_raise([1, 2])
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      20
      "none"
      "zx"
      :missing
      42
      nil
      nil
      6
      0
      :ran
      1
      "ArgumentError: empty search"
    OUT
  end

  it "Operator-write (`a[i] OP= v`)" do
    result = ze0(<<~'RUBY')
      # Indexed-slot compound writes — `a[i] OP= v`, `a[i] &&= v`,
      # `a[i] ||= v`, `a[i], b[j] = ...`. Was four tests; merged here.
      # The op_assign section's `class Vec` is unique; locals reused
      # across the originals (`xs`, `counts`, etc.) get per-section
      # prefixes so the merged script's type inference doesn't unify
      # them or carry hash content across sections.

      class Vec
        attr_accessor :data
        def initialize(n)
          @data = Array.new(n, 0.5)
        end
      end


      # Float / Int / hash receivers, both directly and through an
      # object field. IndexOperatorWriteNode is distinct from a `.[]=`
      # call; without the dedicated codegen the update is dropped.

      vop1 = Vec.new(4)
      vop1.data[0] += 1.5
      vop1.data[1] -= 0.5
      vop1.data[2] *= 4.5
      vop1.data[3] /= 0.5
      puts vop1.data[0]   # 2  (spinel strips ".0")
      puts vop1.data[1]   # 0
      puts vop1.data[2]   # 2.25
      puts vop1.data[3]   # 1

      ints_op = Array.new(3, 10)
      ints_op[0] += 5
      ints_op[1] -= 3
      ints_op[2] *= 2
      puts ints_op[0]     # 15
      puts ints_op[1]     # 7
      puts ints_op[2]     # 20

      counts_op = {"a" => 1, "b" => 2}
      counts_op["a"] += 10
      counts_op["b"] += 20
      puts counts_op["a"] # 11
      puts counts_op["b"] # 22

      # Same pattern through a method call on an object: `obj.attr[i] += x`.
      vop2 = Vec.new(3)
      iop = 0
      while iop < 3
        vop2.data[iop] += 0.25
        iop += 1
      end
      puts vop2.data[0]   # 0.75
      puts vop2.data[1]   # 0.75
      puts vop2.data[2]   # 0.75
    RUBY

    _(result).must_answer <<~'OUT'
      2.0
      0.0
      2.25
      1.0
      15
      7
      20
      11
      22
      0.75
      0.75
      0.75
    OUT
  end

  it "And-write (`a[i] &&= v`)" do
    result = ze0(<<~'RUBY')
      # Indexed-slot compound writes — `a[i] OP= v`, `a[i] &&= v`,
      # `a[i] ||= v`, `a[i], b[j] = ...`. Was four tests; merged here.
      # The op_assign section's `class Vec` is unique; locals reused
      # across the originals (`xs`, `counts`, etc.) get per-section
      # prefixes so the merged script's type inference doesn't unify
      # them or carry hash content across sections.

      class Vec
        attr_accessor :data
        def initialize(n)
          @data = Array.new(n, 0.5)
        end
      end


      # Reads a[i]; if truthy, sets a[i] = v. Stick to non-zero values
      # so the C-truthy semantic agrees with Ruby's truthy semantic.
      xs_aw = [1, 2, 3, 4, 5]
      xs_aw[0] &&= 10              # truthy -> fires
      xs_aw[2] &&= 30              # truthy -> fires
      xs_aw[4] &&= xs_aw[4] * 100  # truthy -> fires; recv/idx evaluated once
      puts xs_aw[0]                # 10
      puts xs_aw[1]                # 2
      puts xs_aw[2]                # 30
      puts xs_aw[3]                # 4
      puts xs_aw[4]                # 500

      counts_aw = {"alice" => 30, "bob" => 25}
      counts_aw["alice"] &&= 31    # truthy -> fires
      counts_aw["carol"] &&= 50    # unset (returns 0) -> doesn't fire
      puts counts_aw["alice"]      # 31
      puts counts_aw["bob"]        # 25
      puts counts_aw.length        # 2 (carol not added)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      2
      30
      4
      500
      31
      25
      2
    OUT
  end

  it "Or-write (`a[i] ||= v`)" do
    result = ze0(<<~'RUBY')
      # Indexed-slot compound writes — `a[i] OP= v`, `a[i] &&= v`,
      # `a[i] ||= v`, `a[i], b[j] = ...`. Was four tests; merged here.
      # The op_assign section's `class Vec` is unique; locals reused
      # across the originals (`xs`, `counts`, etc.) get per-section
      # prefixes so the merged script's type inference doesn't unify
      # them or carry hash content across sections.

      class Vec
        attr_accessor :data
        def initialize(n)
          @data = Array.new(n, 0.5)
        end
      end


      # Reads a[i]; if falsy, sets a[i] = v. Receiver and index are
      # evaluated exactly once even though the source has them on both
      # sides of the implicit `a[i] = a[i] || v`.
      counts_or = {"alice" => 0, "bob" => 5}
      counts_or["carol"] ||= 10    # never set -> fires
      counts_or["bob"]   ||= 99    # 5 truthy -> no-op
      puts counts_or["alice"]      # 0
      puts counts_or["bob"]        # 5
      puts counts_or["carol"]      # 10
    RUBY

    _(result).must_answer <<~'OUT'
      0
      5
      10
    OUT
  end

  it "Target (multi-assign LHS into indexed slots)" do
    result = ze0(<<~'RUBY')
      # Indexed-slot compound writes — `a[i] OP= v`, `a[i] &&= v`,
      # `a[i] ||= v`, `a[i], b[j] = ...`. Was four tests; merged here.
      # The op_assign section's `class Vec` is unique; locals reused
      # across the originals (`xs`, `counts`, etc.) get per-section
      # prefixes so the merged script's type inference doesn't unify
      # them or carry hash content across sections.

      class Vec
        attr_accessor :data
        def initialize(n)
          @data = Array.new(n, 0.5)
        end
      end


      # `a[0], b[1] = 1, 2` -- each LHS slot is an IndexTargetNode.
      xs_t = [10, 20, 30]
      ys_t = [100, 200, 300]
      xs_t[0], ys_t[2] = 1, 999
      puts xs_t[0]                 # 1
      puts xs_t[1]                 # 20
      puts ys_t[2]                 # 999

      # Same-array two-slot swap.
      zs_t = [1, 2, 3, 4, 5]
      zs_t[0], zs_t[4] = zs_t[4], zs_t[0]
      puts zs_t[0]                 # 5
      puts zs_t[4]                 # 1

      # Hash slot mixed with array slot in one multi-assign.
      counts_t = {"a" => 0, "b" => 0}
      arr_t = [0, 0, 0]
      counts_t["a"], arr_t[1] = 42, 99
      puts counts_t["a"]           # 42
      puts arr_t[1]                # 99
    RUBY

    _(result).must_answer <<~'OUT'
      1
      20
      999
      5
      1
      42
      99
    OUT
  end

  it "method visibility reflection" do
    result = ze0(<<~'RUBY')
      # Visibility is not only a call-time gate: `respond_to?`, `singleton_methods`
      # and the `*_instance_methods` family all report it, and code branches on what
      # they say. Three places where zeo enforced the gate but recorded nothing.

      puts "-- Module's own directives are private methods of Module"
      p Module.private_instance_methods(false).sort &
        %i[private public protected module_function remove_const ruby2_keywords included extended prepended]
      p Class.private_instance_methods(false) & [:inherited]

      class C; end
      %i[private public protected module_function remove_const ruby2_keywords inherited].each do |m|
        begin
          C.public_send(m)
          puts "C.#{m}: answered"
        rescue NoMethodError
          puts "C.#{m}: NoMethodError"
        rescue ArgumentError
          puts "C.#{m}: ArgumentError"
        end
      end

      puts "-- a singleton class sees them with Module's visibility"
      p C.singleton_class.method_defined?(:private)
      p C.singleton_class.private_method_defined?(:private)
      p C.singleton_class.method_defined?(:name)

      puts "-- while the class-body directives still work (implicit self)"
      class D
        def a = 1
        private
        def b = 2
        public
        def c = 3
      end
      p [D.new.a, D.new.c]
      begin
        D.new.b
      rescue NoMethodError
        puts "D#b is private"
      end

      puts "-- private inside `class << self`, on a user module"
      module UserMod
        class << self
          def pub = 1
          private
          def hid = 2
        end
      end
      p UserMod.respond_to?(:hid)
      p UserMod.singleton_methods(false).sort
      p UserMod.singleton_class.private_instance_methods(false).sort
      begin
        UserMod.hid
      rescue NoMethodError
        puts "UserMod.hid: NoMethodError"
      end

      puts "-- and on a REOPENED BUILTIN, which recorded nothing at all"
      module Comparable
        class << self
          def cmp_pub = 1
          private
          def cmp_hid = 2
        end
      end
      p Comparable.respond_to?(:cmp_hid)
      p Comparable.singleton_class.private_instance_methods(false).include?(:cmp_hid)
      p Comparable.cmp_pub
      begin
        Comparable.cmp_hid
      rescue NoMethodError
        puts "Comparable.cmp_hid: NoMethodError"
      end

      puts "-- private_class_method, both spellings"
      class E
        private_class_method def self.mk = 1
        def self.pub = 2
      end
      p E.singleton_methods(false).sort
      p E.respond_to?(:mk)
      p E.singleton_class.private_instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      -- Module's own directives are private methods of Module
      [:extended, :included, :module_function, :prepended, :private, :protected, :public, :remove_const, :ruby2_keywords]
      [:inherited]
      C.private: NoMethodError
      C.public: NoMethodError
      C.protected: NoMethodError
      C.module_function: NoMethodError
      C.remove_const: NoMethodError
      C.ruby2_keywords: NoMethodError
      C.inherited: NoMethodError
      -- a singleton class sees them with Module's visibility
      false
      true
      true
      -- while the class-body directives still work (implicit self)
      [1, 3]
      D#b is private
      -- private inside `class << self`, on a user module
      false
      [:pub]
      [:hid]
      UserMod.hid: NoMethodError
      -- and on a REOPENED BUILTIN, which recorded nothing at all
      false
      true
      1
      Comparable.cmp_hid: NoMethodError
      -- private_class_method, both spellings
      [:pub]
      false
      [:mk]
    OUT
  end

  it "primitive method shadow" do
    result = ze0(<<~'RUBY')
      # Issue #302: a user-defined class method whose name matches a
      # primitive method (e.g. `String#index`) used to shadow the primitive
      # during caller-side type inference. `def find_bracket(s); s.index("[");
      # end` walked s's body, found `index` is defined on user-class
      # StringIndexer, and committed s's param type to obj_StringIndexer —
      # even though the call site passed a string and `index` is a primitive
      # String method.
      #
      # Fix: extend `called_methods_only_on_container_builtins` to also
      # accept the methods shared across String / Hash / Integer, so
      # `def index` / `def show` / `def create` etc. on user classes can
      # coexist with primitive callers.

      class StringIndexer
        def index(needle, start = 0)
          "from-StringIndexer"
        end
      end

      def find_bracket(s)
        s.index("[")
      end
      puts find_bracket("hello[world]")    # 5

      # String method that's also defined on a controller-shaped class.
      class ArticlesController
        def show
          "ArticlesController#show"
        end
      end

      def first_or_default(s)
        s.start_with?("/")    # String#start_with? — should not be shadowed
      end
      puts first_or_default("/articles")    # true
      puts first_or_default("articles")     # false

      # Hash-shared `keys` shouldn't pull a user-class param into obj_X.
      class KeyHolder
        def keys
          ["alpha", "beta"]
        end
      end

      def count_keys(h)
        h.keys.length
      end
      puts count_keys({a: 1, b: 2, c: 3})   # 3
    RUBY

    _(result).must_answer <<~'OUT'
      5
      true
      false
      3
    OUT
  end

  it "primitive method shadow int recv" do
    result = ze0(<<~'RUBY')
      # Issue #305: follow-up to #302's primitive-shadow fix.
      #
      # #302 stopped the body-side param-type inference from committing
      # a param to a user class when the called methods are also defined
      # on a primitive type (`def find_bracket(s); s.index("[")` no
      # longer pins `s` as obj_StringIndexer when the only call site
      # passes a string literal).
      #
      # But the *emit-time* int-recv fallback (`compile_int_class_fallback
      # _expr`) still walked every user class and picked the first one
      # whose method-name matched. When the receiver flowed in as
      # `mrb_int` (e.g. unpinned param, IntArray-of-pointer fallback),
      # the fallback would route `raw_key.index("[")` to
      # `ArticlesController#index` regardless of the receiver's actual
      # nature.
      #
      # Fix: when `mname` is a primitive-shared method AND any user class
      # defines it, refuse the int-to-class cast and let the unresolved-
      # call diagnostic fire. The shape happens to compile to a `0`
      # placeholder for the call's result — that's the existing fallback
      # contract for genuinely unresolvable calls; it's vastly better
      # than the silent miscompile that picked a random user class.

      class ArticlesController
        def index
          "controller-action"
        end
      end

      # A param with no upstream pinning. Spinel defaults the param to
      # mrb_int when no call site supplies a non-int. Without the fix,
      # the body's `.index` call hits compile_int_class_fallback_expr,
      # which walks the user-class table and picks ArticlesController
      # (the first class defining `def index`), emitting a typed cast
      # `((sp_ArticlesController *)raw_key)->index_get(...)` that is
      # either a C-compile error or a silent miscompile. With the fix,
      # the int-recv fallback refuses primitive-shared method names and
      # the call lowers to the unresolved-call placeholder (literal 0).
      #
      # We don't call `find_first` from Ruby — defining it is enough for
      # spinel to emit and type-check the body, and avoiding the call
      # keeps MRI happy (Integer#index doesn't exist).
      def find_first(raw_key)
        raw_key.index("[")
      end

      puts "compiled-cleanly"
    RUBY

    _(result).must_answer "compiled-cleanly\n"
  end

  it "reflection asks and answers as ruby does" do
    result = ze0(<<~'RUBY')
      def try = yield rescue [$!.class, $!.message]

      # respond_to? passes include_all on, and lets the hook's error out.
      class RM
        def respond_to_missing?(m, all) = (p [:asked, m, all]; m == :ghost)
      end
      p RM.new.respond_to?(:ghost), RM.new.respond_to?(:ghost, true)
      class Boom
        def respond_to_missing?(m, all) = raise("boom")
      end
      p try { Boom.new.respond_to?(:x) }

      # Two define_method bodies are two methods.
      class DM
        define_method(:a) { 1 }
        define_method(:b) { 2 }
      end
      d = DM.new
      p d.method(:a) == d.method(:b), d.method(:a) == d.method(:a)

      p Object.private_instance_methods.include?(:initialize_dup), Object.private_instance_methods.include?(:initialize_clone)

      # Object#=== is identity first.
      o = Object.new
      def o.==(x) = false
      p Object.instance_method(:===).bind_call(o, o)

      p try { 1.instance_of?(1) }
      p try { Object.include?(1) }

      # The top of the chain has no super method.
      def dbl(n) = n * 2
      p method(:dbl).super_method
      p 1.method(:+).super_method

    RUBY

    _(result).must_answer <<~'OUT'
      [:asked, :ghost, false]
      [:asked, :ghost, true]
      true
      true
      [RuntimeError, "boom"]
      false
      true
      true
      true
      true
      [TypeError, "class or module required"]
      [TypeError, "wrong argument type Integer (expected Module)"]
      nil
      nil
    OUT
  end

  it "runtime directive without arguments takes effect" do
    result = ze0(<<~'RUBY')
      # The argument-less runtime directives, forced through string `eval` so no
      # compile-time resolution helps: a bare `private` switches the body default,
      # a bare `module_function` switches the mode, and `include` on a compiled
      # class splices the overlay ancestry. Each once read as a documented no-op
      # in `runtime_meta/api.rs`; this golden keeps the docs honest.
      puts "-- bare private via string eval --"
      class Foo; end
      eval(["Foo.class_eval do", "  private", "  def hidden = 'h'", "end"].join("\n"))
      p Foo.private_method_defined?(:hidden)
      begin
        Foo.new.hidden
      rescue NoMethodError
        puts "NoMethodError"
      end

      puts "-- bare module_function via string eval --"
      module M; end
      eval(["M.module_eval do", "  module_function", "  def helper = 'help'", "end"].join("\n"))
      p M.respond_to?(:helper)
      p M.helper
      p M.private_instance_methods.include?(:helper)

      puts "-- runtime include on a compiled class via string eval --"
      module Extra
        def extra = "extra"
      end
      class Compiled
        def base = "base"
      end
      eval(["Compiled", ".include(Extra)"].join(""))
      p Compiled.include?(Extra)
      p Compiled.ancestors.include?(Extra)
      begin
        p Compiled.new.extra
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      -- bare private via string eval --
      true
      NoMethodError
      -- bare module_function via string eval --
      true
      "help"
      true
      -- runtime include on a compiled class via string eval --
      true
      true
      "extra"
    OUT
  end

  it "splat builtin predicate family" do
    result = ze0(<<~'RUBY')
      # the predicate/search builtins take their argument as a scalar, so an
      # unexpanded splat answered from a comparison against the array pointer
      x001 = ["b"]
      p("abc".include?(*x001))

      x002 = ["a"]
      p("abc".start_with?(*x002))

      x003 = ["c"]
      p("abc".end_with?(*x003))

      x004 = ["b"]
      p("abc".index(*x004))

      x005 = ["b"]
      p("abc".count(*x005))

      x006 = ["-"]
      p("a-b".split(*x006))

      x007 = ["-"]
      p([1, 2].join(*x007))

      x008 = [1]
      p({ a: 1 }.value?(*x008))

      x009 = ["a", "z"]
      p("abc".tr(*x009))

      # the key predicates aborted the compile: the splat array reached the slot
      # expecting one key
      k001 = [:a]
      p({ a: 1 }.key?(*k001))

      k002 = [:a]
      p({ a: 1 }.has_key?(*k002))

      k003 = [:a]
      p({ a: 1 }.include?(*k003))

      k004 = [:a]
      p({ a: 1 }.member?(*k004))

      x010 = [3]
      p([1, 2, 3].include?(*x010))

      x011 = [2]
      p([1, 2, 3].index(*x011))

      x012 = ["b"]
      p("abc".rindex(*x012))

      # a length only the run time knows: the splat arrives as a parameter
      def f005(keys)
        { a: 1 }.fetch(*keys)
      end
      p f005([:a])

      def f006(keys)
        h = { a: 1 }
        h.delete(*keys)
        h
      end
      p f006([:a])

      def f007(keys)
        { a: 1 }[*keys]
      end
      p f007([:a])

      def f008(idx)
        [1, 2].fetch(*idx)
      end
      p f008([0])

      def f009(idx)
        [1, 2][*idx]
      end
      p f009([0])

      def f010(args)
        "abc".sub(*args)
      end
      p f010(["a", "z"])

      def f011(args)
        "abc".delete(*args)
      end
      p f011(["b"])

      def f012(sep)
        "a-b-c".split(*sep)
      end
      p f012(["-"])

      def f013(needle)
        "abc".include?(*needle)
      end
      p f013(["b"])

      def f014(keys)
        { a: 1 }.key?(*keys)
      end
      p f014([:a])

      # a user method of the same name still reads the array into its own params
      class Bag
        def initialize(items)
          @items = items
        end

        def index(a, b)
          a + b
        end
      end
      p Bag.new([1]).index(*[3, 4])

      # the variadic builtins keep taking the array as it stands
      p [1, 2, 3].values_at(*[0, 2])
      p [1, 2, 3].dig(*[0])
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      1
      1
      ["a", "b"]
      "1-2"
      true
      "zbc"
      true
      true
      true
      true
      true
      1
      1
      1
      {}
      1
      1
      1
      "zbc"
      "ac"
      ["a", "b", "c"]
      true
      true
      7
      [1, 3]
      1
    OUT
  end

  it "splat index" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # A `*` splat in the index of `g[...] += v` makes the index count unknown
      # at compile time, so both halves of the pair spread ONE saved Array
      # rather than a slot array. The index is built once, so a side-effecting
      # one runs the number of times it is written.

      class Grid
        def initialize = @cells = {}
        def [](*at) = @cells[at]

        def []=(*at, value)
          @cells[at] = value
        end
        def to_s = @cells.inspect
      end

      g = Grid.new
      g[1, 2] = 7
      p g[*[1, 2]]

      built = 0
      coords = lambda do
        built += 1
        [3, 4]
      end
      g[3, 4] = 0
      g[*coords.call] += 10
      g[*[3, 4]] += 1
      p g[3, 4]
      p built

      g[*[5, 6]] ||= :fresh
      g[*[5, 6]] ||= :later
      p g[5, 6]

      g[*[7, 8]], g[9] = "x", "y"
      p [g[7, 8], g[9]]

      h = { [1] => :one }
      h[*[[1]]] &&= :changed
      p h

      # The setter's own answer is not the assignment's: a multiple assignment
      # answers the right-hand side.
      class Loud
        attr_reader :seen
        def initialize = @seen = []
        def []=(k, v)
          @seen << k
          :ignored
        end
      end
      loud = Loud.new
      p((loud[:a], loud[:b] = 1, 2))
      p loud.seen
    RUBY

    _(result).must_answer <<~'OUT'
      7
      11
      1
      :fresh
      ["x", "y"]
      {[1] => :changed}
      [1, 2]
      [:a, :b]
    OUT
  end

  it "values at splat" do
    result = ze0(<<~'RUBY')
      # values_at with a splatted array expands each element as a separate
      # key/index (#3277).
      a = [10, 20, 30, 40, 50]
      idx = [1, 3]
      p a.values_at(*idx)
      p a.values_at(0, *idx, 4)
      p a.values_at(*[])

      h = { "a" => 1, "b" => 2, "c" => 3 }
      keys = ["a", "c"]
      p h.values_at(*keys)
      p h.values_at("a", *["b", "c"])
      p h.values_at(*["x", "a"])

      sh = { one: 10, two: 20 }
      p sh.values_at(*[:two, :one])

      pa = [1, "two", :three, 4.0]
      p pa.values_at(*[1, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      [20, 40]
      [10, 20, 40, 50]
      []
      [1, 3]
      [1, 2, 3]
      [nil, 1]
      [20, 10]
      ["two", 4.0]
    OUT
  end
end
