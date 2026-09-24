# frozen_string_literal: true

require "spec_helper"

describe "Methods: visibility" do
  it "issue module private instance methods" do
    result = zr(<<~'RUBY')
      # `private` inside a MODULE body did not reach the registry, in any of its
      # three forms. The same directives inside a CLASS body worked, which is what
      # made this look like a scope-frame problem -- it was not.
      #
      # A module declares its methods in `own_methods` (the collection that emits the
      # `__um_<id>` bridge container), while the registration loop's visibility pass
      # reads the materialized `methods` -- EMPTY for a module nothing includes. So
      # the mark went nowhere. It is now pushed where the method ROW is pushed, which
      # is the one place that can see a module's own methods.

      module BareDirective
        def a = 1

        private

        def b = 2
      end

      module WrappedDef
        def a = 1
        private def b = 2
      end

      module NamedAfter
        def a = 1
        def b = 2
        private :b
      end

      module ProtectedDirective
        def a = 1

        protected

        def b = 2
      end

      class ClassControl
        def a = 1

        private

        def b = 2
      end

      [BareDirective, WrappedDef, NamedAfter, ProtectedDirective, ClassControl].each do |m|
        puts m.to_s
        p m.instance_methods(false).sort
        p m.private_instance_methods(false).sort
        p m.protected_instance_methods(false).sort
        p [m.private_method_defined?(:b), m.protected_method_defined?(:b), m.method_defined?(:b)]
      end

      # The mark has to survive into an INCLUDER, which is why declaring it on a
      # module matters at all.
      class Host
        include BareDirective
      end
      p Host.new.a
      p Host.private_method_defined?(:b)
      p Host.new.respond_to?(:b)
      p Host.new.respond_to?(:b, true)
      begin
        Host.new.b
      rescue NoMethodError => e
        puts e.message
      end
      p Host.new.send(:b)
    RUBY

    _(result).must_answer <<~'OUT'
      BareDirective
      [:a]
      [:b]
      []
      [true, false, false]
      WrappedDef
      [:a]
      [:b]
      []
      [true, false, false]
      NamedAfter
      [:a]
      [:b]
      []
      [true, false, false]
      ProtectedDirective
      [:a, :b]
      []
      [:b]
      [false, true, true]
      ClassControl
      [:a]
      [:b]
      []
      [true, false, false]
      1
      true
      false
      true
      private method 'b' called for an instance of Host
      2
    OUT
  end

  it "issue private class method def" do
    result = zr(<<~'RUBY')
      # `private_class_method def helper ...` under a `module_function` directive
      # registers the def: `private_class_method` takes the def's symbol as an
      # argument, and the def itself defines the method as usual. zeo does not model
      # class-method VISIBILITY (tests/gaps/class_method_visibility.rb), so the
      # helper stays callable -- what this pins is that it EXISTS.
      module M
        module_function

        def pub
          helper * 2
        end

        private_class_method def helper
          21
        end
      end

      p M.pub
    RUBY

    _(result).must_answer "42\n"
  end

  it "module function dead method dce" do
    result = zr(<<~'RUBY')
      # A named-module_function method that no in-unit call site reaches
      # (even via a chain of other uncalled module functions) is dead-code-
      # eliminated, so its body — which may use unimplemented dynamic
      # patterns — doesn't break compilation. A *called* module function
      # still works. Regression for #1062.
      module M
        # uncalled; body builds from a variable-held class (dynamic .new)
        def fail_with(*args)
          klass = args.shift
          e = klass.new(*args)
          e.set_backtrace([])
          e
        end
        module_function :fail_with

        # uncalled, but calls the above (chain) — both must be dead
        def boom(*args)
          fail_with(*args)
        end
        module_function :boom

        # CALLED — must stay live and work
        def greet(name)
          "hi " + name
        end
        module_function :greet
      end
      puts M.greet("world")
      puts(2 + 3)
    RUBY

    _(result).must_answer "hi world\n5\n"
  end

  it "module function governs a runtime define method" do
    result = zr(<<~'RUBY')
      # A bare `module_function` is a MODE: every definition after it in the body
      # becomes both a module method and a private instance copy. Zeo resolves
      # that cursor at compile time, which reaches a `def` and reaches the block
      # form of `define_method` (it desugars to a `def`) -- but a
      # `define_method(:name, <a callable>)` installs at RUN time, where the
      # compile-time cursor cannot follow it.
      #
      # This is rack's shape, and the reason `Rack::Utils.escape_html` was
      # missing: `define_method(:escape_html, ERB::Escape.instance_method(:html_escape))`
      # under a bare `module_function`.
      module Src
        def html_escape(s) = "esc(#{s})"
      end
      shout = ->(s) { "lam(#{s})" }

      module U
        module_function

        def plain(s) = "plain(#{s})"

        define_method(:blk) { |s| "blk(#{s})" }
        define_method(:unbound, Src.instance_method(:html_escape))
        define_method(:lambda_arg, ->(s) { "lam(#{s})" })
        define_method("string_name", ->(s) { "str(#{s})" })

        # rack's own shape: the definition sits in a BRANCH of the module body,
        # so the mode has to reach it there too.
        if defined?(Src) && Src.instance_method(:html_escape)
          define_method(:in_a_branch, Src.instance_method(:html_escape))
        else
          def in_a_branch(s) = "fallback(#{s})"
        end
      end

      %i[plain blk unbound lambda_arg string_name in_a_branch].each do |m|
        puts U.public_send(m, "x")
      end

      # Both halves, in ruby's own reporting: the module method is public, the
      # instance copy private.
      p U.instance_methods(false).sort
      p U.private_instance_methods(false).sort
      p U.singleton_methods(false).sort

      # The instance copy is what an `include` mixes in, private and all.
      class Host
        include U
        def use(s) = unbound(s)
      end
      puts Host.new.use("y")
      begin
        Host.new.unbound("z")
      rescue NoMethodError => e
        puts e.message
      end

      # Without the mode, a run-time define_method stays a public instance
      # method and nothing is promoted.
      module Plain
        define_method(:only_instance, ->(s) { s })
      end
      p Plain.instance_methods(false)
      p Plain.singleton_methods(false)
    RUBY

    _(result).must_answer <<~'OUT'
      plain(x)
      blk(x)
      esc(x)
      lam(x)
      str(x)
      esc(x)
      []
      [:blk, :in_a_branch, :lambda_arg, :plain, :string_name, :unbound]
      [:blk, :in_a_branch, :lambda_arg, :plain, :string_name, :unbound]
      esc(y)
      private method 'unbound' called for an instance of Host
      [:only_instance]
      []
    OUT
  end

  it "operator assignment through self calls private methods" do
    result = zr(<<~'RUBY')
      # An operator assignment through a literal `self` may call private
      # readers, writers, `[]` and `[]=`, as a plain `self.x = v` may.
      class Counter
        def bump = (self.count += 1; count)
        def seed = (self.count ||= 5; count)
        def slot = (self[0] ||= :v; self[0])
        def add = (self[1] += 2; self[1])

        private

        attr_accessor :count

        def [](i) = @h[i]

        def []=(i, v)
          @h[i] = v
        end

        def initialize
          @count = 1
          @h = {1 => 1}
        end
      end
      c = Counter.new
      p c.bump, Counter.new.seed, c.slot, c.add
      begin
        c.count += 1
      rescue NoMethodError => e
        p e.message
      end

    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      :v
      3
      "private method 'count' called for an instance of Counter"
    OUT
  end

  it "private def idiom and retroactive private by name" do
    result = zr(<<~'RUBY')
      class A
        def pub_a
          priv_a
        end

        private def priv_a
          "priv_a"
        end
      end

      class B
        def pub_b
          priv_b
        end

        def priv_b
          "priv_b"
        end

        private :priv_b
      end

      puts A.new.pub_a
      puts B.new.pub_b
    RUBY

    _(result).must_answer "priv_a\npriv_b\n"
  end

  it "protected method callable from a related classs own method" do
    result = zr(<<~'RUBY')
      class Money
        def initialize(amount)
          @amount = amount
        end

        def greater_than_five
          other = Money.new(5)
          amount > other.amount
        end

        protected

        def amount
          @amount
        end
      end

      puts Money.new(10).greater_than_five
    RUBY

    _(result).must_answer "true\n"
  end

  it "public method" do
    result = zr(<<~'RUBY')
      m = "hello".public_method(:upcase)
      p m.call
      class C; def foo(x); x*3; end; end
      p C.new.public_method(:foo).call(4)
    RUBY

    _(result).must_answer <<~'OUT'
      "HELLO"
      12
    OUT
  end

  it "toplevel method runtime name" do
    result = zr(<<~'RUBY')
      # A top-level method is emitted as sp_<name>, which is the runtime's own
      # namespace. The mangler carries an rb_ infix for names that would land in it,
      # but it only looked at the segment in front of an underscore -- so `def sym_x`
      # was protected while `def sym` collided with the sp_sym TYPEDEF and the
      # program failed to build on a C diagnostic that never named `sym`.
      def sym(v) = "sym:#{v}"
      def int(v) = "int:#{v}"
      def float(v) = "float:#{v}"
      def queue(v) = "queue:#{v}"
      def thread(v) = "thread:#{v}"
      def argv(v) = "argv:#{v}"
      def fmod(v) = "fmod:#{v}"
      def safepoint(v) = "safepoint:#{v}"
      def sym_x(v) = "sym_x:#{v}"
      def plain(v) = "plain:#{v}"

      p sym(1)
      p int(2)
      p float(3)
      p queue(4)
      p thread(5)
      p argv(6)
      p fmod(7)
      p safepoint(8)
      p sym_x(9)
      p plain(10)

      # names the list did not carry: a bare runtime function is just as much a
      # collision as a runtime typedef, and `gcd` / `gets` / `readlines` are names a
      # program writes without a second thought
      def gcd(a, b) = "gcd:#{a}:#{b}"
      def lcm(a, b) = "lcm:#{a}:#{b}"
      def gets(v) = "gets:#{v}"
      def readlines(v) = "readlines:#{v}"
      def bool(v) = "bool:#{v}"
      def mutex(v) = "mutex:#{v}"
      def backtick(v) = "backtick:#{v}"
      def idiv(a, b) = "idiv:#{a}:#{b}"

      p gcd(1, 2)
      p lcm(3, 4)
      p gets(5)
      p readlines(6)
      p bool(7)
      p mutex(8)
      p backtick(9)
      p idiv(10, 11)

      # names only the generated set carries: the reserved set is read from the
      # runtime sources now, so a name that exists there is covered whether or not
      # anyone remembered to list it
      def ceildiv(a, b) = "ceildiv:#{a}:#{b}"
      def powmod(v) = "powmod:#{v}"
      def unsentinel(v) = "unsentinel:#{v}"
      def condvar(v) = "condvar:#{v}"

      p ceildiv(1, 2)
      p powmod(3)
      p unsentinel(4)
      p condvar(5)

      # an infixed name and a user name that already spells the infix stay apart
      def rb_sym(v) = "rb_sym:#{v}"
      p sym(90)
      p rb_sym(91)

      # and the mangling does not leak into Ruby: the names still call each other
      def outer(v) = sym(v) + "/" + int(v)
      p outer(11)
    RUBY

    _(result).must_answer <<~'OUT'
      "sym:1"
      "int:2"
      "float:3"
      "queue:4"
      "thread:5"
      "argv:6"
      "fmod:7"
      "safepoint:8"
      "sym_x:9"
      "plain:10"
      "gcd:1:2"
      "lcm:3:4"
      "gets:5"
      "readlines:6"
      "bool:7"
      "mutex:8"
      "backtick:9"
      "idiv:10:11"
      "ceildiv:1:2"
      "powmod:3"
      "unsentinel:4"
      "condvar:5"
      "sym:90"
      "rb_sym:91"
      "sym:11/int:11"
    OUT
  end

  it "visibility keywords switch the default for subsequent defs" do
    result = zr(<<~'RUBY')
      # A bare `private`/`public` switches the DEFAULT visibility for every
      # subsequent `def` in the class body (see
      # `parse::lower_class_body_statement`'s docs) -- this test only checks
      # that a PUBLIC method compiles/runs normally after a `private` section;
      # see the dedicated visibility-enforcement tests below for the actual
      # private/protected/public_send rejection cases.

      class Box
        def initialize
          @x = 1
        end
        private
        def helper
          2
        end
        public
        def x
          @x
        end
      end
      puts Box.new.x
    RUBY

    _(result).must_answer "1\n"
  end
end
