# frozen_string_literal: true

require "spec_helper"

describe "Object: defining and naming methods" do
  it "alias inside class self is a class method alias" do
    result = ze0(<<~'RUBY')
      # `alias new old` inside `class << self` aliases a SINGLETON method: it
      # must resolve against the class-method table and register `new` as a class
      # method, not an instance method.

      module M
        def self.original = 42
        class << self
          alias renamed original
        end
      end
      puts M.renamed
      puts M.respond_to?(:renamed)
      puts M.singleton_methods.include?(:renamed)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      true
      true
    OUT
  end

  it "alias of a method touching an ivar works through either name" do
    _(ze0(<<~'RUBY')).must_answer "3\n"
      class Counter
        def initialize
          @count = 0
        end
        def increment
          @count += 1
        end
        alias inc increment
        def value
          @count
        end
      end
      c = Counter.new
      c.inc
      c.inc
      c.increment
      puts c.value
    RUBY
  end

  it "basic object method missing" do
    result = ze0(<<~'RUBY')
      # A `BasicObject` subclass's `method_missing` is never reached: zeo raises
      # `NoMethodError` from the send instead of calling it.
      #
      # `BasicObject` is the blank slate you inherit from precisely to catch
      # everything -- it has seven methods, so almost every call is a miss, and
      # `method_missing` is the whole mechanism. Every proxy/delegator built this way
      # (`Delegator`, `BasicObject`-rooted builders, the classic `NullObject`) stops
      # working.
      #
      # The same class rooted at `Object` DOES reach its `method_missing` (the second
      # pair below), so the fallback exists and the BasicObject-rooted case misses
      # it. `dispatch::send_in_reason` looks the hook up through the receiver's
      # registry chain; a BasicObject subclass's chain is the one place that lookup
      # does not find a user row.

      class Blank < BasicObject
        def method_missing(name, *args) = [:blank_mm, name, args]
        def respond_to_missing?(name, priv = false) = true
      end

      b = Blank.new
      p b.anything
      p b.with(1, 2)
      p b.respond_to?(:whatever)

      # Rooted at Object, the same shape already works.
      class Normal
        def method_missing(name, *args) = [:normal_mm, name, args]
        def respond_to_missing?(name, priv = false) = true
      end
      p Normal.new.anything
      p Normal.new.respond_to?(:whatever)

      p ::BasicObject.instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      [:blank_mm, :anything, []]
      [:blank_mm, :with, [1, 2]]
      [:blank_mm, :respond_to?, [:whatever]]
      [:normal_mm, :anything, []]
      true
      [:!, :!=, :==, :__id__, :__send__, :equal?, :instance_eval, :instance_exec]
    OUT
  end

  it "basicobject send missing" do
    result = ze0(<<~'RUBY')
      # A blank-slate receiver has no #send / #public_send -- only __send__ is
      # BasicObject's own (#2725). The send desugar leaves such calls unretargeted
      # and the blank-slate gate raises CRuby's NoMethodError; __send__ dispatches.
      class BO < BasicObject
        def initialize(x = 0); @x = x; end
        def own; @x; end
      end
      a = BO.new(7)
      r = (a.send(:own) rescue $!.class)
      p r
      r2 = (a.public_send(:own) rescue $!.class)
      p r2
      p a.__send__(:own)
      # ordinary receivers keep the whole surface
      class W; def hi(x); "hi:#{x}"; end; end
      w = W.new
      p w.send(:hi, 1)
      p w.send("hi", 2)
      p w.__send__(:hi, 3)
      p 5.send(:+, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
      NoMethodError
      7
      "hi:1"
      "hi:2"
      "hi:3"
      7
    OUT
  end

  it "class method method missing" do
    result = ze0(<<~'RUBY')
      # `method_missing` defined as a CLASS method is never consulted: zeo raises
      # NoMethodError for the missing class method instead of routing to it. Both
      # spellings are affected -- `def self.method_missing` and a `method_missing`
      # inside `class << self`.
      #
      # This is the whole public API of some gems. Faker's is one call away from it:
      #
      #   Faker::Name.first_name   # => Faker::Base.method_missing(:first_name)
      #
      # Ruby prints the two "flex" lines below.

      class Base
        class << self
          def method_missing(name, *args)
            return "flex #{name}" if name.to_s.start_with?("m_")
            super
          end

          def respond_to_missing?(name, include_private = false)
            name.to_s.start_with?("m_") || super
          end
        end
      end

      class Plain
        def self.method_missing(name, *args)
          return "flex2 #{name}" if name.to_s.start_with?("m_")
          super
        end
      end

      p Base.m_colour
      p Plain.m_size
      p Base.respond_to?(:m_colour)
    RUBY

    _(result).must_answer <<~'OUT'
      "flex m_colour"
      "flex2 m_size"
      true
    OUT
  end

  it "define singleton method on object and class" do
    result = ze0(<<~'RUBY')
      # A per-object singleton (only that object responds) and a
      # class-level singleton method (a class method).

      class Widget; end
      a = Widget.new
      a.define_singleton_method(:special) { "just me" }
      puts a.special
      puts Widget.new.respond_to?(:special)
      Widget.define_singleton_method(:factory) { "built" }
      puts Widget.factory
    RUBY

    _(result).must_answer <<~'OUT'
      just me
      false
      built
    OUT
  end

  it "dup dispatches dynamically through send" do
    _(ze0(<<~'RUBY')).must_answer "2\n"
      puts [1, 2].send(:dup).length
    RUBY
  end

  it "dup drops singleton" do
    result = ze0(<<~'RUBY')
      # `#dup` drops the singleton methods, so the copy is an instance of the class
      # Ruby sees. The copy is made by assigning the whole struct, which carried the
      # ORIGINAL's cls_id -- for a singleton receiver that is the synthesized
      # subclass -- so the copy answered the singleton's methods at run time while
      # `respond_to?`, reading the static type, said it did not (#4043).
      class Sing
        def base = 1
      end

      o = Sing.new
      def o.extra = 99

      p o.extra
      p((o.dup.extra rescue $!.class))
      p o.dup.respond_to?(:extra)
      p o.dup.base
      p o.dup.class
      p o.respond_to?(:extra)

      # clone KEEPS them, as CRuby does
      p o.clone.extra
      p o.clone.respond_to?(:extra)

      # a module extended onto the object goes the same way
      module Loud
        def shout = "LOUD"
      end
      q = Sing.new
      q.extend(Loud)
      p q.shout
      p((q.dup.shout rescue $!.class))
      p q.clone.shout

      # a plain object with no singleton is unaffected
      r = Sing.new
      p r.dup.base
      p r.dup.class
    RUBY

    _(result).must_answer <<~'OUT'
      99
      NoMethodError
      false
      1
      Sing
      true
      99
      true
      "LOUD"
      NoMethodError
      "LOUD"
      1
      Sing
    OUT
  end

  it "dup drops singleton methods" do
    result = ze0(<<~'RUBY')
      class T; def base; 1; end; end
      o = T.new
      def o.extra; 99; end
      d = o.dup
      p d.respond_to?(:extra)
      p o.respond_to?(:extra)
      c = o.clone
      p c.respond_to?(:extra)
      p d.base
      p o.extra
      p c.extra
      p d.class
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      1
      99
      99
      T
    OUT
  end

  it "dynamic send" do
    result = ze0(<<~'RUBY')
      # `recv.send(name)` / `__send__` / `public_send` with a NON-literal name dispatches
      # over the method names that appear as symbol/string literals in the program. The
      # receiver's type bounds which names resolve; the argument count selects the arm.
      # A name not in that set (or not a method on the receiver) raises NoMethodError.
      def s(x); x; end

      # symbol held in a local
      a = s([3, 1, 2])
      m = :sort
      p a.send(m)              # [1, 2, 3]
      m = :length
      p a.send(m)             # 3
      m = :first
      p a.send(m)             # 3

      # argument count selects the arm (push needs one arg; first takes none)
      b = s([1, 2])
      op = :push
      b.send(op, 9)
      p b                     # [1, 2, 9]

      # string name held in a local (interns to the same method)
      nm = "reverse"
      p s([1, 2, 3]).send(nm)   # [3, 2, 1]

      # dynamically chosen among a set, on a typed (literal) string receiver
      %w[upcase reverse].each { |k| p "abc".send(k) }   # "ABC", "cba"

      # __send__ and public_send aliases
      p a.__send__(:max)      # 3
      p a.public_send(:min)   # 1

      # a name that is not a method on the receiver raises NoMethodError
      bad = :no_such_method
      begin
        a.send(bad)
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      3
      3
      [1, 2, 9]
      [3, 2, 1]
      "ABC"
      "cba"
      3
      1
      NoMethodError
    OUT
  end

  it "dynamic send carries a block through to a yield using method" do
    _(ze0(<<~'RUBY')).must_answer "6\n"
      class Collector
        def each_num(a, b, c)
          yield a
          yield b
          yield c
        end
      end
      total = 0
      Collector.new.send(:each_num, 1, 2, 3) { |n| total += n }
      puts total
    RUBY
  end

  it "issue method missing dynamic class body" do
    _(ze0(<<~'RUBY')).must_answer "\"mm:foo:[1, 2]\"\n"
      # method_missing defined inside a `Class.new { ... }` block isn't wired up as
      # the receiver's dispatch fallback; zeo raises NoMethodError for the unknown
      # method instead of routing it to method_missing.
      klass = Class.new do
        def method_missing(name, *args)
          "mm:#{name}:#{args}"
        end
      end
      p klass.new.foo(1, 2)
    RUBY
  end

  it "issue respond to private default" do
    result = ze0(<<~'RUBY')
      # Object#respond_to?(:name) (the one-argument form) should return false for
      # a private method -- only the two-argument form (`respond_to?(:name,
      # true)`) should include private methods. zeo returns true in both cases,
      # not distinguishing the default `include_all` value.
      klass = Class.new do
        private

        def secret; end
      end
      p klass.new.respond_to?(:secret)
      p klass.new.respond_to?(:secret, true)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
    OUT
  end

  it "method missing" do
    _(ze0(<<~'RUBY')).must_answer "missing\n"
      class Greeter
        def method_missing(name)
          puts :missing
        end
      end

      Greeter.new.send(:nonexistent)
    RUBY
  end

  it "method missing explicit" do
    result = ze0(<<~'RUBY')
      # method_missing is not honored as a missing-method hook (spinel resolves every
      # call statically), but a class may still define and call it explicitly like any
      # other method. Defining it emits a compile-time warning to stderr.
      class Proxy
        def initialize(label)
          @label = label
        end

        def method_missing(name, *args)
          "#{@label}:#{name}/#{args.length}"
        end
      end

      p = Proxy.new("px")
      puts p.method_missing(:foo)
      puts p.method_missing(:bar, 1, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      px:foo/0
      px:bar/2
    OUT
  end

  it "method missing fallback on a total miss" do
    _(ze0(<<~'RUBY')).must_answer "missing\n"
      class Greeter
        def method_missing(name)
          puts :missing
        end
      end

      Greeter.new.send(:nonexistent)
    RUBY
  end

  it "mixin in the source is the send ruby writes" do
    result = ze0(<<~'RUBY')
      # A whole-program compile records `include M` as a compile-time
      # ancestry EDIT and emits no statement for it. A snippet has no class
      # table to edit into, so analyze must leave the marker alone and the
      # emitter sends it -- receiverless, because ruby's top-level `include`
      # is a private method on `main`.

      module Greeter
        def hello = "hello from #{self.class}"
        def self.included(base) = puts("included into #{base}")
      end
      class Plain; end
      src = "include Greeter"
      Plain.class_eval(src)
      p Plain.new.hello
      p Plain.ancestors.include?(Greeter)
      obj = Object.new
      ext = "extend Greeter"
      obj.instance_eval(ext)
      p obj.hello
    RUBY

    _(result).must_answer <<~'OUT'
      included into Plain
      "hello from Plain"
      true
      "hello from Object"
    OUT
  end

  it "nested send dispatch" do
    result = ze0(<<~'RUBY')
      class Dispatcher
        def greet; "hi"; end
      end
      d = Dispatcher.new
      p d.send(:send, :greet)
      p d.public_send(:public_send, :greet)
      p d.send(:__send__, :greet)
      p d.send(:greet)
    RUBY

    _(result).must_answer <<~'OUT'
      "hi"
      "hi"
      "hi"
      "hi"
    OUT
  end

  it "notimplement stub respond to" do
    result = ze0(<<~'RUBY')
      # `respond_to?` answered TRUE for a method ruby installs as a not-implemented
      # stub, where ruby answers false.
      #
      # CRuby defines the calls a platform lacks (`Kernel#syscall` on macOS,
      # `Process::Sys.setresuid` where the syscall is absent) with
      # `rb_f_notimplement`, and tells such an entry apart by its implementation
      # IDENTITY. The entry is still LISTED -- `private_instance_methods` and
      # `singleton_methods` carry it, and `instance_method(:syscall).arity` answers
      # 0 -- but `respond_to?` reports false, which is how a program is meant to
      # detect the absence before calling.
      #
      # zeo names the rows instead (`dispatch::is_notimplement_row`). The question is
      # asked at `respond_to?`'s own entry rather than in `responds_to`, which doubles
      # as an EXISTENCE predicate: a stub does exist, so `instance_method` must still
      # build an `UnboundMethod` for it.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      STUBS = [
        ["Kernel#syscall", -> { syscall(999_999) }],
        ["Process::Sys.setresuid", -> { Process::Sys.setresuid(0, 0, 0) }],
        ["Process::Sys.setresgid", -> { Process::Sys.setresgid(0, 0, 0) }]
      ].freeze

      # `respond_to?` says no, in both the instance and the singleton form.
      show("respond_to? syscall") { respond_to?(:syscall, true) }
      show("respond_to? syscall public") { respond_to?(:syscall) }
      show("Process::Sys.respond_to? setresuid") { Process::Sys.respond_to?(:setresuid) }
      show("Process::Sys.respond_to? setresgid") { Process::Sys.respond_to?(:setresgid) }

      # ...while every listing still carries them, which is what makes this a missing
      # BIT rather than a missing method.
      show("listed as private") { Kernel.private_instance_methods(false).include?(:syscall) }
      show("listed as singleton") { Kernel.singleton_methods(false).include?(:syscall) }
      show("private_method_defined?") { Kernel.private_method_defined?(:syscall) }
      show("arity") { Kernel.instance_method(:syscall).arity }
      show("owner") { Kernel.instance_method(:syscall).owner }
      show("Sys singleton listing") { Process::Sys.singleton_methods(false).include?(:setresuid) }

      # A name that is NOT a stub is unaffected, on the same modules.
      show("respond_to? puts") { respond_to?(:puts, true) }
      show("Process::Sys.respond_to? getuid") { Process::Sys.respond_to?(:getuid) }

      # Every listed stub must actually refuse -- the check that stops the table in
      # `is_notimplement_row` from going stale by having a body implemented out from
      # under it.
      STUBS.each do |name, call|
        call.call
        puts "#{name}: DID NOT RAISE"
      rescue NotImplementedError => e
        puts "#{name}: #{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      respond_to? syscall: false
      respond_to? syscall public: false
      Process::Sys.respond_to? setresuid: false
      Process::Sys.respond_to? setresgid: false
      listed as private: true
      listed as singleton: true
      private_method_defined?: false
      arity: 0
      owner: Kernel
      Sys singleton listing: true
      respond_to? puts: true
      Process::Sys.respond_to? getuid: true
      Kernel#syscall: NotImplementedError: syscall() function is unimplemented on this machine
      Process::Sys.setresuid: NotImplementedError: setresuid() function is unimplemented on this machine
      Process::Sys.setresgid: NotImplementedError: setresgid() function is unimplemented on this machine
    OUT
  end

  it "public send" do
    result = ze0(<<~'RUBY')
      # Issue #735. `recv.public_send(:meth, args)` should be identical to
      # `recv.send(:meth, args)` in spinel (visibility is not modeled in
      # static dispatch). The parser textually rewrites `.send(:foo)` and
      # `.__send__(:foo)` to `.foo`; now `.public_send(:foo)` (and the
      # string-form variant) take the same shortcut.

      puts "hello".public_send(:upcase)
      puts "world".public_send("upcase")
      puts 42.public_send(:to_s)

      # __send__ also keeps working (existing path).
      puts "x".__send__(:upcase)
    RUBY

    _(result).must_answer <<~'OUT'
      HELLO
      WORLD
      42
      X
    OUT
  end

  it "public send enforces visibility at runtime" do
    result = ze0(<<~'RUBY')
      # `public_send` is stricter than an ordinary explicit-receiver call: it
      # rejects private AND protected, with no self-relatedness relaxation,
      # because CRuby implements it by passing `Qundef` as the caller's self
      # (vm_eval.c:1230) -- a sentinel nothing can be a kind of. This is a
      # RUNTIME check (rb_method_call_status), so the program must compile and
      # the NoMethodError must be rescuable. Covers explicit-receiver, implicit
      # self, and a runtime-computed method name.

      def err
        yield
      rescue NoMethodError => e
        "#{e.class}: #{e.message}"
      end
      class Acct
        def balance = 100
        def peer_check(other) = other.guarded
        protected
        def guarded = "prot"
        private
        def secret = 42
      end
      class Inner
        def run = public_send(:hidden)
        private
        def hidden = 1
      end
      def dyn(o, m) = o.public_send(m)
      a = Acct.new
      p a.public_send(:balance)
      puts err { a.public_send(:secret) }
      puts err { a.public_send(:guarded) }
      p a.send(:secret)
      p a.peer_check(Acct.new)
      puts err { Inner.new.run }
      puts err { dyn(a, :secret) }
    RUBY

    _(result).must_answer <<~'OUT'
      100
      NoMethodError: private method 'secret' called for an instance of Acct
      NoMethodError: protected method 'guarded' called for an instance of Acct
      42
      "prot"
      NoMethodError: private method 'hidden' called for an instance of Inner
      NoMethodError: private method 'secret' called for an instance of Acct
    OUT
  end

  it "public send keeps the barrier up" do
    result = ze0(<<~'RUBY')
      # `send`/`__send__` are deliberately visibility-blind. `public_send` is not:
      # ruby resolves the target and refuses a non-public one with a rescuable
      # NoMethodError, with NONE of the relaxations an ordinary explicit-receiver
      # call gets -- no literal-`self` exemption, no protected relatedness.

      class Acct
        def initialize(n) = @n = n
        def pub = :pub
        def compare(other) = other.public_send(:guarded)
        def own = public_send(:secret)
        protected def guarded = :prot
        private def secret = :shh
      end

      def try
        yield
      rescue NoMethodError => e
        [e.class, e.message]
      end

      a = Acct.new(1)
      p a.public_send(:pub)
      p a.send(:secret)
      p a.__send__(:secret)
      p(try { a.public_send(:secret) })
      p(try { a.public_send(:guarded) })

      # A name computed at run time takes the same route.
      n = "secret"
      p(try { a.public_send(n) })
      p a.send(n)

      # A receiverless `public_send` still enforces it: ruby checks the RESOLVED
      # entry with a public scope, which has nothing to do with whether the site
      # wrote a receiver.
      p(try { a.own })

      # ...and protected relatedness does NOT relax it, even between two instances
      # of the same class.
      p(try { a.compare(Acct.new(2)) })

      # A public method reached through either spelling is just a call.
      p a.public_send(:pub)
      p a.send(:pub)

      # No name at all.
      p(begin
        a.public_send
      rescue ArgumentError => e
        [e.class, e.message]
      end)
    RUBY

    _(result).must_answer <<~'OUT'
      :pub
      :shh
      :shh
      [NoMethodError, "private method 'secret' called for an instance of Acct"]
      [NoMethodError, "protected method 'guarded' called for an instance of Acct"]
      [NoMethodError, "private method 'secret' called for an instance of Acct"]
      :shh
      [NoMethodError, "private method 'secret' called for an instance of Acct"]
      [NoMethodError, "protected method 'guarded' called for an instance of Acct"]
      :pub
      :pub
      [ArgumentError, "no method name given"]
    OUT
  end

  it "public send still enforces visibility unlike send" do
    result = ze0(<<~'RUBY')
      # Same intent as when this asserted a compile-time panic, now asserting
      # the CORRECT mechanism: real Ruby resolves visibility at call time
      # (`rb_method_call_status`, vm_eval.c:837) and raises a rescuable
      # NoMethodError. Rejecting it during codegen was wrong -- it killed any
      # program that merely mentions such a call, even in a rescued branch --
      # so the program must now compile and the raise must be catchable, while
      # `send` stays visibility-blind.

      class Box
        private

        def secret
          "shh"
        end
      end

      begin
        puts Box.new.public_send(:secret)
      rescue NoMethodError => e
        puts e.message
      end
      puts Box.new.send(:secret)
    RUBY

    _(result).must_answer <<~'OUT'
      private method 'secret' called for an instance of Box
      shh
    OUT
  end

  it "public send visibility" do
    result = ze0(<<~'RUBY')
      # public_send dispatches only public methods: a private or protected target
      # raises NoMethodError with CRuby's message, while send/__send__ stay
      # visibility-blind.
      def err
        yield
      rescue NoMethodError => e
        "#{e.class}: #{e.message}"
      end

      class Acct
        def balance = 100
        def show(label) = "#{label}: #{balance}"

        def peer_check(other) = other.guarded

        protected

        def guarded = "prot"

        private

        def secret = 42
      end

      a = Acct.new
      p a.public_send(:balance)
      p a.public_send(:show, "acct")
      p a.public_send("balance")
      puts err { a.public_send(:secret) }
      puts err { a.public_send("secret") }
      puts err { a.public_send(:guarded) }

      # send / __send__ ignore visibility
      p a.send(:secret)
      p a.__send__(:secret)

      # protected still callable through peer dispatch
      p a.peer_check(Acct.new)

      # receiverless public_send of a private method raises too
      class Inner
        def run = public_send(:hidden)
        private
        def hidden = 1
      end
      puts err { Inner.new.run }

      # runtime-computed name: visibility enforced per resolved arm
      def dyn(o, m) = o.public_send(m)
      p dyn(a, :balance)
      puts err { dyn(a, :secret) }
    RUBY

    _(result).must_answer <<~'OUT'
      100
      "acct: 100"
      100
      NoMethodError: private method 'secret' called for an instance of Acct
      NoMethodError: private method 'secret' called for an instance of Acct
      NoMethodError: protected method 'guarded' called for an instance of Acct
      42
      42
      "prot"
      NoMethodError: private method 'hidden' called for an instance of Inner
      100
      NoMethodError: private method 'secret' called for an instance of Acct
    OUT
  end

  it "respond to class builtins" do
    result = ze0(<<~'RUBY')
      # A class/module object responds to the builtin Class/Module methods it
      # inherits (:name, :new, :instance_methods, :superclass, ...), not only its
      # user-defined singleton methods.
      class Foo
        def self.custom; end
      end
      module Bar
        def self.helper; end
      end
      puts Foo.respond_to?(:new)               # true
      puts Foo.respond_to?(:name)              # true
      puts Foo.respond_to?(:instance_methods)  # true
      puts Foo.respond_to?(:superclass)        # true
      puts Foo.respond_to?(:custom)            # true (user singleton)
      puts Foo.respond_to?(:nope_xyz)          # false
      puts Bar.respond_to?(:new)               # false (module)
      puts Bar.respond_to?(:name)              # true
      puts Bar.respond_to?(:helper)            # true
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      false
      false
      true
      true
      done
    OUT
  end

  it "respond to core class and module" do
    result = ze0(<<~'RUBY')
      # respond_to? on a core class or module had no user class entry to consult, so
      # the fold left the call unresolved: it raised NoMethodError at runtime, and on
      # Thread / Mutex / Fiber the front end rejected it outright. The analyze-time
      # probes already answer this for a primitive receiver; let a constant receiver
      # use them too. A module also answered true for its plain instance methods,
      # which only its module_function ones should do. #3467.
      r1 = (String.respond_to?(:new) rescue $!.class); p r1
      r2 = (Integer.respond_to?(:sqrt) rescue $!.class); p r2
      r3 = (Comparable.respond_to?(:new) rescue $!.class); p r3
      p Thread.respond_to?(:new)
      p Mutex.respond_to?(:new)
      p Fiber.respond_to?(:new)
      p Array.respond_to?(:new)
      p Hash.respond_to?(:new)
      p Math.respond_to?(:sqrt)
      p Enumerable.respond_to?(:new)
      p Float.respond_to?(:nonexistent_thing)

      module Greeter
        def greet = "hi"
        def self.version = 1
        module_function
        def helper = 2
      end
      p Greeter.respond_to?(:version)
      p Greeter.respond_to?(:greet)
      p Greeter.respond_to?(:helper)
      p Greeter.respond_to?(:missing)

      class Host
        include Greeter
        def self.make = new
      end
      p Host.respond_to?(:make)
      p Host.respond_to?(:greet)
      p Host.respond_to?(:new)
      p Host.new.respond_to?(:greet)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      true
      true
      true
      true
      true
      false
      false
      true
      false
      true
      false
      true
      false
      true
      true
    OUT
  end

  it "respond to def self method" do
    result = ze0(<<~'RUBY')
      # def self.m singleton methods must be visible to respond_to? on the
      # class constant, and module_function methods on the module constant.
      class Foo
        def self.bar; 1; end
      end
      puts Foo.respond_to?(:bar)
      puts Foo.respond_to?(:nope)

      module M
        module_function
        def greet; "hi"; end
      end
      puts M.respond_to?(:greet)
      puts M.respond_to?(:nope)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
    OUT
  end

  it "respond to missing and method missing protocol" do
    result = ze0(<<~'RUBY')
      # `respond_to_missing?` is wired into the whole `respond_to?` surface
      # (the codegen folds and the Kernel row), `method(:dyn)` succeeds when the
      # hook admits the name (its Method dispatches through `method_missing`),
      # and `defined?(recv.dyn)` reports "method". The default `method_missing`/
      # `respond_to_missing?` rows are hidden-private (invisible to `methods`,
      # answer `respond_to?` only with `include_all`) and are what an override's
      # `super` reaches -- a bare `super` in `method_missing` raises the real
      # NoMethodError. Output oracle-verified verbatim.

      class R
        def respond_to_missing?(name, include_private = false)
          name.to_s.start_with?("dyn_") || super
        end
        def method_missing(name, *args)
          if name.to_s.start_with?("dyn_")
            "handled #{name}"
          else
            super
          end
        end
      end
      r = R.new
      p r.respond_to?(:dyn_foo)
      p r.respond_to?(:other)
      p r.dyn_foo
      p defined?(r.dyn_foo)
      p defined?(r.other)
      m = r.method(:dyn_bar)
      p m.call
      begin
        r.nope_at_all
      rescue NoMethodError => e
        puts e.message
      end
      o = Object.new
      p o.respond_to?(:method_missing)
      p o.respond_to?(:method_missing, true)
      p Object.new.methods.include?(:respond_to_missing?)
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      "handled dyn_foo"
      "method"
      nil
      "handled dyn_bar"
      undefined method 'nope_at_all' for an instance of R
      false
      true
      false
      done
    OUT
  end

  it "respond to module singleton accessor" do
    result = ze0(<<~'RUBY')
      # class << self; attr_accessor :x on a module must be visible to
      # respond_to? for both the reader and the writer.
      module Foo
        class << self
          attr_accessor :x
        end
      end
      puts Foo.respond_to?(:x)
      puts Foo.respond_to?(:x=)
      puts Foo.respond_to?(:nope)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
    OUT
  end

  it "respond to nil slot" do
    result = ze0(<<~'RUBY')
      # respond_to? on a nil that arrived through a slot: the literal receiver
      # folded at compile time, the slot did not, and answered a flat false (#3815).
      a = nil
      p a.respond_to?(:to_a)
      p a.respond_to?(:to_i)
      p a.respond_to?(:inspect)
      p a.respond_to?(:definitely_not_a_method)
      p nil.respond_to?(:to_a)
      xs = [nil, 1]
      p xs[0].respond_to?(:to_a)
      b = true
      p b.respond_to?(:&)
      p b.respond_to?(:definitely_not)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      true
      true
      true
      false
    OUT
  end

  it "respond to poly" do
    result = ze0(<<~'RUBY')
      # respond_to?(:m) on a poly receiver must answer per runtime value, not from a
      # union-wide static approximation.
      #
      # `value.respond_to?(:to_css) ? value.to_css : value` where value is a String
      # from some call sites and a #to_css-defining user class from others: the
      # analyze probe types `value.to_css` (Color defines it) and reported a static
      # true, so the String took the wrong branch and returned "" instead of itself.
      #
      # Fix: for a poly receiver whose method is defined by a user class, emit a
      # runtime cls_id check (like the poly is_a? path) -- a builtin value, which
      # cannot define a user protocol method, answers false.

      class Color
        def initialize(s) = (@s = s)
        def to_css = @s
      end
      class Named
        def initialize(n) = (@n = n)
        def to_css = "named-#{@n}"
      end

      def coerce(value) = value.respond_to?(:to_css) ? value.to_css : value

      # 1. A String member takes the else branch (returns itself).
      p coerce("#fef6e0")               #=> "#fef6e0"
      # 2. A #to_css-defining member responds.
      p coerce(Color.new("#abc"))       #=> "#abc"
      # 3. A second class defining the method also responds.
      p coerce(Named.new("red"))        #=> "named-red"

      # 4. A method no class defines: false for every runtime value.
      def has_bogus(v) = v.respond_to?(:nonexistent_xyz)
      p has_bogus("s")                  #=> false
      p has_bogus(Color.new("x"))       #=> false

      # 5. A universal Object method: true for every value.
      def has_to_s(v) = v.respond_to?(:to_s)
      p has_to_s("s")                   #=> true
      p has_to_s(Color.new("x"))        #=> true
      p has_to_s(42)                    #=> true

      # 6. Concrete (non-poly) receivers are unaffected.
      p "hi".respond_to?(:upcase)       #=> true
      p Color.new("z").respond_to?(:to_css)  #=> true
      p 5.respond_to?(:to_css)          #=> false

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      "#fef6e0"
      "#abc"
      "named-red"
      false
      false
      true
      true
      true
      true
      true
      false
      done
    OUT
  end

  it "respond to primitive" do
    result = ze0(<<~'RUBY')
      # Issue #716. `<primitive>.respond_to?(name)` should answer true for
      # the common method set, not just for obj-typed receivers. The compile-
      # time approximation uses a conservative allowlist of universal methods.

      puts 1.respond_to?(:to_s)
      puts "x".respond_to?(:class)
      puts :s.respond_to?(:inspect)
      puts 1.5.respond_to?(:nil?)
      puts [].respond_to?(:dup)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
    OUT
  end

  it "respond to primitives" do
    result = ze0(<<~'RUBY')
      # respond_to? on built-in (primitive) receivers, answered at compile time by
      # probing spinel's own method resolution -- no hand-maintained method list.
      # Per-type helpers keep each receiver's concrete type (a single shared helper
      # would widen every receiver to a poly value, whose runtime class isn't static).
      def st(x); x; end
      def si(x); x; end
      def sf(x); x; end
      def sa(x); x; end
      def sh(x); x; end
      def sy(x); x; end

      # String: no-arg, operator, index, block iterator, String-form argument, absent
      p st("hi").respond_to?(:upcase)      # true
      p st("hi").respond_to?(:+)           # true
      p st("hi").respond_to?(:each_char)   # true
      p st("hi").respond_to?("downcase")   # true
      p st("hi").respond_to?(:no_such)     # false
      p st("hi").respond_to?(:push)        # false

      # Integer: block-returning-self, operator, Comparable mixin, absent
      p si(5).respond_to?(:times)          # true
      p si(5).respond_to?(:+)              # true
      p si(5).respond_to?(:between?)       # true
      p si(5).respond_to?(:upcase)         # false

      # Float
      p sf(1.5).respond_to?(:ceil)         # true
      p sf(1.5).respond_to?(:round)        # true

      # Array: self-returning iterators, map, operator, absent
      p sa([1, 2]).respond_to?(:each)             # true
      p sa([1, 2]).respond_to?(:each_with_index)  # true
      p sa([1, 2]).respond_to?(:map)              # true
      p sa([1, 2]).respond_to?(:reverse_each)     # true
      p sa([1, 2]).respond_to?(:upcase)           # false

      # Hash: iterators + lookups
      p sh({a: 1}).respond_to?(:each)      # true
      p sh({a: 1}).respond_to?(:each_pair) # true
      p sh({a: 1}).respond_to?(:key?)      # true
      p sh({a: 1}).respond_to?(:fetch)     # true
      p sh({a: 1}).respond_to?(:upcase)    # false

      # Symbol
      p sy(:foo).respond_to?(:upcase)      # true
      p sy(:foo).respond_to?(:to_sym)      # true
      p sy(:foo).respond_to?(:each)        # false

      # Kernel/Object universals resolve for any receiver
      p st("x").respond_to?(:class)        # true
      p si(5).respond_to?(:frozen?)        # true
      p sa([1]).respond_to?(:tap)          # true

      # literal receivers (already concrete-typed)
      p nil.respond_to?(:to_a)             # true
      p nil.respond_to?(:upcase)           # false
      p true.respond_to?(:&)               # true
      p (1..3).respond_to?(:each)          # true
      p (1..3).respond_to?(:map)           # true
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
      false
      true
      true
      true
      true
      true
      true
      false
      true
      true
      true
      true
      false
      true
      true
      false
      true
      true
      true
      true
      false
      true
      true
      true
    OUT
  end

  it "respond to sees class and module singleton methods" do
    result = ze0(<<~'RUBY')
      # respond_to? on a class/module value must see user `def self.x`,
      # module_function, and class<<self accessors, plus inherited builtin
      # Class methods -- but a module never responds to :new.

      class Foo
        def self.custom; end
      end
      module Bar
        def self.helper; end
        module_function
        def mf; end
      end
      module Acc
        class << self
          attr_accessor :x
        end
      end
      puts Foo.respond_to?(:new)
      puts Foo.respond_to?(:custom)
      puts Foo.respond_to?(:name)
      puts Foo.respond_to?(:nope_xyz)
      puts Bar.respond_to?(:new)
      puts Bar.respond_to?(:helper)
      puts Bar.respond_to?(:mf)
      puts Acc.respond_to?(:x)
      puts Acc.respond_to?(:x=)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      true
      true
      true
      true
    OUT
  end

  it "respond to walks the mro" do
    result = ze0(<<~'RUBY')
      # `respond_to?` walks the real MRO now: Enumerable names answer true on
      # arrays, Comparable names on strings, and Kernel privates stay invisible.

      puts [1, 2].respond_to?(:map)
      puts "s".respond_to?(:between?)
      puts 5.respond_to?(:puts)
      puts 5.respond_to?(:itself)
      puts "s".respond_to?(:nope)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
    OUT
  end

  it "send bypasses visibility entirely" do
    _(ze0(<<~'RUBY')).must_answer "shh\n"
      class Box
        private

        def secret
          "shh"
        end
      end

      puts Box.new.send(:secret)
    RUBY
  end

  it "send dead code" do
    _(ze0(<<~'RUBY')).must_answer "pressed a\n"
      # A runtime-name send in an unreachable method must NOT abort compilation.
      # Dead code is pruned before codegen, so the send is never emitted; only a
      # send that codegen actually emits is diagnosed. This mirrors a real program
      # that defines a dispatch helper using `send` but never calls it on the
      # compiled entry path.
      class Pad
        def press(button)
          "pressed #{button}"
        end

        # Never called -> dead-code-eliminated. Uses a runtime method name (the
        # `action` parameter), which would otherwise trigger the diagnostic.
        def dispatch(action, button)
          send(action, button)
        end
      end

      puts Pad.new.press(:a)
    RUBY
  end

  it "send literal and user" do
    result = ze0(<<~'RUBY')
      # A literal-name send/public_send is rewritten to a direct call, so it keeps
      # working. A class that defines its own `send` is dispatched normally and is
      # never mistaken for Kernel#send (even with a runtime argument), so the
      # runtime-name diagnostic must not fire for it.
      class Calc
        def double(n)
          n * 2
        end

        def label
          "calc"
        end
      end

      class Mailer
        def send(msg)
          "sent: #{msg}"
        end
      end

      c = Calc.new
      puts c.send(:double, 5)        # literal symbol name -> direct call
      puts c.public_send("label")    # literal string name -> direct call

      m = Mailer.new
      greeting = "hi"
      puts m.send(greeting)          # user-defined Mailer#send, runtime arg
      puts m.send(greeting + "!")    # still the user method, not Kernel#send
    RUBY

    _(result).must_answer <<~'OUT'
      10
      calc
      sent: hi
      sent: hi!
    OUT
  end

  it "send reaches toplevel def" do
    result = ze0(<<~'RUBY')
      # A top-level `def` is Object's PRIVATE instance method, so an explicit receiver
      # cannot reach it -- except through #send, whose whole point is to ignore
      # visibility. Spinel retargets `x.send(:m)` to a plain `x.m` in the analyzer,
      # which is the right lowering but loses exactly the permission that made the
      # call legal, so the top-level method was never found.
      def zork(v) = "top:#{v}"
      def plain = "top-plain"

      class K
        def go = self.send(:zork, 3)
        def bare = send(:zork, 4)
        def noargs = self.send(:plain)
      end

      p K.new.go
      p K.new.bare
      p K.new.noargs
      p send(:zork, 5)

      o = Object.new
      p o.send(:zork, 6)

      # the receiver's own class still answers first
      class Own
        def zork(v) = "class:#{v}"
        def go = self.send(:zork, 7)
      end

      p Own.new.go

      # and send still reaches a private method of the receiver's own class
      class Priv
        def call_it = self.send(:hidden)

        private

        def hidden = "private-hidden"
      end

      p Priv.new.call_it

      # __send__ is the same protocol, and takes the same route now: the textual
      # rewrite that consumed it before the analyzer could stamp it is gone
      class Alias
        def go = self.__send__(:zork, 8)
        def bare = __send__(:zork, 9)
        def own = self.__send__(:mine)
        def hidden_call = self.__send__(:hidden)
        def mine = "class-mine"

        private

        def hidden = "class-hidden"
      end

      a = Alias.new
      p a.go
      p a.bare
      p a.own
      p a.hidden_call
      p Alias.new.__send__("mine")

      # still a BasicObject method, which is why the rewrite was blind to begin with
      class Bare < BasicObject
        def go = __send__(:inner)
        def inner = "basic"
      end

      p Bare.new.go
    RUBY

    _(result).must_answer <<~'OUT'
      "top:3"
      "top:4"
      "top-plain"
      "top:5"
      "top:6"
      "class:7"
      "private-hidden"
      "top:8"
      "top:9"
      "class-mine"
      "class-hidden"
      "class-mine"
      "basic"
    OUT
  end

  it "send traceable name" do
    result = ze0(<<~'RUBY')
      # The statically-traceable send names must keep compiling and running after the
      # genuinely-computed names are loud-rejected. A name is traceable when it is a
      # literal, a variable assigned only literals, or a block parameter bound to
      # program literals -- all of which the static arm set covers.

      # a literal name
      p "hi".send(:upcase)

      # a variable assigned a symbol literal
      m = :upcase
      p "hi".send(m)

      # a variable reassigned among symbol literals
      sel = :reverse
      p [1, 2, 3].send(sel)
      sel = :first
      p [1, 2, 3].send(sel)

      # a block parameter bound to string literals
      %w[upcase reverse].each { |k| p "abc".send(k) }

      # __send__ / public_send aliases with a traceable name
      op = :max
      p [3, 1, 2].__send__(op)
      q = :min
      p [3, 1, 2].public_send(q)

      # a traceable name that isn't a method on the receiver still raises NoMethodError
      bad = :no_such_method
      begin
        "hi".send(bad)
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "HI"
      "HI"
      [3, 2, 1]
      1
      "ABC"
      "cba"
      3
      1
      NoMethodError
    OUT
  end

  it "undef in a singleton body is invisible to respond to" do
    result = ze0(<<~'RUBY')
      class Foo
        class << self
          undef_method :new
        end
      end
      p Foo.respond_to?(:new)
      begin
        Foo.new
      rescue NoMethodError => e
        p e.class
      end

      class Bar; end
      class << Bar
        undef_method :new
      end
      p Bar.respond_to?(:new)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      NoMethodError
      false
    OUT
  end

  it "visibility refusal routes through method missing" do
    result = ze0(<<~'RUBY')
      # A call refused for VISIBILITY raises `NoMethodError` directly instead of
      # going through `method_missing`, so a user hook never sees it.
      #
      # CRuby refuses an explicit-receiver call to a private or protected method by
      # calling `method_missing` with the private/protected reason
      # (`rb_method_call_status` then `rb_vm_call0`'s miss path); the DEFAULT
      # `method_missing` is what turns that into "private method 'x' called for ...".
      # An override intercepts it first -- which is how a delegator or a proxy
      # forwards a name its target keeps private.
      #
      # zeo's refusal sites call `raise_method_missing` directly
      # (`explicit_call_barrier` in `dispatch/caches.rs`, `send_value_public_in` and
      # `refined_send_in` in `dispatch/mod.rs`), which BUILDS the error rather than
      # dispatching the hook. `method_missing_or_raise` -- the miss path for a name
      # nothing defines -- is the shape they should share, and it already exists.
      #
      # The bug is general: the class side has it too, and the per-object singleton
      # side inherits it. All three are pinned here.

      def try(label)
        p [label, yield]
      rescue NoMethodError, NameError => e
        p [label, :raised, e.message]
      end

      class K
        private def hidden = :hidden
        protected def guarded = :guarded
        def method_missing(n, *a) = [:mm, n, a]
        def respond_to_missing?(n, p = false) = true
      end
      try(:cls_private)   { K.new.hidden }
      try(:cls_protected) { K.new.guarded }
      try(:cls_args)      { K.new.hidden(1, 2) }
      try(:cls_public)    { K.new.public_send(:hidden) }

      o = Object.new
      class << o
        private
        def s = :s
        public
        def method_missing(n, *a) = [:mm, n, a]
      end
      try(:sing_private)  { o.s }
      try(:sing_public)   { o.public_send(:s) }

      module MFe
        module_function
        def h = :h
      end
      e = Object.new.extend(MFe)
      def e.method_missing(n, *a) = [:mm, n, a]
      try(:ext_private)   { e.h }

      # With NO hook the message is unchanged.
      class Bare
        private def q = :q
      end
      try(:bare)          { Bare.new.q }

      # A class-level hook catches a private CLASS method the same way.
      class CM
        def self.hidden_cm = :hidden_cm
        private_class_method :hidden_cm
        def self.method_missing(n, *a) = [:cmm, n]
      end
      try(:class_method)  { CM.hidden_cm }
    RUBY

    _(result).must_answer <<~'OUT'
      [:cls_private, [:mm, :hidden, []]]
      [:cls_protected, [:mm, :guarded, []]]
      [:cls_args, [:mm, :hidden, [1, 2]]]
      [:cls_public, [:mm, :hidden, []]]
      [:sing_private, [:mm, :s, []]]
      [:sing_public, [:mm, :s, []]]
      [:ext_private, [:mm, :h, []]]
      [:bare, :raised, "private method 'q' called for an instance of Bare"]
      [:class_method, [:cmm, :hidden_cm]]
    OUT
  end
end
