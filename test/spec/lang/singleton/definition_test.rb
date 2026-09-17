# frozen_string_literal: true

require "spec_helper"

describe "Singleton: defining and naming methods" do
  it "alias and singleton class" do
    result = ze0(<<~'RUBY')
      class Greeter
        def hello
          "hi"
        end
        alias hola hello
        alias :bonjour :hello
      end
      g = Greeter.new
      puts g.hello
      puts g.hola
      puts g.bonjour

      class Animal
        def speak
          "generic"
        end
      end
      class Dog < Animal
        def speak
          "woof"
        end
        alias original_speak speak
      end
      d = Dog.new
      puts d.speak
      puts d.original_speak

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

      class MathUtils
        class << self
          def square(x)
            x * x
          end
          def cube(x)
            x * x * x
          end
        end
      end
      puts MathUtils.square(4)
      puts MathUtils.cube(3)

      module MyMath
        class << self
          def double(x)
            x * 2
          end
        end
      end
      puts MyMath.double(5)

      class Registry
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
      Registry.reset
      Registry.bump
      Registry.bump
      puts Registry.total
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      hi
      hi
      woof
      woof
      3
      16
      27
      10
      2
    OUT
  end

  it "alias on a singleton class copies the visibility" do
    result = ze0(<<~'RUBY')
      # `alias_method` copies the method ENTRY, so the alias carries the source's
      # visibility -- on a singleton class exactly as on a plain one.
      class C
        class << self
          private

          def hidden = :h
        end
      end

      C.singleton_class.alias_method(:secret, :hidden)
      p C.singleton_class.private_instance_methods(false).sort
      begin
        C.secret
      rescue NoMethodError => e
        puts "call: #{e.message}"
      end
      p C.send(:secret)

      # A public source stays public, whatever the alias name carried before.
      class C
        def self.loud = :l
      end
      C.singleton_class.alias_method(:shout, :loud)
      p C.shout
      p C.singleton_class.private_instance_methods(false).sort

      # A per-object singleton, and a plain class, take the same copy.
      subject = Object.new
      def subject.speak = :s
      subject.singleton_class.send(:private, :speak)
      subject.singleton_class.alias_method(:whisper, :speak)
      p subject.singleton_class.private_instance_methods(false).sort

      class Plain
        def h = :h
        private :h
      end
      Plain.alias_method(:s, :h)
      p Plain.private_instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      [:hidden, :secret]
      call: private method 'secret' called for class C
      :h
      :l
      [:hidden, :secret]
      [:speak, :whisper]
      [:h, :s]
    OUT
  end

  it "receiverless call sees the receivers own singleton" do
    result = ze0(<<~'RUBY')
      # A receiverless call inside a method is a send to `self` like any other, and
      # `self` may carry a per-object singleton method that shadows the class's. zeo
      # resolved the receiverless form straight to the class's compiled definition,
      # so the explicit `self.` spelling and a call from outside saw the singleton
      # and the bare name written in the method next door did not.
      class Foo
        def close = "class"

        def implicit = close
        def explicit = self.close
      end

      f = Foo.new
      f.define_singleton_method(:close) { "singleton" }
      p f.close, f.explicit, f.implicit

      # An object WITHOUT the singleton still reaches the class's own method, and the
      # two objects disagree at the same call site.
      g = Foo.new
      p g.close, g.explicit, g.implicit

      # The same question asked of a method the class gains at run time, and of one a
      # per-object `undef` retires. Both reach the receiverless call through the same
      # overlay the singleton does.
      class Bar
        def tag = "compiled"
        def read = tag
      end
      b = Bar.new
      p b.read
      Bar.define_method(:tag) { "redefined" }
      p b.read
      b.define_singleton_method(:tag) { "mine" }
      p b.read, Bar.new.read

      # A singleton method installed with `def obj.name` is the same thing said
      # another way.
      class Baz
        def kind = "class"
        def ask = kind
      end
      z = Baz.new
      def z.kind = "singleton"
      p z.ask, Baz.new.ask
    RUBY

    _(result).must_answer <<~'OUT'
      "singleton"
      "singleton"
      "singleton"
      "class"
      "class"
      "class"
      "compiled"
      "redefined"
      "mine"
      "redefined"
      "singleton"
      "class"
    OUT
  end

  it "singleton alias and civ" do
    result = ze0(<<~'RUBY')
      class C003
        @shown003 = true
        @count003 = 2
        class << self
          attr_reader :shown003
          attr_accessor :count003
          alias_method :shown003?, :shown003
        end
        def self.bump; @count003 += 1; end
      end
      p C003.shown003
      p C003.shown003?
      p C003.count003
      C003.count003 = 7
      p C003.count003
      C003.bump
      p C003.count003

      class D003
        class << self
          attr_accessor :label003
        end
      end
      p D003.label003
      D003.label003 = "hi"
      p D003.label003
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      2
      7
      8
      nil
      "hi"
    OUT
  end

  it "singleton alias inherits its visibility" do
    result = ze0(<<~'RUBY')
      # An `alias_method` on an object's SINGLETON class installs a public row even
      # when its source is private. Ruby gives an alias the visibility of the method
      # it copies, on a singleton exactly as on a class.
      #
      # The class-side rule is already right: `alias_method :y, :x` after
      # `private :x` makes `y` private, and the `class << self` twin does too. The
      # per-object path writes the body into the identity-keyed singleton table and
      # nothing carries the source's mark across with it.

      def try(label)
        p [label, yield]
      rescue NoMethodError, NameError => e
        p [label, :raised, e.class.to_s]
      end

      o = Object.new
      def o.a = :a
      o.singleton_class.send(:private, :a)
      o.singleton_class.send(:alias_method, :b, :a)
      try(:alias_public) { o.public_send(:b) }
      try(:alias_send)   { o.send(:b) }
      try(:singles)      { o.singleton_methods.sort }
      try(:respond)      { o.respond_to?(:b) }

      # A PUBLIC source aliases public.
      q = Object.new
      def q.c = :c
      q.singleton_class.send(:alias_method, :d, :c)
      try(:pub_alias)    { q.public_send(:d) }
      try(:pub_singles)  { q.singleton_methods.sort }

      # The `class << obj; alias new old; end` spelling takes the same route.
      r = Object.new
      def r.e = :e
      r.singleton_class.send(:private, :e)
      class << r
        alias f e
      end
      try(:kw_alias)     { r.public_send(:f) }
      try(:kw_send)      { r.send(:f) }
    RUBY

    _(result).must_answer <<~'OUT'
      [:alias_public, :raised, "NoMethodError"]
      [:alias_send, :a]
      [:singles, []]
      [:respond, false]
      [:pub_alias, :c]
      [:pub_singles, [:c, :d]]
      [:kw_alias, :raised, "NoMethodError"]
      [:kw_send, :e]
    OUT
  end

  it "undef in a reopened singleton applies where it stands" do
    result = ze0(<<~'RUBY')
      # `undef` inside a reopened `class << self` retires the class method WHERE IT
      # STANDS. Recording it as a compile-time fact applied it from program start, so
      # a call written between the two bodies raised.
      class Gone
        def self.away = :here
        def self.stays = :stays
      end

      p Gone.away
      p Gone.respond_to?(:away)

      class Gone
        class << self
          undef away
        end
      end

      begin
        Gone.away
      rescue NoMethodError => e
        p e.class
      end
      p Gone.respond_to?(:away)
      p Gone.singleton_class.method_defined?(:away)
      # Its sibling is untouched.
      p Gone.stays

      # An undef written in the FIRST body still applies from the start.
      class Never
        def self.a = :a
        class << self
          undef a
        end
      end
      begin
        Never.a
      rescue NoMethodError => e
        p [:never, e.class]
      end

      # Two names at once, and a subclass sees the parent's retirement.
      class Multi
        def self.x = :x
        def self.y = :y
      end
      class Sub2 < Multi; end
      p Sub2.x
      class Multi
        class << self
          undef x, y
        end
      end
      begin; Multi.x; rescue NoMethodError => e; p [:multi_x, e.class]; end
      begin; Multi.y; rescue NoMethodError => e; p [:multi_y, e.class]; end
      begin; Sub2.x; rescue NoMethodError => e; p [:sub_x, e.class]; end
    RUBY

    _(result).must_answer <<~'OUT'
      :here
      true
      NoMethodError
      false
      false
      :stays
      [:never, NoMethodError]
      :x
      [:multi_x, NoMethodError]
      [:multi_y, NoMethodError]
      [:sub_x, NoMethodError]
    OUT
  end

  it "undef in a reopened singleton class reaches back" do
    result = ze0(<<~'RUBY')
      # `class << self; undef away; end` written in a LATER reopening retires the
      # class method from that point on. zeo retires it for the whole program, so
      # the call written before the reopening raises NoMethodError instead of
      # answering `:here`.
      #
      # Pre-existing, and unrelated to class-method call-site caching: the same call
      # raises identically with every `Target.name` site uncached. The `undef` is
      # recorded by `class_method_undefined`, and the probe that reads it in
      # `send_value_in_reason` is gated only on `is_live()` -- a whole-program flag
      # with no notion of when the undef ran. Same shape as
      # `a_define_singleton_method_on_a_class_does_not_reach_back.rb`.
      class Gone
        def self.away = :here
      end
      p Gone.away
      class Gone
        class << self
          undef away
        end
      end
      begin
        Gone.away
      rescue NoMethodError
        puts "away is gone"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      :here
      away is gone
    OUT
  end

  it "undef in a singleton body retires it for that object" do
    result = ze0(<<~'RUBY')
      # `undef :close` inside a singleton body retires the name for ONE object. It
      # had no arm in the per-object desugar and fell through to the pass-through
      # catch-all (an `undef` names no `self`), which put a definition-level node
      # where a value belongs -- so zeo refused the whole program with "a
      # definition-level construct used as a VALUE: undef". The refusal was right
      # while there was nowhere for the retirement to be recorded; there is a
      # per-object tombstone now.
      #
      # `class << self` written in a METHOD body opens the singleton of the INSTANCE
      # the method was called on. logging's `def kill` is exactly this, and it is the
      # largest single cluster in the corpus's lowering-gap bucket.
      class Foo
        def close = "class"
        def read = "read"
        def flush = "flush"

        def kill
          class << self
            undef :close
          end
        end
      end

      g = Foo.new
      g.kill
      p g.respond_to?(:close)
      p(begin
        g.close
      rescue NoMethodError
        :raised
      end)
      p g.read
      p Foo.new.close

      # The `class << obj` spelling of the same thing, and the multi-name form:
      # `undef a, b` names them in one statement and `undef_method` takes them in one
      # call.
      a = Foo.new
      class << a
        undef :close, :read
      end
      p a.respond_to?(:close), a.respond_to?(:read), a.flush

      # An `alias` in a singleton body copies the definition the RECEIVER would have
      # run, and the copy survives the original's retirement. zeo wrote the copy into
      # an instance table the singleton id never had, where no send for that object
      # looks -- so `c.shut` raised where ruby answers.
      c = Foo.new
      class << c
        alias shut close
        undef :close
      end
      p c.shut
      p(begin
        c.close
      rescue NoMethodError
        :raised
      end)
      p Foo.new.close
    RUBY

    _(result).must_answer <<~'OUT'
      false
      :raised
      "read"
      "class"
      false
      false
      "flush"
      "class"
      :raised
      "class"
    OUT
  end
end
