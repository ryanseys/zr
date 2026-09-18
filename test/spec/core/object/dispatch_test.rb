# frozen_string_literal: true

require "spec_helper"

describe "Object: dispatch" do
  it "or write ivar poly setter" do
    result = ze0(<<~'RUBY')
      class Flash2
        def hi; "hi"; end
      end
      class CtrlA
        def f=(v); @f = v; end
      end
      class CtrlB
        def f=(v); @f = v; end
      end
      class Harness
        def dispatch(c)
          c.f = @cache ||= Flash2.new
        end
        def run
          dispatch(CtrlA.new)
          dispatch(CtrlB.new)
          @cache
        end
      end
      r = Harness.new.run
      puts r.nil? ? "nil" : "ok: #{r.hi}"

      class CA
        def x=(v); @x = v; end
      end
      class CB
        def x=(v); @x = v; end
      end
      class H2
        def dispatch_arr(c); c.x = @arr ||= [1, 2, 3]; end
        def dispatch_hash(c); c.x = @h ||= {"a" => 1}; end
        def run
          dispatch_arr(CA.new)
          dispatch_arr(CB.new)
          dispatch_hash(CA.new)
          [@arr.length, @h.size]
        end
      end
      p H2.new.run
    RUBY

    _(result).must_answer "ok: hi\n[3, 1]\n"
  end

  it "poly dispatch value type to s" do
    result = ze0(<<~'RUBY')
      # A by-value (value-type) class defining #to_s: the synthesized poly to_s
      # dispatch arm must dereference the boxed pointer into the by-value self,
      # both when the class merely exists (compile) and when a boxed instance
      # actually flows through the dispatch (runtime).

      class Password
        def initialize(digest)
          @digest = digest.to_s
        end

        def to_s
          @digest
        end
      end

      class W
        def self.show(x)
          (x && "y").to_s
        end
      end

      puts W.show(1)
      puts W.show(nil)

      vals = [Password.new("abc"), "plain", 42]
      vals.each { |v| puts v.to_s }
      p (Password.new("z") && "w").to_s
      x = Password.new("boxed")
      p (x && x).to_s
    RUBY

    _(result).must_answer <<~'OUT'
      y

      abc
      plain
      42
      "w"
      "boxed"
    OUT
  end

  it "poly is a" do
    result = ze0(<<~'RUBY')
      # `<poly>.is_a?(Klass)` / `kind_of?` / `instance_of?` runtime
      # dispatch. Spinel previously fell through to user-class dispatch
      # only — the SP_TAG_INT / SP_TAG_STR / SP_TAG_FLT / SP_TAG_NIL /
      # SP_TAG_BOOL / SP_TAG_SYM / built-in Array / Hash / Range cases
      # were missing, so `is_a?(Integer)` against a poly slot always
      # returned false and downstream branches took the wrong arm. The
      # user-class dispatch also walked the wrong direction (recv->parent
      # instead of any-descendant->ancestor).
      #
      # Repro: a heterogeneous poly array yields each element back as
      # poly, then the type test routes it to the right branch. The
      # trailing Bar.new must select the `is_a?(Bar)` arm AND the
      # Foo.new before it must NOT match `is_a?(Bar)` (subclass-only).

      class Foo
        def name; "foo"; end
      end
      class Bar < Foo
        def name; "bar"; end
      end

      arr = [42, "hello", :sym, 1.5, nil, true, false, [1, 2], Foo.new, Bar.new]
      arr.each do |x|
        if x.is_a?(Integer)
          puts "Integer #{x}"
        elsif x.is_a?(String)
          puts "String #{x}"
        elsif x.is_a?(Symbol)
          puts "Symbol #{x.to_s}"
        elsif x.is_a?(Float)
          puts "Float"
        elsif x.is_a?(NilClass)
          puts "Nil"
        elsif x.is_a?(TrueClass)
          puts "True"
        elsif x.is_a?(FalseClass)
          puts "False"
        elsif x.is_a?(Array)
          puts "Array"
        elsif x.is_a?(Bar)
          puts "Bar"
        elsif x.is_a?(Foo)
          puts "Foo"
        else
          puts "?"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Integer 42
      String hello
      Symbol sym
      Float
      Nil
      True
      False
      Array
      Foo
      Bar
    OUT
  end

  it "poly object default render" do
    result = ze0(<<~'RUBY')
      # A bare Object (boxed with the builtin object class id) renders CRuby's
      # #<Object:0xADDR> through the poly to_s/inspect defaults (print/p paths).
      puts Object.new.to_s.gsub(/0x[0-9a-f]+/, "0xADDR")
      puts Object.new.inspect.gsub(/0x[0-9a-f]+/, "0xADDR")
    RUBY

    _(result).must_answer "#<Object:0xADDR>\n#<Object:0xADDR>\n"
  end

  it "poly to s user class" do
    result = ze0(<<~'RUBY')
      # A user class defining an instance `to_s`/`inspect` must not capture boxed
      # scalars in the polymorphic to_s/inspect dispatch. Every boxed scalar carries
      # cls_id 0, which aliased the first user class (index 0): a poly `value.to_s`
      # with a user class 0 defining `to_s` entered that class's method and
      # dereferenced the scalar's payload, segfaulting. Issue #1576.

      class Env
        def initialize(name)
          @name = name
        end

        def to_s
          @name
        end

        def inspect
          "#<Env #{@name}>"
        end
      end

      # `value` is untyped (called with mixed types -> poly); `.to_s` has no
      # statically-known receiver type, so it lowers to the class-id dispatch.
      def render(value)
        value.to_s
      end

      def show(value)
        value.inspect
      end

      # boxed scalars must fall through to the runtime poly converter, not Env
      puts render(42)             # 42
      puts render("hello")        # hello
      puts render(3.14)           # 3.14
      puts render(:sym)           # sym
      puts render(nil)            # (empty line)

      # the actual user object still dispatches to Env#to_s / #inspect
      puts render(Env.new("env")) # env
      puts show(Env.new("x"))     # #<Env x>

      # inspect over scalars routes through the poly converter too
      puts show(42)               # 42
      puts show("hi")             # "hi"
      puts show(:s)               # :s
    RUBY

    _(result).must_answer <<~'OUT'
      42
      hello
      3.14
      sym

      env
      #<Env x>
      42
      "hi"
      :s
    OUT
  end

  it "poly to sym" do
    result = ze0(<<~'RUBY')
      # x stays poly (called with String and Symbol), so #to_sym dispatches through
      # the poly-scalar runtime path rather than a concrete String/Symbol path.
      def as_sym(x) = x.to_sym

      p as_sym("hello")
      p as_sym(:already)
      p as_sym("with spaces")

      # map over a heterogeneous array whose elements are strings and symbols.
      p ["a", :b, "c", :d].map(&:to_sym)

      # a poly value that is neither String nor Symbol raises NoMethodError.
      def try_sym(x)
        x.to_sym
      rescue NoMethodError => e
        "NoMethodError: #{e.message}"
      end
      puts try_sym("ok")
      puts try_sym(42)
    RUBY

    _(result).must_answer <<~'OUT'
      :hello
      :already
      :"with spaces"
      [:a, :b, :c, :d]
      ok
      NoMethodError: undefined method 'to_sym' for an instance of Integer
    OUT
  end

  it "poly user binop object result" do
    result = ze0(<<~'RUBY')
      # A user operator with a POLY operand runs through the boxed arithmetic path,
      # but the fixpoint still settles the call's type on the class that defines it.
      # `(a % o).value` then read a field off an sp_RbVal.

      class Int64
        attr_reader :value
        def initialize(v); @value = v; end
        def +(other)
          Int64.new(@value + other.value)
        end
        def %(other)
          b = other.value
          return Int64.new(0) if b == 0
          Int64.new(@value % b)
        end
      end

      class Wrap
        attr_reader :value
        def initialize(v); @value = v; end
      end

      def pick(f, n)
        f ? Int64.new(n) : Wrap.new(n)
      end

      a = Int64.new(17)
      o = pick(true, 5)
      p (a % o).value
      p (a + o).value
    RUBY

    _(result).must_answer "2\n22\n"
  end

  it "poly user nil predicate" do
    result = ze0(<<~'RUBY')
      # A Null Object answers `nil?` with true, and its guard has to fire. The
      # poly-receiver arm folded `nil?` to the tag test without asking whether a user
      # class owns the name -- the arm directly below it skips for exactly that
      # reason, and this one did not. The user's method was never entered and
      # `return ... if u.nil?` silently did not fire.
      class NullUser
        def nil? = true
        def name = "(none)"
      end

      class RealUser
        def nil? = false
        def name = "matz"
      end

      def label(u)
        return "missing" if u.nil?
        u.name
      end

      p label(NullUser.new)
      p label(RealUser.new)
      p label(nil)

      def ask(v) = v.nil?

      p ask(NullUser.new)
      p ask(RealUser.new)
      p ask(nil)

      # a union with no real nil in it, which is where the fold was reached
      class Only
        def nil? = true
      end

      def ask2(v) = v.nil?
      p ask2(Only.new)
      p ask2([1])
      p ask2("s")

      # and with no user class defining it, the fold is what it always was
      def plain(v) = v.nil?
      p plain(nil)
      p plain(1)
      p plain("a")
      p plain([1])
    RUBY

    _(result).must_answer <<~'OUT'
      "missing"
      "matz"
      "missing"
      true
      false
      true
      true
      false
      false
      true
      false
      false
      false
    OUT
  end

  it "reopened freeze takes the ordinary dispatch" do
    result = ze0(<<~'RUBY')
      # A reopen of `String#freeze` takes the ordinary dispatch, so the
      # literal-freeze fold stands down.
      #
      # It lives in a file of its own because the gate is a WHOLE-PROGRAM fact:
      # zeo decides once per compile, where CRuby checks its redefinition flag when
      # the instruction runs. Putting this reopen at the foot of
      # `a_frozen_string_literal_is_not_deduplicated.rb` would therefore change
      # every probe above it, which is the divergence rather than the rule.
      #
      # The gate has to ask TWO questions. `runtime_patches` records a RUNTIME
      # redefinition -- `define_method(:freeze)` and friends -- and a compile-time
      # builtin reopen is NOT one, as `a_later_def_on_a_builtin_reaches_back`
      # records. Asking only the first kept the fold here and answered the literal
      # where ruby answers the reopened body: a silently wrong program, not a
      # slower one.
      class String
        def freeze = "reopened:#{self}"
      end
      p "lit".freeze
      p "lit".freeze.equal?("lit".freeze)
      p "other".freeze

      # The reopened body is an ordinary method, so `-@` is untouched by it.
      p (-"lit").equal?(-"lit")
      p (-"lit").frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      "reopened:lit"
      false
      "reopened:other"
      true
      true
    OUT
  end

  it "user defined dup override wins" do
    result = ze0(<<~'RUBY')
      # `dup`/`clone` are ordinary overridable Kernel methods in real Ruby --
      # the static arm must fall through to Path 1 dispatch when the
      # receiver's class defines its own.

      class W
        def dup
          "custom"
        end
      end

      puts W.new.dup
    RUBY

    _(result).must_answer "custom\n"
  end
end
