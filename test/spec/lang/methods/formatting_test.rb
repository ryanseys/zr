# frozen_string_literal: true

require "spec_helper"

describe "Methods: formatting and inspection" do
  it "class method knows its own name" do
    result = ze0(<<~'RUBY')
      # `__method__` answers the BARE method name, whichever way the method was
      # defined.
      #
      # zeo read it off the backtrace label and stripped only the `#` separator, so
      # an instance method answered `:name` and a class method answered `:"Owner.name"`.
      #
      # What that breaks is `to_enum(__method__, ...)` -- the standard way a method
      # hands back an enumerator over itself. The enumerator named a method that does
      # not exist, so re-entering it raised NoMethodError. rubygems' vendored
      # `Gem::TSort.tsort` is written exactly that way, so no gem could be resolved.

      module M
        def self.plain = __method__
        def dup_name = __method__
        def self.dup_name = __method__
      end

      class C
        def self.klass = __method__
        def inst = __method__
        class << self
          def in_sclass = __method__
        end
      end

      def top_level = __method__

      puts "module singleton\t#{M.plain.inspect}"
      puts "module both, class\t#{M.dup_name.inspect}"
      puts "class singleton\t#{C.klass.inspect}"
      puts "instance\t#{C.new.inst.inspect}"
      puts "class << self\t#{C.in_sclass.inspect}"
      puts "top level\t#{top_level.inspect}"
      puts "through Method\t#{M.method(:plain).call.inspect}"

      # The idiom that made it matter.
      module Walker
        def self.each_pair(a, b)
          return to_enum(__method__, a, b) unless block_given?

          yield a
          yield b
        end
      end

      puts "to_enum\t#{Walker.each_pair(1, 2).to_a.inspect}"
      puts "with block\t#{Walker.each_pair(3, 4) { |x| }.inspect}"

      # A method with a same-named instance twin still names itself, not its twin.
      module Twin
        def go = "instance"

        def self.go
          return to_enum(__method__) unless block_given?

          yield :singleton
        end
      end
      puts "twin\t#{Twin.go.to_a.inspect}"

      # `__callee__` answers the name it was REACHED through. The ALIAS half of that
      # is a separate divergence and lives in
      # tests/gaps/a_singleton_alias_reports_the_name_it_was_called_by.rb.
      class Aliased
        def self.original = __callee__
      end
      puts "callee original\t#{Aliased.original.inspect}"
    RUBY

    _(result).must_answer <<~'OUT'
      module singleton	:plain
      module both, class	:dup_name
      class singleton	:klass
      instance	:inst
      class << self	:in_sclass
      top level	:top_level
      through Method	:plain
      to_enum	[1, 2]
      with block	nil
      twin	[:singleton]
      callee original	:original
    OUT
  end

  it "double splat kwargs" do
    result = ze0(<<~'RUBY')
      # `def f(a, **kwargs)` binds extra keyword args into a sym_poly_hash.
      def test(a, **kwargs)
        puts a
        puts kwargs.inspect
      end

      test(1, b: 2, c: 3)

      # Just kwargs (no positionals)
      def only_kw(**opts)
        puts opts.inspect
      end

      only_kw(x: 10, y: 20)

      # No keyword args at the call site -> empty hash
      only_kw

      # Mix of explicit keyword + kwrest: explicit gets bound, leftover
      # goes to kwargs.
      def mixed(a, b:, **rest)
        puts "a=#{a} b=#{b}"
        puts rest.inspect
      end

      mixed(1, b: 2, c: 3, d: 4)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      {b: 2, c: 3}
      {x: 10, y: 20}
      {}
      a=1 b=2
      {c: 3, d: 4}
    OUT
  end

  it "double splat nil" do
    result = ze0(<<~'RUBY')
      # `**nil` in a call is ruby's "pass no keywords" spelling -- a no-op, both as
      # a literal and through a nil-valued variable. zeo lowers every `**expr` splat
      # through a to-Hash conversion, so it raises TypeError ("no implicit
      # conversion of nil into Hash") before the call happens.
      def kw(a, b: 2, **rest)
        [a, b, rest]
      end

      puts kw(1, **nil).inspect
      h = nil
      puts kw(2, **h).inspect
    RUBY

    _(result).must_answer "[1, 2, {}]\n[2, 2, {}]\n"
  end

  it "empty method returns nil" do
    result = ze0(<<~'RUBY')
      # An empty method body implicitly returns nil.
      def f; end
      puts f.nil?
      def g
      end
      x = g
      puts x.nil?
      puts f.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      nil
    OUT
  end

  it "explicit receiver visibility" do
    result = ze0(<<~'RUBY')
      # Ruby decides visibility from the SHAPE of the call, not from the value the
      # receiver holds. `vm_call_method` runs no check at all for an implicit
      # receiver, for the literal `self` keyword, or for `send` (all FCALL); every
      # other explicit receiver is checked.
      #
      # zeo enforced that only where the receiver's class was known at compile time.
      # A dynamic call skipped it entirely, so `1.puts("x")` printed, `"ab".initialize`
      # answered nil, and a private method reached through a local that merely HELD
      # self went through.

      def try(label)
        v = yield
        puts "#{label} => #{v.inspect}"
      rescue NoMethodError => e
        puts "#{label} !! #{e.class}: #{e.message}"
      end

      class R
        def on_self = self.helper
        def bare = helper

        # A local holding `self` is an ordinary explicit receiver. Only the `self`
        # KEYWORD is exempt, which is why this one raises and `on_self` does not.
        def through_local
          me = self
          me.helper
        end

        def on_other(o) = o.helper
        private def helper = :helped
      end

      try("R.new.on_self") { R.new.on_self }
      try("R.new.bare") { R.new.bare }
      try("R.new.through_local") { R.new.through_local }
      try("R.new.on_other(R.new)") { R.new.on_other(R.new) }
      try("R.new.helper") { R.new.helper }
      try("R.new.send(:helper)") { R.new.send(:helper) }
      try("R.new.__send__(:helper)") { R.new.__send__(:helper) }
      try("R.new.public_send(:helper)") { R.new.public_send(:helper) }
      try("R.new.respond_to?(:helper)") { R.new.respond_to?(:helper) }
      try("R.new.respond_to?(:helper, true)") { R.new.respond_to?(:helper, true) }

      # `protected` is the receiver-sensitive one: reachable when the CALLER's self
      # is a kind of the method's owner, whoever the receiver is.
      class Money
        def >(other) = amount > other.amount
        protected def amount = 7
      end
      class Cash < Money; end
      class Outsider
        def peek(m) = m.amount
      end

      try("Money.new > Money.new") { Money.new > Money.new }
      try("Money.new > Cash.new") { Money.new > Cash.new }
      try("Cash.new > Money.new") { Cash.new > Money.new }
      try("Outsider.new.peek(Money.new)") { Outsider.new.peek(Money.new) }
      try("Money.new.amount") { Money.new.amount }
      try("Money.new.send(:amount)") { Money.new.send(:amount) }
      try("Money.new.public_send(:amount)") { Money.new.public_send(:amount) }

      # The builtin rows answer the same way -- Kernel's methods are private, on
      # every receiver, whatever its class.
      try("1.puts") { 1.puts("x") }
      try("'ab'.puts") { "ab".puts("x") }
      try("nil.puts") { nil.puts("x") }
      try("[].raise") { [].raise("boom") }
      try("'ab'.initialize") { "ab".initialize }
      try("[].initialize") { [].initialize }
      try("Object.new.initialize") { Object.new.initialize }
      try("RuntimeError.new.initialize") { RuntimeError.new.initialize }
      try("3.7.require") { 3.7.require("set") }

      # A class method the class actually provides is the one that answers, so a
      # same-named private Kernel method further down cannot reach past it. `open`
      # is the case that matters: `File.open` is File's own public singleton method,
      # while `Kernel#open` is private.
      try("File.respond_to?(:open)") { File.respond_to?(:open) }
      try("String.name") { String.name }
      try("Integer.instance_methods.class") { Integer.instance_methods.class }

      # A private CLASS method is checked the same way.
      class Factory
        def self.build = :built
        def self.make_via_self = self.build
        private_class_method :build
      end
      try("Factory.make_via_self") { Factory.make_via_self }
      try("Factory.build") { Factory.build }
      try("Factory.send(:build)") { Factory.send(:build) }

      # Visibility changed after the fact is a RUNTIME property, so a site that
      # dispatches dynamically has to see the change. (A site whose receiver class is
      # known at compile time answers from the compile-time table instead -- see
      # tests/gaps/runtime_private_on_typed_receiver.rb.)
      class Late
        def open_now = :open
      end
      try("Late#open_now before") { Late.new.open_now }
      Late.send(:private, :open_now)
      try("Late#open_now after") { [Late.new].first.open_now }
    RUBY

    _(result).must_answer <<~'OUT'
      R.new.on_self => :helped
      R.new.bare => :helped
      R.new.through_local !! NoMethodError: private method 'helper' called for an instance of R
      R.new.on_other(R.new) !! NoMethodError: private method 'helper' called for an instance of R
      R.new.helper !! NoMethodError: private method 'helper' called for an instance of R
      R.new.send(:helper) => :helped
      R.new.__send__(:helper) => :helped
      R.new.public_send(:helper) !! NoMethodError: private method 'helper' called for an instance of R
      R.new.respond_to?(:helper) => false
      R.new.respond_to?(:helper, true) => true
      Money.new > Money.new => false
      Money.new > Cash.new => false
      Cash.new > Money.new => false
      Outsider.new.peek(Money.new) !! NoMethodError: protected method 'amount' called for an instance of Money
      Money.new.amount !! NoMethodError: protected method 'amount' called for an instance of Money
      Money.new.send(:amount) => 7
      Money.new.public_send(:amount) !! NoMethodError: protected method 'amount' called for an instance of Money
      1.puts !! NoMethodError: private method 'puts' called for an instance of Integer
      'ab'.puts !! NoMethodError: private method 'puts' called for an instance of String
      nil.puts !! NoMethodError: private method 'puts' called for nil
      [].raise !! NoMethodError: private method 'raise' called for an instance of Array
      'ab'.initialize !! NoMethodError: private method 'initialize' called for an instance of String
      [].initialize !! NoMethodError: private method 'initialize' called for an instance of Array
      Object.new.initialize !! NoMethodError: private method 'initialize' called for an instance of Object
      RuntimeError.new.initialize !! NoMethodError: private method 'initialize' called for an instance of RuntimeError
      3.7.require !! NoMethodError: private method 'require' called for an instance of Float
      File.respond_to?(:open) => true
      String.name => "String"
      Integer.instance_methods.class => Array
      Factory.make_via_self => :built
      Factory.build !! NoMethodError: private method 'build' called for class Factory
      Factory.send(:build) => :built
      Late#open_now before => :open
      Late#open_now after !! NoMethodError: private method 'open_now' called for an instance of Late
    OUT
  end

  it "extended class method keeps its visibility" do
    result = ze0(<<~'RUBY')
      # `SomeClass.extend(M)` copies M's instance methods in as CLASS methods and
      # loses their visibility marks -- the class-receiver twin of
      # `an_extended_module_keeps_its_visibility`.
      #
      # `extend_object_default`'s `RubyValue::Class` arm (`runtime_meta/api.rs`)
      # writes `entry.class_methods` and `entry.extended_class_methods` and nothing
      # else. The class-method visibility map (`class_methods_vis`) is left alone, so
      # a `module_function` name -- private on the module's instance side -- arrives
      # public on the class's singleton.
      #
      # The per-object arm carries the marks; this one does not.

      def try(label)
        p [label, yield]
      rescue NoMethodError, NameError => e
        p [label, :raised, e.class.to_s]
      end

      module MFc
        module_function
        def helper = :helper
      end
      class KD; end
      KD.extend(MFc)
      try(:dot)      { KD.helper }
      try(:public)   { KD.public_send(:helper) }
      try(:send)     { KD.send(:helper) }
      try(:singles)  { KD.singleton_methods }
      try(:respond)  { KD.respond_to?(:helper) }

      module M1
        def m = :m
        private :m
      end
      class C2; end
      C2.extend(M1)
      try(:m_dot)    { C2.m }
      try(:m_public) { C2.public_send(:m) }
      try(:m_singles){ C2.singleton_methods }
      try(:m_priv)   { C2.singleton_class.private_instance_methods(false) }

      # A public row still arrives public, and an own `def self.x` beside it is
      # untouched.
      module M2
        def pub2 = :pub2
      end
      class C3
        extend M2
        def self.own = :own
      end
      try(:pub_dot)  { C3.pub2 }
      try(:own_dot)  { C3.own }
      try(:c3_sing)  { C3.singleton_methods.sort }
    RUBY

    _(result).must_answer <<~'OUT'
      [:dot, :raised, "NoMethodError"]
      [:public, :raised, "NoMethodError"]
      [:send, :helper]
      [:singles, []]
      [:respond, false]
      [:m_dot, :raised, "NoMethodError"]
      [:m_public, :raised, "NoMethodError"]
      [:m_singles, []]
      [:m_priv, []]
      [:pub_dot, :pub2]
      [:own_dot, :own]
      [:c3_sing, [:own, :pub2]]
    OUT
  end

  it "generic sends" do
    result = ze0(<<~'RUBY')
      puts 10.to_s
      puts 10.to_s(2)
      puts 3.7.floor
      puts 3.2.ceil
      puts -5.abs
      puts 10.gcd(4)
      puts 255.to_s(16)
      puts 5.between?(1, 10)
      puts 1.zero?
      puts 7.even?
      puts 7.odd?
      p 3.14.round
      p 10.divmod(3)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      1010
      3
      4
      5
      2
      ff
      true
      false
      false
      true
      3
      [3, 1]
    OUT
  end

  it "instance methods false" do
    result = ze0(<<~'RUBY')
      # `Klass.instance_methods(false)` const-folds to a literal symbol array
      # of the class/module's own (non-inherited) instance methods. The set
      # matches method_defined?(name, false): the method table plus attr
      # readers and `=`-suffixed writers. The set is public + protected;
      # private defs are excluded (matching CRuby). The no-arg / `true` forms
      # stay unfolded.
      class Foo
        attr_reader :r
        attr_writer :w
        attr_accessor :rw
        def hello; end
        def world(a, b); end
        private
        def secret; end
      end

      ms = Foo.instance_methods(false)
      puts ms.class
      puts ms.include?(:hello)
      puts ms.include?(:world)
      puts ms.include?(:r)
      puts ms.include?(:w=)
      puts ms.include?(:rw)
      puts ms.include?(:rw=)
      puts ms.include?(:secret)
      puts ms.include?(:nope)

      module M
        def self.a; end
        def b; end
        def c(x); end
      end

      mm = M.instance_methods(false)
      puts mm.include?(:b)
      puts mm.include?(:c)
      puts mm.include?(:a)
      puts mm.length

      class Empty
      end
      puts Empty.instance_methods(false).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      Array
      true
      true
      true
      true
      true
      true
      false
      false
      true
      true
      false
      2
      []
    OUT
  end

  it "instance methods false chain" do
    result = ze0(<<~'RUBY')
      # Module#/Class#instance_methods(false) returns a real (boxed) poly array of
      # symbols, so chained operations like `.map(&:to_s).sort` iterate it correctly
      # instead of treating an opaque sym-array box as empty.

      module M
        def after_commit_hook; end
        def execute_after_commit; end
      end
      p M.instance_methods(false).map(&:to_s).sort

      class C
        def m1; end
        def m2; end
        attr_reader :r
      end
      p C.instance_methods(false).map(&:to_s).sort
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      ["after_commit_hook", "execute_after_commit"]
      ["m1", "m2", "r"]
      done
    OUT
  end

  it "isa self in base method" do
    result = ze0(<<~'RUBY')
      # `is_a?` on a receiver whose static type is a BASE class. That type is only an
      # upper bound -- a Base-typed slot legitimately holds a Sub, which is the whole
      # point of a subclass -- so the test has to read the object's runtime class.
      # It read the static one, so a predicate written on the base class answered
      # false for every subclass instance, silently, while the identical test written
      # at the call site answered true because there the receiver's type IS Sub.
      #
      # The downstream shape is Rails single-table inheritance, where the predicates
      # live on the base class by construction (#4142).
      class Base
        def inside = self.is_a?(Sub)
        def implicit = is_a?(Sub)
        def exact = instance_of?(Sub)
        def own = is_a?(Base)
      end

      class Sub < Base
      end

      class Deeper < Sub
      end

      b = Sub.new
      p b.inside
      p b.implicit
      p b.exact
      p b.own
      p b.is_a?(Sub)
      p b.is_a?(Base)

      p Base.new.inside
      p Base.new.own
      p Base.new.exact

      # Through the grandparent, and exact-vs-ancestor at each level.
      d = Deeper.new
      p [d.inside, d.exact, d.own]
      p [d.is_a?(Deeper), d.is_a?(Sub), d.is_a?(Base), d.instance_of?(Sub)]

      # A collection typed by the base, dispatching per element -- the STI shape.
      rooms = [Base.new, Sub.new, Deeper.new]
      p rooms.map { |r| r.inside }
      p rooms.map { |r| r.class.to_s }

      # A leaf class with no subclasses keeps the exact answer.
      class Alone
        def me = is_a?(Alone)
      end
      p Alone.new.me

      # The shape this arrived as: Rails single-table inheritance, where the
      # predicates live on the base class by construction and the subclasses are
      # declared after it. Every one of them answered false for every room -- a
      # well-formed page with the wrong content, and no error anywhere.
      class Room
        def open?   = is_a?(Rooms::Open)
        def closed? = is_a?(Rooms::Closed)
        def label = open? ? "open" : (closed? ? "closed" : "plain")
      end

      module Rooms
        class Open < Room; end
        class Closed < Room; end
      end

      rooms = [Rooms::Open.new, Rooms::Closed.new, Room.new]
      p rooms.map { |r| r.label }
      p rooms.map { |r| [r.open?, r.closed?] }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      false
      true
      false
      [true, false, true]
      [true, true, true, false]
      [false, true, true]
      ["Base", "Sub", "Deeper"]
      true
      ["open", "closed", "plain"]
      [[true, false], [false, true], [false, false]]
    OUT
  end

  it "keyword given flag does not travel" do
    result = ze0(<<~'RUBY')
      # Ruby distinguishes "the caller wrote keywords" from "the caller passed a
      # Hash" -- `rb_keyword_given_p`. zeo collapses both into a trailing
      # `RubyValue::Hash` positional the moment a call leaves the static path, so
      # every callee that asks the question gets the wrong answer.
      #
      # Two call shapes leave that path: a `**h` double-splat (always dispatched
      # dynamically -- see `codegen::call::splat`) and `send`. A LITERAL keyword at a
      # statically-resolved site keeps the distinction and already answers correctly,
      # which is the control in each pair below.
      #
      # `**nil` is the sharpest reader of the flag, since refusing keywords is its
      # whole purpose (`tests/keywords_refused_message.rb` covers the literal form
      # that works). `tests/gaps/struct_construction_argument_shapes.rb` is the same
      # root cause reached through `Struct.new`, which decides member binding from
      # the argument shape because the flag never arrives.
      #
      # An EMPTY `**{}` passes no keywords at all, so it must stay silent -- that is
      # the line separating this from a shape-only test.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue ArgumentError => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      def nokw(a, **nil) = a
      def nokw_splat(*a, **nil) = a

      # The literal form keeps the flag -- already correct.
      show("literal kw") { nokw(1, b: 2) }
      show("literal, rest") { nokw_splat(1, b: 2) }

      # A `**h` splat loses it.
      show("splat kw") { h = { b: 2 }; nokw(1, **h) }
      show("splat kw, rest") { h = { b: 2 }; nokw_splat(1, **h) }

      # `send` loses it.
      show("send kw") { send(:nokw, 1, b: 2) }

      # A real positional Hash must keep working, and an empty splat passes nothing.
      show("positional hash") { nokw({ b: 2 }) }
      show("rest positional hash") { nokw_splat(1, { b: 2 }) }
      show("empty splat") { h = {}; nokw(1, **h) }
    RUBY

    _(result).must_answer <<~'OUT'
      literal kw: ArgumentError: no keywords accepted
      literal, rest: ArgumentError: no keywords accepted
      splat kw: ArgumentError: no keywords accepted
      splat kw, rest: ArgumentError: no keywords accepted
      send kw: ArgumentError: no keywords accepted
      positional hash: {b: 2}
      rest positional hash: [1, {b: 2}]
      empty splat: 1
    OUT
  end

  it "kwarg back propagate callee type" do
    result = ze0(<<~'RUBY')
      # #561 (Sam Ruby). Kwarg passthrough back-propagation: when
      # method outer forwards `inner(name: lvar)` and inner's
      # `name:` is typed (default value or body usage), outer's
      # matching kwarg should pick up the callee's slot type
      # rather than defaulting to int. Pre-fix outer.s stayed int
      # and the C compile failed at the int -> const char *
      # coercion at the inner call site.
      #
      # This mirrors the positional callee_slot back-propagation
      # pass but keyed on kwarg name rather than position; the
      # kwarg path also accepts any concrete callee type
      # (string / int_array / hash variant / etc.) rather than
      # just ptr / obj.

      module Broadcasts
        def self.append(stream:, target:, html:)
          record(action: :append, stream: stream, target: target, html: html)
        end

        def self.record(action:, stream:, target:, html:)
          out = action.to_s + "|" + stream + "|" + target + "|len=" + html.length.to_s
          out
        end
      end

      puts Broadcasts.append(stream: "s", target: "t", html: "<div>")
    RUBY

    _(result).must_answer "append|s|t|len=5\n"
  end

  it "kwarg only call leading optional" do
    result = ze0(<<~'RUBY')
      # The whole-program shape: NO call site anywhere supplies the leading optional
      # positionally, so it stays poly, and the fallthrough handed it the keyword
      # hash -- which the declared keyword had already consumed, binding it twice
      # (#3525). A companion call passing the positional immunises this, which is
      # why the eleven shapes in kwarg_with_omitted_leading_optional.rb could not
      # fail: they share a file with calls that rescue them. One shape per file.
      class A
        def self.f(a = nil, k: :default)
          "a=#{a.inspect} k=#{k.inspect}"
        end
      end
      puts A.f(k: 1)
    RUBY

    _(result).must_answer "a=nil k=1\n"
  end

  it "kwarg only instance leading optional" do
    result = ze0(<<~'RUBY')
      # One shape per file: a companion call that supplies the positional would
      # immunise this (#3525).
      class B
        def f(a = nil, k: :default)
          "a=#{a.inspect} k=#{k.inspect}"
        end
      end
      puts B.new.f(k: 1)
    RUBY

    _(result).must_answer "a=nil k=1\n"
  end

  it "kwarg only two leading optionals" do
    result = ze0(<<~'RUBY')
      # One shape per file: a companion call that supplies the positional would
      # immunise this (#3525).
      class C
        def self.f(a = nil, b = nil, k: :default)
          "a=#{a.inspect} b=#{b.inspect} k=#{k.inspect}"
        end
      end
      puts C.f(k: 1)
    RUBY

    _(result).must_answer "a=nil b=nil k=1\n"
  end

  it "kwarg with omitted leading optional" do
    result = ze0(<<~'RUBY')
      # A keyword argument supplied while a leading optional positional is omitted:
      # the keyword hash must NOT also land in the positional slot (#3525).
      class A
        def self.f(a = nil, k: :default)
          "a=#{a.inspect} k=#{k.inspect}"
        end
      end
      puts A.f(k: 1)
      puts A.f(9, k: 1)
      puts A.f
      puts A.f(9)

      # instance method, same shape
      class B
        def f(a = nil, k: :default)
          "a=#{a.inspect} k=#{k.inspect}"
        end
      end
      puts B.new.f(k: 1)
      puts B.new.f(9, k: 1)

      # two leading optionals
      class C
        def self.f(a = nil, b = nil, k: :default)
          "a=#{a.inspect} b=#{b.inspect} k=#{k.inspect}"
        end
      end
      puts C.f(k: 1)
      puts C.f(7, k: 1)
      puts C.f(7, 8, k: 1)

      # a trailing required after the optional, with a keyword
      class D
        def self.f(a = nil, r, k: :default)
          "a=#{a.inspect} r=#{r.inspect} k=#{k.inspect}"
        end
      end
      puts D.f(5, k: 1)
      puts D.f(4, 5, k: 1)
    RUBY

    _(result).must_answer <<~'OUT'
      a=nil k=1
      a=9 k=1
      a=nil k=:default
      a=9 k=:default
      a=nil k=1
      a=9 k=1
      a=nil b=nil k=1
      a=7 b=nil k=1
      a=7 b=8 k=1
      a=nil r=5 k=1
      a=4 r=5 k=1
    OUT
  end

  it "kwargs param" do
    result = ze0(<<~'RUBY')
      # KeywordRestParameterNode -- def f(**kw)
      #
      # Declares a method that captures all keyword arguments into a single
      # sym_poly_hash slot. The full body-access path (kw[:key], kw.length)
      # is deferred until a real program needs it; this test verifies the declaration
      # alone compiles and the existing **nil form still works.
      #
      # Forwarding usage (**kw → another method's **kw slot) is exercised by
      # test/forwarding_args.rb, which routes through cluster A3 + B1.

      # Declaration compiles; body never reads kw, so no kwargs runtime path
      # is needed. Validates that adding the param slot doesn't break
      # bootstrap or alter the C signature for callers that don't pass kwargs.
      def silent(a, **kw)
        a + 1
      end
      puts silent(2).to_s   #=> 3

      # `def f(**nil)` is the explicit "rejects keyword args" form.
      # Verifies the existing NoKeywordsParameterNode handling still works
      # after the parser's PARAMETERS_NODE flattener gained the keyword_rest
      # emission (cluster A1).
      def strict(a, b, **nil)
        a + b
      end
      puts strict(2, 3).to_s   #=> 5
    RUBY

    _(result).must_answer "3\n5\n"
  end

  it "kwrest does not fill optional" do
    result = ze0(<<~'RUBY')
      # A method taking `**kwrest` takes every keyword the call passed, so none of
      # them is a positional hash argument: the keywords-only call used to bind the
      # hash to the optional positional as well, and `event.nil?` answered false
      # (#3808).
      def inner(event = nil, **filters)
        puts "nil?=#{event.nil?} keys=#{filters.keys.inspect}"
      end
      inner(key_down: :escape)
      inner(:sym, key_down: :escape)
      inner(nil, key_down: :escape)
      def on(event = nil, **filters)
        if event.nil?
          "keywords"
        else
          "positional #{event.inspect}"
        end
      end
      puts on(key_down: :escape)
      puts on(:quit)
    RUBY

    _(result).must_answer <<~'OUT'
      nil?=true keys=[:key_down]
      nil?=false keys=[:key_down]
      nil?=true keys=[:key_down]
      keywords
      positional :quit
    OUT
  end

  it "kwrest does not type optional" do
    result = ze0(<<~'RUBY')
      def a(x = nil, **kw)
        puts "x=#{x.inspect} kw=#{kw.inspect}"
      end

      a(k: 1)
      a
      a(7)
      a({ h: 3 }, k: 4)

      def b(x = :none, **kw)
        puts "b x=#{x.inspect} kw=#{kw.inspect}"
      end

      b(z: 9)
      b

      def c(x = nil, **kw)
        if x
          puts "c truthy #{x}"
        else
          puts "c falsy #{x.inspect}"
        end
      end

      c(q: 2)
      c("here")
    RUBY

    _(result).must_answer <<~'OUT'
      x=nil kw={k: 1}
      x=nil kw={}
      x=7 kw={}
      x={h: 3} kw={k: 4}
      b x=:none kw={z: 9}
      b x=:none kw={}
      c falsy nil
      c truthy here
    OUT
  end

  it "later default may read an earlier captured param" do
    result = ze0(<<~'RUBY')
      # `def fill_breakable(sep = ' ', width = sep.length)` with `sep`
      # captured by a block (prettyprint's shape): `width`'s default reads
      # `sep` through its capture cell, so the cell must exist BEFORE the
      # later default evaluates -- wraps now interleave with the bindings in
      # parameter order instead of trailing the whole prologue.

      def fill(sep = "--", width = sep.length)
        t = proc { sep }
        [t.call, width]
      end
      p fill
      p fill("abc")
      p fill("abc", 9)
    RUBY

    _(result).must_answer <<~'OUT'
      ["--", 2]
      ["abc", 3]
      ["abc", 9]
    OUT
  end

  it "method added sees the superseded body" do
    result = ze0(<<~'RUBY')
      # `def v; end; def v; end` fires `method_added(:v)` twice, and at the FIRST
      # firing ruby has only the first body installed. zeo runs the second.
      #
      # This is not the watermark, which handles a name whose first definition is
      # still ahead (`tests/method_added_dispatch_watermark.rb`). Here `v` is already
      # defined at both firings -- what differs is WHICH body. zeo keeps one row per
      # name: `analyze::add_own_method` REPLACES an earlier same-name entry rather
      # than appending, which is Ruby's own last-def-wins rule everywhere else, and
      # codegen emits one method per surviving row. The superseded body is not
      # compiled at all, so there is nothing for the first hook to reach.
      #
      # Fix shape, if this ever earns it: keep every redefinition as its own row,
      # emit them all, and have the watermark name which row is current at each hook
      # position. That is a per-redefinition cost in generated code paid by every
      # program, to serve a hook body that reads a method it is about to lose.

      class Redef
        def self.method_added(name)
          return unless name == :v
          puts "  v -> #{new.v}"
        end

        def v = 1
        def v = 2
      end
      p Redef.new.v

      # The same asymmetry with an `attr_accessor` superseded by a hand-written
      # reader: the hook for `:name` sees the generated one in ruby.
      class Attr
        def self.method_added(m)
          return unless m == :name
          puts "  name -> #{new.name.inspect}"
        end

        attr_accessor :name
        def name = "hand-written"
      end
      p Attr.new.name
    RUBY

    _(result).must_answer <<~'OUT'
        v -> 1
        v -> 2
      2
        name -> nil
        name -> "hand-written"
      "hand-written"
    OUT
  end

  it "method added watermark" do
    result = ze0(<<~'RUBY')
      # Ruby's definition hook sees a HALF-BUILT class: at `method_added(:a)`,
      # `instance_methods(false)` answers `[:a]` alone, and a `def b` written below is
      # not defined yet.
      #
      # zeo installs every method table before the program's first statement runs, so
      # there is no such moment to observe. The compiler works out which names are
      # still in the future at each announcement -- it knows them statically -- and
      # the reflection rows subtract that set for as long as the hook body is running.

      class W
        def self.method_added(name)
          puts "#{name}: own=#{instance_methods(false).sort.inspect} " \
               "defined?(later)=#{method_defined?(:later)} " \
               "respond_to=#{new.respond_to?(:later)}"
        end

        def first = 1
        def later = 2
        def last = 3
      end

      puts "-- once the class is built, everything is visible again"
      p [W.instance_methods(false).sort, W.method_defined?(:later)]

      puts "-- instance_method raises for a name that does not exist yet"
      class R
        def self.method_added(name)
          return unless name == :one
          begin
            instance_method(:two)
          rescue NameError => e
            puts "  NameError: #{e.message}"
          end
        end
        def one = 1
        def two = 2
      end

      puts "-- visibility predicates follow the same watermark"
      class V
        def self.method_added(name)
          return unless name == :pub
          puts "  public?=#{public_method_defined?(:priv)} private?=#{private_method_defined?(:priv)}"
        end
        def pub = 1
        private
        def priv = 2
      end

      puts "-- an INHERITED name is not hidden: it exists, whatever this class reached"
      class Base
        def shared = "base"
      end
      class Sub < Base
        def self.method_added(name)
          return unless name == :own
          puts "  shared defined?=#{method_defined?(:shared)} own=#{instance_methods(false).sort.inspect}"
        end
        def own = 1
        def shared = "sub"
      end

      puts "-- a redefinition does not hide the name it already defined"
      class D
        def self.method_added(name)
          puts "  #{name}: defined?=#{method_defined?(:x)}"
        end
        def x = 1
        def x = 2
      end

      puts "-- a runtime definition needs no watermark: it really is the last one"
      K = Class.new do
        def self.method_added(name)
          puts "  runtime #{name}: own=#{instance_methods(false).sort.inspect}"
        end
        def a = 1
        def b = 2
      end
    RUBY

    _(result).must_answer <<~'OUT'
      first: own=[:first] defined?(later)=false respond_to=false
      later: own=[:first, :later] defined?(later)=true respond_to=true
      last: own=[:first, :last, :later] defined?(later)=true respond_to=true
      -- once the class is built, everything is visible again
      [[:first, :last, :later], true]
      -- instance_method raises for a name that does not exist yet
        NameError: undefined method 'two' for class 'R'
      -- visibility predicates follow the same watermark
        public?=false private?=false
      -- an INHERITED name is not hidden: it exists, whatever this class reached
        shared defined?=true own=[:own]
      -- a redefinition does not hide the name it already defined
        x: defined?=true
        x: defined?=true
      -- a runtime definition needs no watermark: it really is the last one
        runtime a: own=[:a]
        runtime b: own=[:a, :b]
    OUT
  end

  it "method in container" do
    result = ze0(<<~'RUBY')
      class Calc
        def initialize(b); @b = b; end
        def add(n); @b + n; end
      end
      ms = [Calc.new(3).method(:add)]
      p ms[0].class
      p ms[0].name
      p ms[0].owner.to_s
      p ms[0].receiver.class.to_s
      p ms[0].parameters
      p ms[0].arity
      p ms[0].call(1)
      p ms[0].unbind.class
      p ms[0].to_proc.call(1)
      h = { a: Calc.new(3).method(:add) }
      p h[:a].name
      p h[:a].call(2)
    RUBY

    _(result).must_answer <<~'OUT'
      Method
      :add
      "Calc"
      "Calc"
      [[:req, :n]]
      1
      4
      UnboundMethod
      4
      :add
      5
    OUT
  end

  it "method object does not snapshot its definition" do
    result = ze0(<<~'RUBY')
      # A `Method` or `UnboundMethod` captured before a reopen keeps answering for
      # the definition it was taken from.
      #
      # The BODY half was already right: `RMethod::snapshot` froze the entry, so
      # `m.call` ran the captured body. What followed the live tables was the
      # METADATA -- `#arity`, `#parameters`, `#source_location` and `#inspect` are
      # keyed by `(class, name)` with no position, and a redefinition timeline
      # re-registers that key at each body's own line. So one handle described two
      # different definitions depending on which question you asked.
      #
      # The fix is the metadata twin of the entry snapshot: the handle captures its
      # `Arc<MethodMeta>` at construction and every reflection row reads through it.
      # CRuby holds the `rb_method_entry_t` it was built from, which makes all of
      # these a snapshot rather than a lookup.
      #
      # `meta` is `None` exactly where `snapshot` is None, and for the same reason:
      # a `#super_method` re-seat names a position the ordinary walk would not
      # reach, so it resolves afresh. `#bind` and `#unbind` carry the row on, since
      # `um.arity` and `um.bind(o).arity` describe one definition.
      class U
        def u = 1
      end
      first = U.instance_method(:u)
      class U
        def u(a) = 2
      end
      p [first.arity, U.instance_method(:u).arity]
      p first.parameters
      p U.instance_method(:u).parameters

      class B
        def b = "b1"
      end
      m = B.new.method(:b)
      class B
        def b = "b2"
      end
      p [m.arity, m.call, B.new.b]

      # The sweep.

      # `source_location` and `inspect` follow the same row as `arity`.
      class S
        def s = 1
      end
      h = S.instance_method(:s)
      line_before = h.source_location[1]
      class S
        def s(a, b) = 2
      end
      p [h.arity, h.parameters, h.source_location[1] == line_before]
      p [S.instance_method(:s).arity, S.instance_method(:s).source_location[1] == line_before]

      # `#bind` carries the row: the bound Method must describe the same definition
      # the UnboundMethod does, not the live one.
      class BN
        def m = 1
      end
      u = BN.instance_method(:m)
      class BN
        def m(a, b, c) = 2
      end
      p [u.arity, u.bind(BN.new).arity, BN.new.method(:m).arity]

      # `#unbind` carries it the other way.
      class UB
        def m = 1
      end
      bm = UB.new.method(:m)
      class UB
        def m(a) = 2
      end
      p [bm.arity, bm.unbind.arity, UB.instance_method(:m).arity]

      # `dup` carries it.
      class DP
        def m = 1
      end
      d = DP.instance_method(:m)
      class DP
        def m(a) = 2
      end
      p [d.dup.arity, d.arity]

      # A handle taken AFTER the last body describes that body -- the ordinary case,
      # and the one a snapshot must not break.
      class AF
        def m = 1
      end
      class AF
        def m(a, b) = 2
      end
      p [AF.instance_method(:m).arity, AF.new.method(:m).arity]

      # A method with no redefinition at all is untouched.
      class NR
        def m(a, b = 1, *r, k:, **kw, &blk) = nil
      end
      p NR.instance_method(:m).parameters
      p NR.instance_method(:m).arity
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1]
      []
      [[:req, :a]]
      [0, "b1", "b2"]
      [0, [], true]
      [2, false]
      [0, 0, 3]
      [0, 0, 1]
      [0, 0]
      [2, 2]
      [[:req, :a], [:opt, :b], [:rest, :r], [:keyreq, :k], [:keyrest, :kw], [:block, :blk]]
      -3
    OUT
  end

  it "method object kwargs" do
    result = ze0(<<~'RUBY')
      class Calc
        def kw(a, b: 2); a + b; end
        def opt(a, b = 1); a + b; end
        def initialize(base = 0); @base = base; end
        def add(n); @base + n; end
      end
      p Calc.new.method(:kw).call(1, b: 5)
      p Calc.new.method(:kw).call(1)
      p Calc.new.method(:opt).call(1)
      p Calc.new.method(:opt).call(1, 9)
      um = Calc.new(1).method(:add).unbind
      p um.bind(Calc.new(10)).call(5)
      p um.arity
      p um.owner.to_s
      p um.bind_call(Calc.new(2), 3)

      module Greet
        def hi(n); "hi #{n}"; end
      end
      class Person
        include Greet
      end
      um2 = Greet.instance_method(:hi)
      p um2.arity
      p um2.bind(Person.new).call("x")
    RUBY

    _(result).must_answer <<~'OUT'
      6
      3
      2
      10
      15
      1
      "Calc"
      5
      1
      "hi x"
    OUT
  end

  it "method original name aliases" do
    result = ze0(<<~'RUBY')
      # `Method#original_name` / `UnboundMethod#original_name` answer the name a
      # method was DEFINED under, which differs from `#name` only when it was reached
      # through an alias. `#inspect` shows the same fact in parens: `A#y(x)`.
      #
      # There are four ways a method can arrive under a second name, and all four
      # have to remember where they came from.

      def shape(m) = m.inspect.sub(/ [^ ]+:\d+>\z/, ">")

      # --- 1. an alias in the SAME body as its source ------------------------------
      class A
        def x(q) = q
        alias_method :y, :x
        alias z x
      end
      a = A.new
      p a.method(:x).name, a.method(:x).original_name
      p a.method(:y).name, a.method(:y).original_name
      p a.method(:z).original_name
      p shape(a.method(:y))

      # The alias is a real method: it calls, and it keeps the source's signature.
      p a.method(:y).call(1), a.method(:y).arity, a.method(:y).parameters

      # --- 2. an alias of an INHERITED method (a different body) -------------------
      class B < A
        alias_method :w, :x
      end
      b = B.new
      p b.method(:w).name, b.method(:w).original_name
      p b.method(:w).owner
      p shape(b.method(:w))
      p b.method(:w).call(2)

      # A subclass INHERITS the alias-ness of an alias defined above it.
      p B.new.method(:y).original_name

      # --- 3. an alias whose source is a BUILTIN -----------------------------------
      class C
        alias_method :inspect_it, :inspect
        alias_method :len, :object_id
      end
      p C.new.method(:inspect_it).name, C.new.method(:inspect_it).original_name
      p C.new.method(:len).original_name

      # --- 4. an alias made at RUNTIME ---------------------------------------------
      class D
        def hello(who) = "hi #{who}"
      end
      D.class_eval { alias_method :greet, :hello }
      d = D.new
      p d.method(:greet).name, d.method(:greet).original_name
      p d.method(:greet).call("ada")
      p d.method(:greet).parameters

      # A chain resolves all the way back to the original, never to the middle.
      D.class_eval { alias_method :salute, :greet }
      p D.new.method(:salute).original_name

      # --- an ordinary method reports its own name ---------------------------------
      p a.method(:x).original_name == a.method(:x).name
      p 1.method(:+).original_name
      p [].method(:each).original_name

      # --- UnboundMethod answers identically ---------------------------------------
      p A.instance_method(:y).name, A.instance_method(:y).original_name
      p shape(A.instance_method(:y))
      p B.instance_method(:w).original_name
      p A.instance_method(:x).original_name
    RUBY

    _(result).must_answer <<~'OUT'
      :x
      :x
      :y
      :x
      :x
      "#<Method: A#y(x)(q)>"
      1
      1
      [[:req, :q]]
      :w
      :x
      B
      "#<Method: B(A)#w(x)(q)>"
      2
      :x
      :inspect_it
      :inspect
      :object_id
      :greet
      :hello
      "hi ada"
      [[:req, :who]]
      :hello
      true
      :+
      :each
      :y
      :x
      "#<UnboundMethod: A#y(x)(q)>"
      :x
      :x
    OUT
  end

  it "method owner module" do
    result = ze0(<<~'RUBY')
      module Greet
        def hello; "hi"; end
      end
      class Person
        include Greet
      end
      m = Person.new.method(:hello)
      p m.owner
      p Person.instance_method(:hello).owner
      class Plain2; def own; 1; end; end
      p Plain2.new.method(:own).owner
      p Person.new.method(:hello).inspect.include?("Greet")
    RUBY

    _(result).must_answer <<~'OUT'
      Greet
      Greet
      Plain2
      true
    OUT
  end

  it "method receiver expr" do
    result = ze0(<<~'RUBY')
      class Calc
        def initialize(b); @b = b; end
        def add(n); @b + n; end
      end
      p Calc.new(3).method(:add).receiver.class
      m = Calc.new(4).method(:add)
      p m.receiver.add(1)
      p m.receiver.class.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      Calc
      5
      "Calc"
    OUT
  end

  it "method visibility" do
    result = ze0(<<~'RUBY')
      # Method visibility tracking: private / protected / public affect the
      # reflection (instance_methods family, method_defined? family) and respond_to?.

      class Account
        def deposit(n); n; end       # public (default)
        def balance; 100; end        # public

        private

        def log(msg); msg; end       # private (section)
        def secret; 42; end          # private (section)

        protected

        def compare(o); o; end       # protected (section)

        public

        def withdraw(n); n; end      # public (re-opened section)

        private :balance             # demote a previously-public method
        private def helper; 1; end   # inline private def
      end

      def sorted(arr); arr.map(&:to_s).sort; end

      # instance_methods(false) excludes private, keeps public + protected
      puts sorted(Account.instance_methods(false)).inspect
      puts sorted(Account.public_instance_methods(false)).inspect
      puts sorted(Account.private_instance_methods(false)).inspect
      puts sorted(Account.protected_instance_methods(false)).inspect

      # method_defined? matches public + protected, not private
      puts Account.method_defined?(:deposit)
      puts Account.method_defined?(:compare)
      puts Account.method_defined?(:log)
      puts Account.method_defined?(:balance)     # demoted to private
      puts Account.method_defined?(:helper)
      puts Account.method_defined?(:missing)

      # the prefixed forms match exactly one visibility
      puts Account.public_method_defined?(:deposit)
      puts Account.public_method_defined?(:log)
      puts Account.private_method_defined?(:log)
      puts Account.private_method_defined?(:helper)
      puts Account.protected_method_defined?(:compare)
      puts Account.protected_method_defined?(:deposit)

      # respond_to?: public only by default; include_all=true also matches private/protected
      a = Account.new
      puts a.respond_to?(:deposit)
      puts a.respond_to?(:log)
      puts a.respond_to?(:log, true)
      puts a.respond_to?(:secret)
      puts a.respond_to?(:secret, true)
      puts a.respond_to?(:compare)
      puts a.respond_to?(:compare, true)
      puts a.respond_to?(:withdraw)
      puts a.respond_to?(:nope)
      puts a.respond_to?(:nope, true)
    RUBY

    _(result).must_answer <<~'OUT'
      ["compare", "deposit", "withdraw"]
      ["deposit", "withdraw"]
      ["balance", "helper", "log", "secret"]
      ["compare"]
      true
      true
      false
      false
      false
      false
      true
      false
      true
      true
      true
      false
      true
      false
      true
      false
      true
      false
      true
      true
      false
      false
    OUT
  end

  it "middle splat param" do
    result = ze0(<<~'RUBY')
      # Issue #710. A middle *splat parameter (def f(a, *b, c)) must collect
      # the inner args and leave the trailing fixed param(s) for the args
      # after the splat. Before the fix, the splat greedily ate all the
      # remaining call args and `c` got 0 with "missing required arg" warnings.

      def g(a, *b, c); [a, b, c]; end
      puts g(1, 2, 3, 4).inspect
      puts g(10, 20, 30).inspect
      puts g(100, 200).inspect          # empty splat, c=200

      def h(a, b, *c, d, e)
        [a, b, c, d, e]
      end
      puts h(1, 2, 3, 4, 5, 6, 7).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, [2, 3], 4]
      [10, [20], 30]
      [100, [], 200]
      [1, 2, [3, 4, 5], 6, 7]
    OUT
  end

  it "names that collide with the compiler" do
    result = ze0(<<~'RUBY')
      # Ruby names that collide with the compiler's own vocabulary must not leak
      # into the generated program: a class named after a builtin type, a method
      # named after a keyword, and Ruby's `_` local, which the generated program
      # has no named binding for. All are mangled on the way out, and none of the
      # mangling is observable from Ruby.

      # --- Classes named after builtin types ------------------------------------

      class Vec
        def initialize(x, y)
          @x = x
          @y = y
        end
        attr_reader :x, :y

        def +(other)
          Vec.new(@x + other.x, @y + other.y)
        end

        def to_s = "Vec(#{@x}, #{@y})"
      end

      v = Vec.new(1, 2) + Vec.new(10, 20)
      puts v
      p v.x
      p v.class
      p v.class.name
      p v.is_a?(Vec)

      class Option
        def initialize(value) = @value = value
        def some? = !@value.nil?
        def value_or(default) = @value.nil? ? default : @value
      end
      p Option.new(5).some?
      p Option.new(nil).some?
      p Option.new(nil).value_or(:fallback)
      p Option.new(:got).value_or(:fallback)

      class Box
        def initialize(v) = @v = v
        def get = @v
      end
      p Box.new("boxed").get

      class Result
        def initialize(ok) = @ok = ok
        def ok? = @ok
      end
      p Result.new(true).ok?

      # Inheritance between prelude-named classes.
      class Iterator
        def each = [1, 2].each { |i| yield i }
      end
      class Send < Iterator; end
      out = []
      Send.new.each { |i| out << i }
      p out
      p Send.new.is_a?(Iterator)

      # A prelude-named class used as a Hash key and in a collection.
      registry = { Vec => :vector, Option => :option }
      p registry[Vec]
      p [Vec.new(0, 0), Vec.new(1, 1)].map(&:to_s)

      # --- Methods named after compiler keywords --------------------------------

      class Keywords
        def type = "a type"
        def match = "a match"
        def loop = "a loop"
        def fn = "an fn"
        def impl = "an impl"
        def move = "a move"
        def ref = "a ref"
        def struct = "a struct"
      end
      k = Keywords.new
      p k.type
      p k.match
      p k.loop
      p k.fn
      p k.impl
      p k.send(:type)
      p k.respond_to?(:match)

      # Predicate/bang/setter suffixes.
      class Suffixes
        def initialize = @saved = false
        def empty? = false
        def save! = @saved = true
        def value=(v)
          @value = v
        end
        def value = @value
        def saved? = @saved
      end
      s = Suffixes.new
      p s.empty?
      s.save!
      p s.saved?
      s.value = 42
      p s.value

      # --- Ruby's `_` local ------------------------------------------------------

      # `_` is an ordinary, readable local in Ruby.
      _ = 10
      p _
      _ = _ + 5
      p _

      # The conventional throwaway in a block, still readable.
      [[1, :a], [2, :b]].each do |n, _|
        p n
      end
      [[1, :a]].each { |_, sym| p sym }

      # `_` in a multiple assignment.
      _, second = [:first, :second]
      p second
      p _

      # Repeated `_` params (Ruby allows the duplicate name).
      [[1, 2, 3]].each { |_, _, third| p third }
    RUBY

    _(result).must_answer <<~'OUT'
      Vec(11, 22)
      11
      Vec
      "Vec"
      true
      true
      false
      :fallback
      :got
      "boxed"
      true
      [1, 2]
      true
      :vector
      ["Vec(0, 0)", "Vec(1, 1)"]
      "a type"
      "a match"
      "a loop"
      "an fn"
      "an impl"
      "a type"
      true
      false
      true
      42
      10
      15
      1
      2
      :a
      :second
      :first
      3
    OUT
  end

  it "nullable" do
    result = ze0(<<~'RUBY')
      # Test nullable types (T|nil without full poly overhead)
      def find_name(arr, target)
        result = nil
        i = 0
        while i < arr.length
          if arr[i] == target
            result = "found:" + target.to_s
          end
          i = i + 1
        end
        result
      end

      r = find_name([10, 20, 30], 20)
      if r.nil?
        puts "not found"
      else
        puts r
      end

      r2 = find_name([10, 20, 30], 99)
      if r2.nil?
        puts "not found"
      else
        puts r2
      end
    RUBY

    _(result).must_answer "found:20\nnot found\n"
  end

  it "op method shift" do
    result = ze0(<<~'RUBY')
      # User-defined << / >> dispatch to the class method, not a raw C shift.
      class Buf
        def initialize
          @s = ""
        end
        def <<(x)
          @s = @s + x
          self
        end
        def >>(x)
          @s = x + @s
          self
        end
        def to_s
          @s
        end
      end
      b = Buf.new
      b << "hi"
      b << "!"
      b >> "["
      puts b.to_s
      # Builtin << still works (regression guard).
      a = []
      a << 1
      a << 2
      puts a.length
      s = "x"
      s << "y"
      puts s
    RUBY

    _(result).must_answer <<~'OUT'
      [hi!
      2
      xy
    OUT
  end

  it "receiver before arguments" do
    result = ze0(<<~'RUBY')
      # Ruby evaluates a call's receiver before its arguments. Spinel handed both to
      # one C call, where the order among the operands is unspecified: gcc picks
      # right-to-left and clang picks left-to-right, so the same program printed the
      # argument's trace before the receiver's on Linux and after it on macOS. The
      # receiver binds to a temp in front of the call now, in place rather than at the
      # statement above, so an expression inside a block body still evaluates where it
      # was written.
      def r_str(v); puts "R str"; v; end
      def a_str(v); puts "A str"; v; end
      p r_str(String.new("abc")).include?(a_str("b"))
      p r_str(String.new("hello")).index(a_str("l"))

      def r_arr(v); puts "R arr"; v; end
      def a_arr(v); puts "A arr"; v; end
      p r_arr([1, 2, 3]).include?(a_arr(2))
      p r_arr([1, 2, 3]).fetch(a_arr(0))

      def r_hash(v); puts "R hash"; v; end
      def a_hash(v); puts "A hash"; v; end
      p r_hash({"k" => 1}).key?(a_hash("k"))

      def r_obj(v); puts "R obj"; v; end
      def a_obj(v); puts "A obj"; v; end
      class Adder
        def initialize; @seen = []; end
        def take(x); @seen.push(x); @seen.length; end
      end
      p r_obj(Adder.new).take(a_obj(7))

      # The receiver is bound where it is written, not hoisted out of a block body:
      # these operands read block parameters that only exist inside it.
      p [10, 20].each.with_index.inject(0) { |t, pr| t + pr[0] + pr[1] }
      p [[1, 2], [3, 4]].map { |a, b| a.to_s + b.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      R str
      A str
      true
      R str
      A str
      2
      R arr
      A arr
      true
      R arr
      A arr
      1
      R hash
      A hash
      true
      R obj
      A obj
      1
      31
      ["12", "34"]
    OUT
  end

  it "recv method splat" do
    result = ze0(<<~'RUBY')
      # Splatting an array into a user-object method call `obj.f(*args)`. Free-function
      # splat already worked; this covers the receiver-method dispatch path.
      class C
        def add3(a, b, c); a + b + c; end
        def join2(a, b); "#{a}-#{b}"; end
        def opt(a, b = 10, c = 20); a + b + c; end
        def show(a, b, c); [a, b, c].inspect; end
      end

      o = C.new
      nums = [1, 2, 3]
      puts o.add3(*nums)            # 6 -- whole-array splat
      puts C.new.add3(*nums)       # 6 -- splat on a fresh receiver
      rest = [2, 3]
      puts o.add3(1, *rest)        # 6 -- leading positional + splat

      parts = ["x", "y"]
      puts o.join2(*parts)         # x-y -- string elements

      puts o.opt(*[1])             # 31 -- optional params fall back to defaults
      puts o.opt(*[1, 2])          # 23
      puts o.opt(*[1, 2, 3])       # 6

      mixed = [1, "two", :three]
      puts o.show(*mixed)          # [1, "two", :three] -- mixed/poly elements

      # wrong element count raises ArgumentError with CRuby's message
      begin
        o.add3(*[1, 2])
      rescue ArgumentError => e
        puts "AE: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      6
      x-y
      31
      23
      6
      [1, "two", :three]
      AE: wrong number of arguments (given 2, expected 3)
    OUT
  end

  it "redefinition window ignores a visibility mark" do
    result = ze0(<<~'RUBY')
      # A `private` mark made before a reopen is enforced in the REDEFINITION
      # WINDOW, and the reopen clears it -- both channels.
      #
      # The gap filed this as TWO writes: a mark to apply, and each install to
      # rewrite it. It is ONE, because the fact was already in the right place.
      # `lower::defs` retags a `def` IN PLACE when `private :v` names a method the
      # same body just defined (there is no `MethodVisibility` node at all in that
      # shape). So by the time `analyze::redefs` builds a timeline, every body
      # already carries its own visibility, and installing it beside the body gives
      # both halves at once: the first body's `private` applies, and the second
      # body's `public` -- the class body's running default at that `def` -- is
      # what clears it.
      #
      # That is also ruby's own rule. A re-`def` resets a name to the running
      # default; it does not inherit the previous body's mark.
      #
      # The mark rides the existing install in both positions: bits 1-2 of
      # `REG_BOOT_REDEF`'s flag byte for the first body (bit 0 was already the
      # channel), and a `zeo_rt_install_positional_visibility` call beside each
      # later one. That entry is infallible on purpose -- unlike
      # `zeo_rt_runtime_set_visibility` there is no name to resolve and no
      # `method_added` to fire, because the install on the line above created the
      # method.
      #
      # Falling back to the static row would NOT have worked: it records the END
      # state, which is public here.
      class V
        def v = "v1"
        private :v
      end
      p [(V.new.v rescue $!.class.to_s), V.new.send(:v)]
      class V
        def v = "v2"
      end
      p V.new.v

      class CV
        def self.v = "cv1"
        private_class_method :v
      end
      p [(CV.v rescue $!.class.to_s), CV.send(:v)]
      class CV
        def self.v = "cv2"
      end
      p CV.v

      # The sweep. Each shape below is one a fix could plausibly get wrong.

      # `protected` is the third mark, and it rides the same two bits.
      class PR
        def m = "pr1"
        protected :m
      end
      p [PR.protected_instance_methods(false), (PR.new.m rescue $!.class.to_s)]
      class PR
        def m = "pr2"
      end
      p [PR.protected_instance_methods(false), PR.new.m]

      # The running DEFAULT, rather than a named mark: a bare `private` before the
      # `def` stamps the body the same way.
      class BD
        private
        def m = "bd1"
      end
      p [BD.private_instance_methods(false), (BD.new.m rescue $!.class.to_s)]
      class BD
        def m = "bd2"
      end
      p [BD.private_instance_methods(false), BD.new.m]

      # Three bodies, so a MIDDLE install has to clear and re-mark.
      class TH
        def m = "t1"
        private :m
      end
      p [(TH.new.m rescue $!.class.to_s), TH.new.send(:m)]
      class TH
        def m = "t2"
      end
      p TH.new.m
      class TH
        def m = "t3"
        private :m
      end
      p [(TH.new.m rescue $!.class.to_s), TH.new.send(:m)]

      # The reverse order: public first, private last. The static row says private,
      # so the WINDOW is what a fix has to keep public.
      class RV
        def m = "rv1"
      end
      p RV.new.m
      class RV
        private def m = "rv2"
      end
      p [(RV.new.m rescue $!.class.to_s), RV.new.send(:m)]

      # A mark written in a LATER body, naming a method an EARLIER body defined --
      # the deferred `MethodVisibility` path rather than the in-place retag.
      class LT
        def m = "lt1"
      end
      p LT.new.m
      class LT
        private :m
      end
      p [(LT.new.m rescue $!.class.to_s), LT.new.send(:m)]

      # A method with no redefinition at all keeps the ordinary static path.
      class ST
        def a = "a"
        def b = "b"
        private :b
      end
      p [ST.new.a, (ST.new.b rescue $!.class.to_s), ST.private_instance_methods(false)]
    RUBY

    _(result).must_answer <<~'OUT'
      ["NoMethodError", "v1"]
      "v2"
      ["NoMethodError", "cv1"]
      "cv2"
      [[:m], "NoMethodError"]
      [[], "pr2"]
      [[:m], "NoMethodError"]
      [[], "bd2"]
      ["NoMethodError", "t1"]
      "t2"
      ["NoMethodError", "t3"]
      "rv1"
      ["NoMethodError", "rv2"]
      "lt1"
      ["NoMethodError", "lt1"]
      ["a", "NoMethodError", [:b]]
    OUT
  end

  it "remove method on a mixed in module" do
    result = ze0(<<~'RUBY')
      # `remove_method` on a MODULE takes the name away from every class that mixed
      # the module in, and a class's OWN definition survives it.
      #
      # Analyze materializes a module's rows onto each host at compile time, so
      # `Host.new.m` resolves through the HOST's own row and never asks the module.
      # The tombstone `remove_method` writes is keyed on the module, at a position
      # the lookup does not visit -- so the removal has to name the hosts and
      # tombstone them too. A host whose winner is its OWN def is not one of them.
      #
      # The hosts are named BEFORE the module's own tombstone lands. "Whose copy is
      # this" is `method_owner`, and once the overlay is live that walk SKIPS a
      # removed position -- so writing first made the module stop being the owner
      # and the sweep find nobody. It reproduced only from the SECOND removal in a
      # program, because the first is what arms the overlay.
      #
      # Reflection reads the same tombstone, and by a different rule than `undef`:
      # a removal empties one position and the walk carries on, so the name is
      # dropped from what that ancestor contributes rather than claimed outright.

      module S
        def u = "s"
      end
      class C
        include S
      end
      class D
        prepend S
      end
      class E
        include S
        def u = "own"
      end
      p [C.new.u, D.new.u, E.new.u]

      S.send(:remove_method, :u)
      def try(o) = (o.u rescue $!.class.to_s)
      p [try(C.new), try(D.new), try(E.new)]

      # A later definition on the module restores it everywhere, and still does not
      # displace the host's own.
      S.send(:define_method, :u) { "s3" }
      p [C.new.u, D.new.u, E.new.u]

      # Reflection agrees with dispatch on both sides of the removal.
      module T
        def w = 1
      end
      class F
        include T
      end
      p [F.method_defined?(:w), F.instance_method(:w).owner.to_s]
      T.send(:remove_method, :w)
      p [
        F.method_defined?(:w),
        F.new.respond_to?(:w),
        T.instance_methods(false).map(&:to_s),
        F.instance_methods(false).map(&:to_s),
      ]

      # Removing from the HOST names a method the host does not own.
      class G
        include T
      end
      begin
        G.send(:remove_method, :w)
      rescue NameError => e
        p e.class.to_s
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["s", "s", "own"]
      ["NoMethodError", "NoMethodError", "own"]
      ["s3", "s3", "own"]
      [true, "T"]
      [false, false, [], []]
      "NameError"
    OUT
  end

  it "rest param keyword argument" do
    result = ze0(<<~'RUBY')
      # A bare `k: v` argument degrades to one positional hash at a `*rest`
      # parameter's tail. One call path did that and the other dropped it entirely,
      # so an INSTANCE method ran with no arguments at all while the identical
      # top-level call kept them -- silently, no error (#3503).
      class C
        def splat_only(*parts) = parts.length
        def leading_arg(a, *parts) = parts.length
        def kwrest(**kw) = kw.length
        def named_kw(id:) = id.to_s
        def rest_and_named(*parts, id:) = [parts.length, id.to_s]
        def contents(*parts) = parts
      end

      def top(*parts) = parts.length

      c = C.new
      p top(id: :desc)
      p c.splat_only(id: :desc)
      p c.splat_only({ id: :desc })
      p c.leading_arg(1, id: :desc)
      p c.kwrest(id: :desc)
      p c.splat_only
      p c.splat_only(1, 2)
      p c.splat_only(1, id: :desc)
      p c.splat_only("a" => 1)

      # a named keyword param still consumes the hash rather than seeing it as rest
      p c.named_kw(id: :desc)
      p c.rest_and_named(1, 2, id: :desc)

      # the hash that lands in rest is the real thing
      p c.contents(id: :desc)
      p c.contents(1, id: :desc)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      1
      1
      1
      0
      2
      2
      1
      "desc"
      [2, "desc"]
      [{id: :desc}]
      [1, {id: :desc}]
    OUT
  end

  it "splat new" do
    result = ze0(<<~'RUBY')
      # A `*args` positional splat or a `**opts` double-splat at a `.new` call
      # site expands at runtime, dispatching through the class's constructor --
      # the same as any ordinary splat call.
      class Point
        def initialize(x, y)
          @x = x
          @y = y
        end

        def to_s
          "(#{@x}, #{@y})"
        end
      end

      coords = [3, 4]
      puts Point.new(*coords)              # (3, 4)

      # `Data.define` classes construct by keyword, so a `**hash` double-splat
      # forwards a runtime hash straight into the constructor.
      Config = Data.define(:host, :port)
      opts = { host: "localhost", port: 8080 }
      p Config.new(**opts)                 # #<data Config host="localhost", port=8080>
      p Config.new(**{ host: "example.com", port: 443 })
    RUBY

    _(result).must_answer <<~'OUT'
      (3, 4)
      #<data Config host="localhost", port=8080>
      #<data Config host="example.com", port=443>
    OUT
  end

  it "three way method visibility reflection" do
    result = ze0(<<~'RUBY')
      # Private/public/protected are tracked distinctly: `instance_methods`
      # keeps public+protected, the prefixed queries match exactly one
      # visibility, `respond_to?`'s default skips private AND protected, and a
      # subclass may re-declare an inherited method's visibility.

      class Account
        def deposit; end
        private
        def log; end
        protected
        def compare; end
      end
      def s(a); a.map(&:to_s).sort; end
      p s(Account.instance_methods(false))
      p s(Account.public_instance_methods(false))
      p s(Account.protected_instance_methods(false))
      p s(Account.private_instance_methods(false))
      p Account.public_method_defined?(:deposit)
      p Account.protected_method_defined?(:compare)
      p Account.private_method_defined?(:log)
      p Account.public_method_defined?(:compare)
      a = Account.new
      p a.respond_to?(:compare)
      p a.respond_to?(:compare, true)
      class Base
        def m; end
      end
      class Sub < Base
        private :m
      end
      p Sub.new.respond_to?(:m)
      p Sub.private_method_defined?(:m)
    RUBY

    _(result).must_answer <<~'OUT'
      ["compare", "deposit"]
      ["deposit"]
      ["compare"]
      ["log"]
      true
      true
      true
      false
      false
      true
      false
      true
    OUT
  end

  it "universal def answers the same on every receiver" do
    result = ze0(<<~'RUBY')
      # A top-level `def` reaches every object, and it must answer the same five
      # questions wherever it is called from.
      #
      # WHY THIS FILE EXISTS. zeo emits a definition on Object/Kernel/BasicObject
      # ONCE under its `Object#name` symbol, and ALSO materializes a private copy
      # onto every user class -- 22,393 extra bodies on a program that requires
      # rubygems, which is 78 MB of the binary. A builtin receiver already skips
      # the copy and dispatches to the shared body (`analyze::mro` exempts it), so
      # the two paths are live side by side RIGHT NOW.
      #
      # That makes this a decisive experiment rather than a guess: if a builtin
      # receiver -- which uses the shared body -- answers exactly what a user class
      # answers -- which uses its own copy -- then dropping the copy changes
      # nothing. Every row below is printed for both kinds for that reason.
      #
      # The five questions are the ones a shared body could get wrong, because each
      # is compiled from something the body would no longer own: an ivar slot, the
      # caller's class, the constant cref, the method owner, and where `super`
      # goes.

      TOP_LEVEL_CONST = "top"

      def touches_an_ivar
        @counter = (@counter || 0) + 1
        [@counter, instance_variable_get(:@counter), instance_variables]
      end

      def reads_a_constant
        TOP_LEVEL_CONST
      end

      def reports_its_owner
        method(__method__).owner
      end

      def calls_a_private_sibling
        a_private_helper
      end

      # Every top-level `def` is already a PRIVATE instance method of Object, which
      # is why each row below reaches it through `send` rather than a dot.
      def a_private_helper
        "private reached"
      end

      def goes_to_super
        super
      rescue NoMethodError => e
        "no super: #{e.message[0, 24]}"
      end

      class Plain; end

      class WithIvar
        def initialize = (@counter = 100)
      end

      class Overrides
        def goes_to_super = "overridden"
      end

      # A class that DEFINES the same name is not sharing anything, and must keep
      # its own body.
      class OwnCopy
        def reads_a_constant = "mine"
      end

      RECEIVERS = {
        # Builtin receivers: the shared-body path today.
        "String" => -> { +"s" },
        "Array" => -> { [1] },
        "Hash" => -> { {} },
        # User classes: the materialized-copy path today.
        "Plain" => -> { Plain.new },
        "WithIvar" => -> { WithIvar.new },
        "OwnCopy" => -> { OwnCopy.new },
      }.freeze

      def show(label, receiver)
        yield receiver
      rescue StandardError => e
        "#{e.class}: #{e.message[0, 40]}"
      end

      RECEIVERS.each do |name, make|
        r = make.call
        puts "#{name}\tivar\t#{show(name, r) { |o| o.send(:touches_an_ivar) }.inspect}"
        puts "#{name}\tivar again\t#{show(name, r) { |o| o.send(:touches_an_ivar) }.inspect}"
        puts "#{name}\tconst\t#{show(name, r) { |o| o.send(:reads_a_constant) }.inspect}"
        puts "#{name}\towner\t#{show(name, r) { |o| o.send(:reports_its_owner) }.inspect}"
        puts "#{name}\tprivate\t#{show(name, r) { |o| o.send(:calls_a_private_sibling) }.inspect}"
        puts "#{name}\tsuper\t#{show(name, r) { |o| o.send(:goes_to_super) }.inspect}"
        puts "#{name}\tprivate?\t#{r.respond_to?(:a_private_helper).inspect}"
      end

      # The two paths must also agree about REFLECTION, which is what a gem reads.
      puts "owner via Plain\t#{Plain.instance_method(:reads_a_constant).owner}"
      puts "owner via String\t#{String.instance_method(:reads_a_constant).owner}"
      puts "owner via OwnCopy\t#{OwnCopy.instance_method(:reads_a_constant).owner}"
      puts "Plain defines?\t#{Plain.instance_methods(false).include?(:reads_a_constant)}"
      puts "Object defines?\t#{Object.private_instance_methods(false).include?(:reads_a_constant)}"

      # An ivar written through a shared body has to land on the RECEIVER, not
      # anywhere shared. Two objects of one class must not see each other's.
      a = Plain.new
      b = Plain.new
      a.send(:touches_an_ivar)
      a.send(:touches_an_ivar)
      b.send(:touches_an_ivar)
      puts "separate ivars\t#{[a.instance_variable_get(:@counter), b.instance_variable_get(:@counter)].inspect}"

      # And a class that already had the ivar keeps its own value.
      w = WithIvar.new
      w.send(:touches_an_ivar)
      puts "pre-set ivar\t#{w.instance_variable_get(:@counter)}"

      # `super` from a universal def, where the receiver's class DOES define it.
      puts "override wins\t#{Overrides.new.goes_to_super.inspect}"
    RUBY

    _(result).must_answer <<~'OUT'
      String	ivar	[1, 1, [:@counter]]
      String	ivar again	[2, 2, [:@counter]]
      String	const	"top"
      String	owner	Object
      String	private	"private reached"
      String	super	"no super: super: no superclass met"
      String	private?	false
      Array	ivar	[1, 1, [:@counter]]
      Array	ivar again	[2, 2, [:@counter]]
      Array	const	"top"
      Array	owner	Object
      Array	private	"private reached"
      Array	super	"no super: super: no superclass met"
      Array	private?	false
      Hash	ivar	[1, 1, [:@counter]]
      Hash	ivar again	[2, 2, [:@counter]]
      Hash	const	"top"
      Hash	owner	Object
      Hash	private	"private reached"
      Hash	super	"no super: super: no superclass met"
      Hash	private?	false
      Plain	ivar	[1, 1, [:@counter]]
      Plain	ivar again	[2, 2, [:@counter]]
      Plain	const	"top"
      Plain	owner	Object
      Plain	private	"private reached"
      Plain	super	"no super: super: no superclass met"
      Plain	private?	false
      WithIvar	ivar	[101, 101, [:@counter]]
      WithIvar	ivar again	[102, 102, [:@counter]]
      WithIvar	const	"top"
      WithIvar	owner	Object
      WithIvar	private	"private reached"
      WithIvar	super	"no super: super: no superclass met"
      WithIvar	private?	false
      OwnCopy	ivar	[1, 1, [:@counter]]
      OwnCopy	ivar again	[2, 2, [:@counter]]
      OwnCopy	const	"mine"
      OwnCopy	owner	Object
      OwnCopy	private	"private reached"
      OwnCopy	super	"no super: super: no superclass met"
      OwnCopy	private?	false
      owner via Plain	Object
      owner via String	Object
      owner via OwnCopy	OwnCopy
      Plain defines?	false
      Object defines?	true
      separate ivars	[2, 1]
      pre-set ivar	101
      override wins	"overridden"
    OUT
  end

  it "user defined operator methods can be defined and dispatched" do
    result = ze0(<<~'RUBY')
      # A real, previously-undetected bug: `safe_ident` had no escaping at
      # all for a method name that's a bare operator symbol (`+`, `<=>`,
      # `[]`, ...) -- `def +(other)` aborted at CODEGEN time with a bare
      # "not a valid identifier" error. This meant user-defined
      # operator overloading -- claimed to "work for free"
      # once operators became ordinary Calls -- never actually worked for
      # the DEFINING side; every existing operator test exercised only
      # native `Int`/`Float` fast paths, which bypass `safe_ident` entirely.
      # Fixed via a fixed lookup table (`OPERATOR_METHOD_NAMES`) mapping
      # every operator symbol to a valid identifier, consulted by BOTH
      # the method-definition side and the general-dispatch call site (the
      # same function backs both), so they agree automatically.

      class Vector
        attr_reader :x, :y
        def initialize(x, y)
          @x = x
          @y = y
        end
        def +(other)
          Vector.new(@x + other.x, @y + other.y)
        end
        def <=>(other)
          (@x * @x + @y * @y) <=> (other.x * other.x + other.y * other.y)
        end
        def to_s
          "(#{@x}, #{@y})"
        end
      end
      v1 = Vector.new(1, 2)
      v2 = Vector.new(3, 4)
      v3 = v1 + v2
      puts v3.to_s
      puts(v1 <=> v2)
      puts(v2 <=> v1)
      puts(v1 <=> v1)
    RUBY

    _(result).must_answer <<~'OUT'
      (4, 6)
      -1
      1
      0
    OUT
  end

  it "visibility explicit receiver" do
    result = ze0(<<~'RUBY')
      # Ruby's THIRD call mode: an explicit receiver enforces visibility, where a
      # receiverless call does not. A `protected` method is reachable only when the
      # CALLER'S SELF is kind_of the method's owner.
      #
      # The class-method case is the asymmetry that was wrong: in `def self.peek(a);
      # a.balance; end`, `self` is the class object, and a class object is no kind
      # of the class whose instances hold `balance`. zeo measured the caller by its
      # lexical class instead, so the class method reached a protected method ruby
      # refuses.

      def t; yield; rescue NoMethodError => e; puts "NoMethodError: #{e.message[0, 44]}"; end

      class A
        def pub; :pub; end
        private def priv; :priv; end
        protected def prot; :prot; end
        def sec; :sec; end
        private :sec
        def call_priv; priv; end
        def call_self_priv; self.priv; end
        def cmp(o); o.prot; end
      end
      a = A.new
      t { p a.pub }
      t { p a.priv }
      t { p a.prot }
      t { p a.sec }
      t { p a.call_priv }
      t { p a.call_self_priv }
      t { p a.cmp(A.new) }
      t { p a.send(:priv) }
      t { p a.public_send(:priv) }
      t { p a.respond_to?(:priv) }
      t { p a.respond_to?(:priv, true) }

      class Account
        def initialize(b); @balance = b; end
        def >(other); balance > other.balance; end
        def bigger_than_all?(others); others.all? { |o| balance > o.balance } end
        def self.peek(a); a.balance; end
        def peek_self; self.balance; end
        def peek_new; Account.new(0).secret; end
        def to_s; "acct:#{secret}"; end
        protected
        def balance; @balance; end
        private
        def secret; 42; end
        public
        def open; :open; end
        alias_method :hidden, :secret
      end
      class Savings < Account
        def cmp(o); balance > o.balance; end
        def poke(o); o.secret; end
      end
      acct = Account.new(10); s = Savings.new(5)
      t { p acct > s }
      t { p acct.bigger_than_all?([s, Account.new(1)]) }
      t { p Account.peek(acct) }
      t { p acct.peek_self }
      t { p acct.peek_new }
      t { p acct.balance }
      t { p acct.secret }
      t { p acct.open }
      t { p acct.hidden }
      t { p s.cmp(acct) }
      t { p s.poke(acct) }
      t { p acct.to_s }
      t { p s.balance }

      begin
        acct.secret
      rescue NoMethodError => e
        p [e.name, e.receiver.class]
      end
      class Cfg
        attr_writer :w
        private :w=
        def set(v); self.w = v; end
      end
      cfg = Cfg.new
      t { cfg.w = 6 }
      t { p(cfg.w = 7) }
      p cfg.set(8)
      module Hidden
        private def mpriv; :mpriv; end
        protected def mprot; :mprot; end
        def via_self; mpriv; end
        def peer(o); o.mprot; end
      end
      class Host; include Hidden; end
      h = Host.new
      t { p h.mpriv }
      t { p h.mprot }
      t { p h.via_self }
      t { p h.peer(Host.new) }

      # The class-method asymmetry, stated on its own.
      class Vault
        def initialize(n) = @n = n
        def self.peek(v) = v.amount
        def self.peek_send(v) = v.send(:amount)
        def compare(other) = amount <=> other.amount
        protected
        def amount = @n
      end
      module Helper
        def self.peek(v) = v.amount
      end
      class SubVault < Vault; end

      t { p Vault.peek(Vault.new(1)) }
      t { p Vault.peek_send(Vault.new(1)) }
      t { p Helper.peek(Vault.new(1)) }
      t { p Vault.new(2).compare(Vault.new(1)) }
      t { p SubVault.new(2).compare(Vault.new(1)) }
      t { p Vault.new(2).compare(SubVault.new(1)) }
      t { p Vault.new(1).amount }
      class << Vault
        def peek_singleton(v) = v.amount
      end
      t { p Vault.peek_singleton(Vault.new(1)) }
    RUBY

    _(result).must_answer <<~'OUT'
      :pub
      NoMethodError: private method 'priv' called for an instance
      NoMethodError: protected method 'prot' called for an instan
      NoMethodError: private method 'sec' called for an instance 
      :priv
      :priv
      :prot
      :priv
      NoMethodError: private method 'priv' called for an instance
      false
      true
      true
      true
      NoMethodError: protected method 'balance' called for an ins
      10
      NoMethodError: private method 'secret' called for an instan
      NoMethodError: protected method 'balance' called for an ins
      NoMethodError: private method 'secret' called for an instan
      :open
      NoMethodError: private method 'hidden' called for an instan
      false
      NoMethodError: private method 'secret' called for an instan
      "acct:42"
      NoMethodError: protected method 'balance' called for an ins
      [:secret, Account]
      NoMethodError: private method 'w=' called for an instance o
      NoMethodError: private method 'w=' called for an instance o
      8
      NoMethodError: private method 'mpriv' called for an instanc
      NoMethodError: protected method 'mprot' called for an insta
      :mpriv
      :mprot
      NoMethodError: protected method 'amount' called for an inst
      1
      NoMethodError: protected method 'amount' called for an inst
      1
      1
      1
      NoMethodError: protected method 'amount' called for an inst
      NoMethodError: protected method 'amount' called for an inst
    OUT
  end
end
