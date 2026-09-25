# frozen_string_literal: true

require "spec_helper"

describe "Modules programs" do
  it "bare arg in module body" do
    result = zr(<<~'RUBY')
      # Inside a `module M` body, a bare method-name argument (`M.use(h)`,
      # where `h` resolves to `M.h`) takes the return type of `M.h`, a
      # Hash. So `opts.length` in the called method answers the Hash size.

      module M
        def self.h
          {"" => ""}
        end
        def self.use(opts)
          opts.length
        end
        M.use(h)
      end

      puts M.use(M.h)
    RUBY

    _(result).must_answer "1\n"
  end

  it "class shift self works inside a module" do
    result = zr(<<~'RUBY')
      module MyMath
        class << self
          def double(x)
            x * 2
          end
        end
      end
      puts MyMath.double(5)
    RUBY

    _(result).must_answer "10\n"
  end

  it "codegen class in module with explicit parent" do
    result = zr(<<~'RUBY')
      # A `class Sub < Parent` written inside a single-level `module M`.
      # The compiler resolves the parent class, and the class works.

      module M
        class Sub < Object
          def hello; puts "hi"; end
        end
      end
      M::Sub.new.hello
    RUBY

    _(result).must_answer "hi\n"
  end

  it "included, extended, prepended and inherited each fire after the edit they report" do
    result = zr(<<~'RUBY')
      # `Module#included`/`#extended`/`#prepended` and `Class#inherited` -- the four
      # hooks a mixin or a subclass fires as it is written. The extend-on-include
      # idiom below (a module giving its host class-side methods) is what
      # ActiveSupport::Concern, Syslog::Constants, and most every Ruby DSL are built
      # out of, so a module whose `included` never ran left its host without them.
      #
      # Each hook runs AFTER the edit it reports, at the mixin's own document
      # position, and `inherited` runs once per class -- at creation, not per reopen.

      module Hooked
        def hi = "instance"

        def self.included(base)
          puts "included #{base}"
          base.extend(self)
        end

        def self.extended(base)
          puts "extended #{base}"
        end

        def self.prepended(base)
          puts "prepended #{base}"
        end
      end

      class Host
        puts "body starts"
        include Hooked
        puts "body ends"
      end

      p Host.new.hi
      p Host.hi

      class Extender
        extend Hooked
      end
      p Extender.hi

      class Prepender
        prepend Hooked
      end
      p Prepender.new.hi

      # A module with no hook stays silent, and the mixin still works.
      module Quiet
        def quiet = "quiet"
      end
      class Silent
        include Quiet
      end
      p Silent.new.quiet

      # --- `included` sees the ancestry the edit already made ---------------------
      module Reflective
        def self.included(base)
          p base.ancestors.include?(Reflective)
          p base.instance_methods(false).sort
        end

        def helper = 1
      end
      class Reflected
        def own = 2
        include Reflective
      end

      # --- `inherited` fires once, at creation ------------------------------------
      class Tracked
        def self.inherited(sub)
          puts "inherited #{sub}"
          super
        end
      end
      class ChildA < Tracked; end
      class ChildB < Tracked
        puts "child b body"
      end
      class ChildB
        puts "child b reopened"
      end
      class GrandChild < ChildA; end

      # --- the runtime shapes fire too --------------------------------------------
      # An anonymous class and a bare object both print an address, so these report
      # only WHICH hook ran.
      module Counting
        def self.seen = (@seen ||= [])
        def self.included(base) = seen << :included
        def self.extended(base) = seen << :extended
        def self.prepended(base) = seen << :prepended
        def counted = "counted"
      end

      runtime = Class.new do
        include Counting
      end
      p runtime.new.counted

      obj = Object.new
      obj.extend(Counting)
      p obj.counted
      p Counting.seen
    RUBY

    _(result).must_answer <<~'OUT'
      body starts
      included Host
      extended Host
      body ends
      "instance"
      "instance"
      extended Extender
      "instance"
      prepended Prepender
      "instance"
      "quiet"
      true
      [:own]
      inherited ChildA
      inherited ChildB
      child b body
      child b reopened
      inherited GrandChild
      "counted"
      "counted"
      [:included, :extended]
    OUT
  end

  it "dynamic new skips modules" do
    result = zr(<<~'RUBY')
      # `k.new` where k is a Class value switches over the classes that could be
      # there. A MODULE has no `new`, so the switch leaves modules out.
      module Counted
        def initialize
          @n = 7
        end
        def n = @n
      end
      class Plain
        def n = 0
      end
      class Counted1
        include Counted
      end
      p [Plain, Counted1].map { |k| k.new.n }
      p [Counted1].map { |k| k.new.n }
      KL = [Plain, Counted1]
      KL.each { |k| p k.new.n }
      p({ a: Counted1 }.map { |_, k| k.new.n })
      p Counted1.new.n
      k = Counted1
      p k.new.n

      module Sized
        def initialize(n)
          @n = n
        end
        def n = @n
      end
      class Box
        include Sized
      end
      p [Box].map { |c| c.new(3).n }
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 7]
      [7]
      0
      7
      [7]
      7
      7
      [3]
    OUT
  end

  it "Comparable gives <, >, between? and sort to a class that defines <=>" do
    result = zr(<<~'RUBY')
      # A user #<=> that answers an Integer gives the class the Comparable
      # methods: <, >, ==, between? and sort.
      class Money
        include Comparable
        attr_reader :cents
        def initialize(c); @cents = c; end
        def <=>(o); cents <=> o.cents; end
      end
      p(Money.new(150) < Money.new(299))
      p(Money.new(300) > Money.new(299))
      p([Money.new(3), Money.new(1), Money.new(2)].sort.map(&:cents))
      p(Money.new(5).between?(Money.new(1), Money.new(9)))
      p(Money.new(150) == Money.new(150))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      [1, 2, 3]
      true
      true
    OUT
  end

  it "between? and clamp work on Comparable objects inside a block" do
    result = zr(<<~'RUBY')
      class Money
        include Comparable
        attr_reader :cents
        def initialize(c) = @cents = c
        def <=>(o) = cents <=> o.cents
      end
      arr = [Money.new(50), Money.new(150), Money.new(100)]
      p arr.select { |m| m.between?(Money.new(60), Money.new(120)) }.map(&:cents)
      p arr.map { |m| m.clamp(Money.new(80), Money.new(120)).cents }
      # not-between
      p Money.new(200).between?(Money.new(1), Money.new(10))
    RUBY

    _(result).must_answer <<~'OUT'
      [100]
      [80, 120, 100]
      false
    OUT
  end

  it "a module method extended into a class calls the class's own new" do
    result = zr(<<~'RUBY')
      module Factory
        def create(a, b)
          build(a, b)
        end
        def build(a, b)
          new(a, b)
        end
      end
      class Product
        extend Factory
        def initialize(a, b); @a = a; @b = b; end
        def a; @a; end
        def sum; @a + @b; end
      end
      p Product.create(1, 2).a
      p Product.create(3, 4).sum
      p Product.build(5, 6).sum
    RUBY

    _(result).must_answer <<~'OUT'
      1
      7
      11
    OUT
  end

  it "Comparable orders by an array of parts, and to_s prints through interpolation" do
    result = zr(<<~'RUBY')
      class Version
        include Comparable
        attr_reader :parts
        def initialize(str); @parts = str.split(".").map(&:to_i); end
        def <=>(other); parts <=> other.parts; end
        def to_s; parts.join("."); end
      end
      versions = ["1.2.0", "1.10.1"].map { |s| Version.new(s) }
      puts versions.min
      puts versions[0]
      puts "#{versions.max}"
      p versions.min.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      1.2.0
      1.2.0
      1.10.1
      "1.2.0"
    OUT
  end

  it "replace, prepend, concat, clear, gsub! and sub! reach a string through a container read" do
    result = zr(<<~'RUBY')
      # In-place mutators through a poly (container-read) receiver: replace,
      # prepend, concat, clear swap or extend the shared buffer.
      arr = [+"abc"]
      arr[0].replace("xyz")
      p arr
      arr[0].prepend(">>")
      p arr
      arr[0].concat("!!")
      p arr
      arr[0].clear
      p arr
      arr2 = [+"axa"]
      arr2[0].gsub!(/x/, "Y")
      p arr2
      arr2[0].sub!(/a/, "b")
      p arr2
    RUBY

    _(result).must_answer <<~'OUT'
      ["xyz"]
      [">>xyz"]
      [">>xyz!!"]
      [""]
      ["aYa"]
      ["bYa"]
    OUT
  end

  it "macro module installs before the def that wins" do
    result = zr(<<~'RUBY')
      module Macro
        def self.included(base) = base.send(:attr_accessor, :m)
      end
      class C1
        include Macro
        def m = "def wins"
      end
      p C1.new.m

      module Macro2
        def self.extended(base) = base.attr_accessor(:n)
      end
      class C2
        extend Macro2
        def n = "def wins"
      end
      p C2.new.n

      module Macro3
        def field(x) = attr_accessor(x)
      end
      class C3
        extend Macro3
        field :o
        def o = "def wins"
      end
      p C3.new.o

      class C4
        instance_eval { attr_accessor :q }
        def q = "def wins"
      end
      p C4.new.q

      class C5
        [:r].each { |x| define_method(x) { "dm" } }
        def r = "def wins"
      end
      p C5.new.r

      class C6
        [:s].each { |x| attr_accessor x }
      end
      class C6
        def s = "def wins"
      end
      p C6.new.s

      class C7
        def u = "def"
      end
      class C7
        [:u].each { |x| attr_accessor x }
      end
      c = C7.new
      c.u = 5
      p c.u

      class C8
        attr_accessor :v
        def v = "def wins"
      end
      p C8.new.v
    RUBY

    _(result).must_answer <<~'OUT'
      "def wins"
      "def wins"
      "def wins"
      "def wins"
      "def wins"
      "def wins"
      5
      "def wins"
    OUT
  end

  it "mixin" do
    result = zr(<<~'RUBY')
      # Test include (mixin)

      module Printable
        def to_str
          "Printable"
        end

        def print_info
          puts to_str
        end
      end

      module Measurable
        def measure
          42
        end
      end

      class Widget
        include Printable
        include Measurable

        def initialize(name)
          @name = name
        end

        def name
          @name
        end

        def to_str
          @name
        end
      end

      w = Widget.new("button")
      puts w.name         # button
      w.print_info        # button (uses Widget#to_str, not Printable#to_str)
      puts w.measure      # 42 (from Measurable)

      class Gadget
        include Printable

        def initialize(label)
          @label = label
        end

        def label
          @label
        end
      end

      g = Gadget.new("dial")
      g.print_info        # Printable (uses Printable#to_str since Gadget doesn't override)
    RUBY

    _(result).must_answer <<~'OUT'
      button
      button
      42
      Printable
    OUT
  end

  it "mixin of a module that defines methods at runtime" do
    result = zr(<<~'PROGRAM')
      # A static `include`/`extend` folds the module's methods into the target's
      # table where the mixin is written, which is only sound when that table is
      # COMPLETE. i18n's delegators are a string eval in a loop:
      #
      #   %w(locale backend default_locale ...).each do |method|
      #     module_eval <<-DELEGATORS
      #       def #{method} ... end
      #     DELEGATORS
      #   end
      #   extend Base
      #
      # so the literal `def`s in `Base` reached `I18n` and the eval'd ones did not --
      # `I18n.translate` worked while `I18n.backend` was a NoMethodError. Such a
      # mixin becomes a runtime send, which installs whatever the module holds by the
      # time it runs.
      module Host
        module Base
          def literal = :literal

          %w(alpha beta).each do |name|
            module_eval <<-RUBY, __FILE__, __LINE__ + 1
              def #{name}
                :#{name}
              end
              def #{name}=(v)
                @#{name} = v
              end
            RUBY
          end
        end
        extend Base
      end

      p Host.literal
      p Host.alpha
      p Host.beta
      p Host.respond_to?(:alpha=)
      Host.alpha = 9
      p Host.instance_variable_get(:@alpha)

      # The INCLUDE side of the same shape.
      module Carrier
        module Feature
          def plain = :plain
          %w(gamma).each do |name|
            module_eval "def #{name}; :#{name}; end", __FILE__, __LINE__
          end
        end
        class User
          include Feature
        end
      end
      p Carrier::User.new.plain
      p Carrier::User.new.gamma

      # A module with NO runtime installs keeps the static edit -- `attr_accessor`
      # and a literal `define_method` both expand at compile time, so listing them
      # would push nearly every module onto the slow path for nothing.
      module Static
        module Plain
          attr_accessor :slot
          define_method(:made) { :made }
          def direct = :direct
        end
        class Holder
          include Plain
        end
      end
      h = Static::Holder.new
      h.slot = 3
      p [h.slot, h.made, h.direct]
    PROGRAM

    _(result).must_answer <<~'OUT'
      :literal
      :alpha
      :beta
      true
      9
      :plain
      :gamma
      [3, :made, :direct]
    OUT
  end

  it "mixin primitive override" do
    result = zr(<<~'RUBY')
      # `include`/`prepend`/`extend` are the PUBLIC verbs. Each is defined in terms of
      # a private primitive that does the actual work -- `append_features`,
      # `prepend_features`, `extend_object` -- and calls the notification hook after:
      #
      #     rb_funcall(mod, append_features, 1, base)
      #     rb_funcall(mod, included, 1, base)
      #
      # The insertion happens ONLY inside the default primitive. So a module that
      # overrides one and omits `super` skips the mixin entirely -- and `included`
      # still fires, because the two calls are unconditional. That is what lets a
      # module police how it is mixed in; the `singleton` gem is built on it.

      puts "== prepend_features with super"
      module PF
        def self.prepend_features(base) = (puts("PF.prepend_features(#{base})"); super)
        def self.prepended(base) = puts("PF.prepended(#{base})")
        def hi = "from PF"
      end
      class Host
        prepend PF
        def hi = "from Host"
      end
      p [Host.ancestors.first(3), Host.new.hi]

      puts "== prepend_features WITHOUT super skips the mixin, but still notifies"
      module NS
        def self.prepend_features(base) = puts("NS.prepend_features, no super")
        def self.prepended(base) = puts("NS.prepended")
        def nope = 1
      end
      class H2
        prepend NS
      end
      p [H2.ancestors.first(3), H2.new.respond_to?(:nope)]

      puts "== append_features"
      module AF
        def self.append_features(base) = (puts("AF.append_features(#{base})"); super)
        def yo = "from AF"
      end
      class H3
        include AF
      end
      p [H3.ancestors.include?(AF), H3.new.yo]

      puts "== append_features without super"
      module AN
        def self.append_features(base) = puts("AN.append_features, no super")
        def gone = 1
      end
      class H4
        include AN
      end
      p [H4.ancestors.include?(AN), H4.new.respond_to?(:gone)]

      puts "== a module with NO override is still folded at compile time"
      module Plain
        def plain = 1
      end
      class H5
        include Plain
      end
      p [H5.ancestors.include?(Plain), H5.new.plain]

      puts "== extend_object"
      module EO
        def self.extend_object(obj) = (puts("EO.extend_object(#{obj.class})"); super)
        def self.extended(obj) = puts("EO.extended(#{obj.class})")
        def tagged = "from EO"
      end
      o = Object.new
      o.extend(EO)
      p [o.tagged, o.is_a?(EO)]
      # The optparse shape: the primitive's `super` is followed by setting an ivar
      # on the receiver, which for a bare Array needs storage beside the value.
      module Tagger
        def self.extend_object(obj)
          super
          obj.instance_eval { @tag = "set" }
        end
        def tag = @tag
      end
      arr = [1, 2]
      arr.extend(Tagger)
      p [arr.tag, arr.instance_variables, arr.is_a?(Tagger), arr]

      puts "== extend_object without super skips the mixin, but still notifies"
      module EN
        def self.extend_object(obj) = puts("EN.extend_object, no super")
        def self.extended(obj) = puts("EN.extended")
        def missing = 1
      end
      o2 = Object.new
      o2.extend(EN)
      p [o2.respond_to?(:missing), o2.is_a?(EN)]

      puts "== a class body `extend` routes through it too"
      class H6
        extend EO
      end
      p [H6.tagged, H6.singleton_class.include?(EO)]

      puts "== the runtime shapes route through the primitive too"
      # A prepend has to outrank the target's OWN method even when that method is
      # defined afterwards -- ruby keeps the prepended module in its own layer.
      K = Class.new { prepend PF; def hi = "from K" }
      p K.new.hi
      K2 = Class.new { include AN }
      p K2.new.respond_to?(:gone)
    RUBY

    _(result).must_answer <<~'OUT'
      == prepend_features with super
      PF.prepend_features(Host)
      PF.prepended(Host)
      [[PF, Host, Object], "from PF"]
      == prepend_features WITHOUT super skips the mixin, but still notifies
      NS.prepend_features, no super
      NS.prepended
      [[H2, Object, Kernel], false]
      == append_features
      AF.append_features(H3)
      [true, "from AF"]
      == append_features without super
      AN.append_features, no super
      [false, false]
      == a module with NO override is still folded at compile time
      [true, 1]
      == extend_object
      EO.extend_object(Object)
      EO.extended(Object)
      ["from EO", true]
      ["set", [:@tag], true, [1, 2]]
      == extend_object without super skips the mixin, but still notifies
      EN.extend_object, no super
      EN.extended
      [false, false]
      == a class body `extend` routes through it too
      EO.extend_object(Class)
      EO.extended(Class)
      ["from EO", true]
      == the runtime shapes route through the primitive too
      PF.prepend_features(#<Class:0xADDR>)
      PF.prepended(#<Class:0xADDR>)
      "from PF"
      AN.append_features, no super
      false
    OUT
  end

  it "mixins" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `include`, `extend` and `prepend` are ordinary sends to the class the
      # body is running on. zr registers a class statically, but nothing about
      # a mixin is static: the runtime answers where a method lands and what
      # `ancestors` reports.

      module Loud
        def speak(word) = "#{super(word)}!"
      end

      module Greeter
        def hello = "hello from #{name}"
      end

      module Tools
        def helper = :helped

        extend self
      end

      class Quiet
        def speak(word) = word
      end

      class Shouter < Quiet
        include Loud
        extend Greeter

        def own = :own
      end

      class Front
        prepend Loud

        def speak(word) = word.upcase
      end

      p Shouter.new.speak("hi")
      p Shouter.hello
      p Shouter.new.own
      p Shouter.ancestors.take(3).map(&:to_s)
      p Shouter.include?(Loud)
      p Front.new.speak("hi")
      p Front.ancestors.take(2).map(&:to_s)
      p Tools.helper
      p Tools.singleton_class.ancestors.take(2).map(&:to_s)

      # A module can be mixed into more than one class, and each keeps its own
      # superclass above it.
      class Whisper
        def speak(word) = word.downcase
      end

      class Murmur < Whisper
        include Loud
      end
      p Murmur.new.speak("HI")

      # An object extends one module without its class changing at all.
      class Named
        def name = "one"
      end

      one = Named.new
      one.extend(Greeter)
      p one.hello
      p Named.new.respond_to?(:hello)
    RUBY

    _(result).must_answer <<~'OUT'
      "hi!"
      "hello from Shouter"
      :own
      ["Shouter", "Loud", "Quiet"]
      true
      "HI!"
      ["Loud", "Front"]
      :helped
      ["#<Class:Tools>", "Tools"]
      "hi!"
      "hello from one"
      false
    OUT
  end

  it "module accessor delete chain" do
    result = zr(<<~'RUBY')
      # `M.accessor.delete` calls the `delete` class method of the module
      # that the accessor holds. The receiver is not a Hash or an Array, so
      # this is an ordinary call, with no warning.

      module M
        class << self
          attr_accessor :adapter
        end
      end

      module Backend
        def self.delete
          "ran-delete"
        end
      end

      M.adapter = Backend
      puts M.adapter.delete

      # Also exercise statement context (no puts) -- must not crash and
      # must not warn.
      M.adapter.delete
    RUBY

    _(result).must_answer "ran-delete\n"
  end

  it "module accessor nil check" do
    result = zr(<<~'RUBY')
      # `.nil?` on a module-singleton accessor whose value type is a
      # class constant: the call must check whether the slot has been
      # assigned, NOT dispatch a class method `.nil?` on the resolved
      # class. This is true also when only one class can be in the slot.

      class A
      end

      module Registry
        class << self
          attr_accessor :adapter
        end
      end

      def configure
        Registry.adapter = A
      end

      # Read paths -- .nil? checks whether the slot is set. It is not a
      # class method call on A.
      def check_unset
        Registry.adapter.nil?
      end

      def check_after_set
        configure
        Registry.adapter.nil?
      end

      puts check_unset ? "nil" : "set"
      puts check_after_set ? "nil" : "set"
    RUBY

    _(result).must_answer "nil\nset\n"
  end

  it "module case conformance" do
    result = zr(<<~'RUBY')
      # Four surfaces around class values and case equality.

      # A module has no superclass chain: its ancestors are itself and what it
      # includes, not the Object/Kernel/BasicObject a class walks into.
      module M; end
      module N; include M; end
      p M.ancestors
      p N.ancestors
      class C; include M; end
      p C.ancestors
      p N.included_modules

      # Module#=== is `arg.is_a?(self)`, including for the roots, which fell past
      # the arm into the missing-method gate
      class U; end
      u = U.new
      p(Object === u)
      p(Object === Object.new)
      p(Object === 3)
      p(BasicObject === u)
      p(U === u)
      p(U === 3)
      p(Integer === 3)
      p(String === "x")

      # `when <obj>` is `<obj> === scrutinee`, which for a plain object is its own
      # ==; the two pointers were compared instead
      class Eq
        def initialize(v); @v = v; end
        def v; @v; end
        def ==(o); v == o.v; end
      end

      a = Eq.new(1)
      b = Eq.new(1)
      d = Eq.new(2)
      p(a === b)
      case b when a then p "eq" else p "ne" end
      case d when a then p "eq" else p "ne" end

      # a class with no == keeps identity
      class Plain; end
      p1 = Plain.new
      p2 = Plain.new
      case p1 when p1 then p "same" else p "other" end
      case p2 when p1 then p "same" else p "other" end
    RUBY

    _(result).must_answer <<~'OUT'
      [M]
      [N, M]
      [C, M, Object, Kernel, BasicObject]
      [M]
      true
      true
      true
      true
      true
      false
      true
      true
      true
      "eq"
      "ne"
      "same"
      "other"
    OUT
  end

  it "module case eq mixin" do
    result = zr(<<~'RUBY')
      class U; end
      r001 = (Comparable === U.new rescue $!.class)
      p r001

      r002 = (Enumerable === U.new rescue $!.class); p r002   # Ruby: false

      p(Object === U.new)        # => true
      p(Kernel === U.new)        # => true
      p(BasicObject === U.new)   # => true
      p(Comparable === 1)        # => true
      module M; end
      p(M === U.new)             # => false
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
      true
      true
      true
      false
    OUT
  end

  it "module class body side effects" do
    result = zr(<<~'RUBY')
      # Side-effecting statements in a module/class body run at definition
      # time (top-to-bottom), like CRuby. Before, only def/const declarations
      # were processed and statements such as `puts` were silently dropped.
      # The body is emitted as a function called from main at the definition
      # site, so output interleaves correctly with surrounding statements.

      puts "before module"

      module M
        puts "in module body"
        VERSION = "1.0"
        puts "version is #{VERSION}"
      end

      puts "after module"

      class C
        puts "in class body"
        def self.hi
          "hi"
        end
      end

      # Nested module bodies run when the enclosing module is defined
      module Outer
        module Inner
          puts "deep body ran"
        end
      end

      # A class method defined in the body is still callable afterward
      puts C.hi
    RUBY

    _(result).must_answer <<~'OUT'
      before module
      in module body
      version is 1.0
      after module
      in class body
      deep body ran
      hi
    OUT
  end

  it "module class new" do
    result = zr(<<~'RUBY')
      # Test: class defined inside module and instantiated through M::C.new

      module M
        class C
          def initialize
            puts "init"
          end

          def step
            puts "step"
          end
        end
      end

      puts "start"
      obj = M::C.new
      obj.step
    RUBY

    _(result).must_answer <<~'OUT'
      start
      init
      step
    OUT
  end

  it "module comparison" do
    result = zr(<<~'RUBY')
      # A class/module is ordered against another by the ancestry relation: `<` is a
      # proper subclass, `<=` allows equality, `>`/`>=` are the reverse, and an
      # unrelated pair is `nil` (not false). `<=>` folds the four into -1/0/1/nil.
      class Animal; end
      class Dog < Animal; end
      class Cat < Animal; end

      p(Dog < Animal)      # true  -- proper subclass
      p(Animal < Dog)      # false -- Animal is the ancestor
      p(Dog < Dog)         # false -- not proper
      p(Dog <= Dog)        # true
      p(Animal > Dog)      # true
      p(Dog >= Animal)     # false
      p(Dog < Cat)         # nil   -- unrelated
      p(Dog <=> Animal)    # -1
      p(Animal <=> Dog)    # 1
      p(Dog <=> Dog)       # 0
      p(Dog <=> Cat)       # nil
      p(Dog <=> 5)         # nil   -- non-module argument

      # Builtins participate through the same ancestry chain.
      p(Integer < Numeric)     # true
      p(Comparable > Integer)  # true
      p(String <= Comparable)  # true

      # A non-class/module argument to `<`/`<=`/`>`/`>=` is a TypeError.
      begin
        Dog < 5
      rescue TypeError => e
        puts e.message
      end

      # `subclasses` lists the direct, currently-defined subclasses.
      class Base; end
      class Kid1 < Base; end
      class Kid2 < Base; end
      class GKid < Kid1; end
      p Base.subclasses.length
      p Base.subclasses.map { |c| c.to_s }.sort
      p Kid1.subclasses.map { |c| c.to_s }
      p Kid2.subclasses

      # Named classes and modules are never singleton classes.
      p Dog.singleton_class?
      module M; end
      p M.singleton_class?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      true
      false
      nil
      -1
      1
      0
      nil
      nil
      true
      true
      true
      compared with non class/module
      2
      ["Kid1", "Kid2"]
      ["GKid"]
      []
      false
      false
    OUT
  end

  it "module const root path" do
    result = zr(<<~'RUBY')
      # Well-known module constants reached through a root-qualified / nested path
      # (::Float::MAX, ::Math::PI) infer their real type (Float) just like the plain
      # Float::MAX form, so methods called on them compile instead of failing on a
      # TY_UNKNOWN receiver. This matches codegen, which already resolves the nested
      # parent path.
      p(::Float::MAX > 1.0)
      p(::Math::PI.round(2))
      p(::Math::E.round(3))
      p(::Float::INFINITY.infinite?)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      3.14
      2.718
      1
    OUT
  end

  it "module cvars" do
    result = zr(<<~'RUBY')
      # Class variables (`@@var`) declared in a module body work the same
      # as in a class body.

      module Tep
        @@session_secret = ""

        def self.session_secret
          @@session_secret
        end

        def self.session_secret=(v)
          @@session_secret = v
        end
      end

      # Read default
      puts Tep.session_secret.length    # 0

      # Write + read back
      Tep.session_secret = "hello"
      puts Tep.session_secret           # hello

      # Read again to confirm the global persists
      puts Tep.session_secret           # hello

      # A bare top-level `@@x` does not store into the same namespace. Only a
      # `class`/`module` body opens the cref that `@@x` resolves against, so Ruby
      # raises here. See `class_variable_cref_scope.rb` for the full rule.
      begin
        @@plain = 42
      rescue RuntimeError => e
        puts e.message                  # class variable access from toplevel
      end
    RUBY

    _(result).must_answer <<~'OUT'
      0
      hello
      hello
      class variable access from toplevel
    OUT
  end

  it "module def is one body for every includer" do
    result = zr(<<~'RUBY')
      # A definition on a module is inherited by every class that includes it, and
      # zr emits its body ONCE rather than once per includer. This pins what that
      # makes observable.
      #
      # The body may not depend on the carrier. A constant it reads must resolve
      # lexically from the MODULE, `self` must be the receiver, a method it calls
      # must dispatch to the receiver's own override, `super` must resume from the
      # module's position in the CARRIER's ancestry, and the private visibility a
      # module gives a method must survive on every includer.
      #
      # A body that names an instance variable is deliberately NOT shared: an
      # includer reads ivars by slot, and two includers can lay their slots out
      # differently. Those rows are here so the split stays visible.

      module Named
        IN_MODULE = "from-Named"

        def lit = 42
        def const_read = IN_MODULE
        def who = self.class.name
        def calls_out = "via:#{tag}"
        def with_block = [1, 2].map { |z| z * 2 }
        def stashes = (@stashed ||= 0) + 1

        private

        def secret = "shh"

        public

        def reaches_private = secret
      end

      # A SECOND module defining the same names: sharing is keyed by the definition,
      # never by the method name, and these must not collide.
      module Other
        def lit = "other-lit"
        def who = "other-who"
      end

      class Base
        def tag = "base"
      end

      class Plain < Base
        include Named
      end

      class Overrides < Base
        include Named
        def tag = "overrides"
      end

      class Elsewhere < Base
        include Other
      end

      class Supering < Base
        include Named
        def with_block = ["S"] + super
      end

      # A carrier with its OWN ivars, so the shared body's `self` is a receiver
      # whose layout differs from the next one's.
      class Roomy < Base
        include Named
        def initialize
          @a = 1
          @b = 2
        end
      end

      plain = Plain.new
      over = Overrides.new
      roomy = Roomy.new

      p [plain.lit, over.lit, Elsewhere.new.lit]
      p [plain.const_read, roomy.const_read]
      p [plain.who, over.who, Elsewhere.new.who]
      p [plain.calls_out, over.calls_out]
      p [plain.with_block, Supering.new.with_block]

      # The ivar a shared-eligible body would touch belongs to the RECEIVER, and
      # each receiver keeps its own.
      p [plain.stashes, roomy.stashes]
      p [plain.instance_variables.sort, roomy.instance_variables.sort]

      # A module's `private` reaches every includer.
      p [plain.respond_to?(:secret), over.respond_to?(:secret)]
      p [plain.reaches_private, over.reaches_private]
      p [plain.send(:secret), roomy.send(:secret)]

      # Reflection names the module, not the carrier.
      p [plain.method(:lit).owner, Overrides.instance_method(:lit).owner]
      p [Elsewhere.instance_method(:lit).owner, plain.is_a?(Named)]
      p [Plain.include?(Named), Elsewhere.include?(Named)]
    RUBY

    _(result).must_answer <<~'OUT'
      [42, 42, "other-lit"]
      ["from-Named", "from-Named"]
      ["Plain", "Overrides", "other-who"]
      ["via:base", "via:overrides"]
      [[2, 4], ["S", 2, 4]]
      [1, 1]
      [[:@stashed], [:@a, :@b, :@stashed]]
      [false, false]
      ["shh", "shh"]
      ["shh", "shh"]
      [Named, Named]
      [Other, true]
      [true, false]
    OUT
  end

  it "module dispatch param widen" do
    result = zr(<<~'RUBY')
      # A module-dispatch call site (`Disp.adapter.method(args)`, where
      # Disp.adapter can hold one of N candidate classes). The only caller
      # passes a poly value, so the param of each candidate's class method
      # widens to poly. The dispatch picks the class that the slot holds.

      class A
        def self.update(id)
          id
        end
      end

      class B
        def self.update(id)
          id
        end
      end

      module Disp
        class << self
          attr_accessor :adapter
        end
      end

      class C
        def initialize
          @id = 0
        end
        def write_str(s); @id = s; end   # widens @id to poly
        def save
          Disp.adapter.update(@id)         # ternary-dispatched: poly arg
        end
      end

      if ARGV.length > 0
        Disp.adapter = A
      else
        Disp.adapter = B
      end

      c = C.new
      c.write_str("hi")
      c.save                              # no output expected; just compile
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "module included class and toplevel" do
    result = zr(<<~'RUBY')
      # A module included BOTH into a class and at toplevel. A method of the module
      # that constructs an object answers that object in both places.
      #
      # The shape comes from tobi/try (a Ruby CLI + TUI): its TUI helper module is
      # mixed into the screen classes and also included at toplevel, so the script
      # body can call the same helpers.
      class Box
        attr_reader :ch
        def initialize(ch); @ch = ch; end
      end

      module Helpers
        def fill(ch); Box.new(ch); end
      end

      class Screen
        include Helpers          # included into a class...
        def go; fill("="); end
      end

      include Helpers            # ...AND at toplevel

      puts Screen.new.go.ch
      puts fill("-").ch

      # a second method on the same module, to show it is not specific to one name
      module More
        def wrap(ch); Box.new("[#{ch}]"); end
      end

      class Panel
        include More
        def draw; wrap("x"); end
      end

      include More

      puts Panel.new.draw.ch
      puts wrap("y").ch
    RUBY

    _(result).must_answer <<~'OUT'
      =
      -
      [x]
      [y]
    OUT
  end

  it "module included modules self" do
    result = zr(<<~'RUBY')
      p Comparable.included_modules
      p Enumerable.included_modules
      module M1; end
      p M1.included_modules
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      []
    OUT
  end

  it "module new refuses an argument" do
    result = zr(<<~'RUBY')
      [
        -> { Module.new(1) },
        -> { Module.new(1, 2) },
        -> { Module.new(1) { } },
        -> { Class.new(String, 2) },
        -> { Class.new(String) },
        -> { Module.new },
      ].each do |f|
        begin
          puts "ok #{f.call.class}"
        rescue ArgumentError => e
          puts "ArgumentError: #{e.message}"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: wrong number of arguments (given 1, expected 0)
      ArgumentError: wrong number of arguments (given 2, expected 0)
      ArgumentError: wrong number of arguments (given 1, expected 0)
      ArgumentError: wrong number of arguments (given 2, expected 0..1)
      ok Class
      ok Module
    OUT
  end

  it "nested class module const resolution" do
    result = zr(<<~'RUBY')
      # When a class lives inside a module and another class in the same
      # module is referenced via a bare name from one of its method bodies,
      # the bare name resolves in the module's lexical scope. `Inner.new`
      # inside `Outer#initialize` makes an `M::Inner`, and the ivar that
      # holds it has that class.

      module M
        class Inner
          def initialize(x)
            @x = x
          end
          attr_reader :x
        end

        class Outer
          def initialize
            @inner = Inner.new(10)
          end
          def via_ivar
            @inner.x
          end
          def via_local
            tmp = Inner.new(20)
            tmp.x
          end
        end
      end

      puts M::Outer.new.via_ivar
      puts M::Outer.new.via_local
    RUBY

    _(result).must_answer "10\n20\n"
  end

  it "poly user include value" do
    result = zr(<<~'RUBY')
      # `include?` on a poly receiver whose class defines its own: the call answers
      # the user method's value, not a true/false copy of it. A position answer of
      # `0`, which Ruby reads as truthy, stays `0`.
      class Tags
        def initialize(names)
          @names = names
          @asked = 0
        end

        attr_reader :asked

        # answers where it found the name; Ruby reads 0 as truthy
        def include?(name)
          @asked += 1
          @names.index(name)
        end
      end

      def found(value) = value.include?("ruby")

      tags = Tags.new(["ruby", "spinel"])
      p found(tags)
      p tags.asked
      p found(["ruby"])
      p found(["spinel", "ruby"])
      p found(["none"])
      p found("a ruby string")
      p found({ "ruby" => 1 })

      # a class whose include? really does answer a bool keeps the plain path
      class Bag
        def initialize(xs) = @xs = xs
        def include?(x) = @xs.length > 0 && x == "y"
      end

      def has(v) = v.include?("y")
      p has(Bag.new(["y"]))
      p has(["y"])
      p has(["n"])
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      true
      true
      false
      true
      true
      true
      true
      false
    OUT
  end

  it "reflection methods" do
    result = zr(<<~'RUBY')
      # methods / instance_methods reflection — names as Symbols, honoring
      # visibility and inheritance.

      module Walkable
        def walk; "walking"; end
      end

      class Animal
        def speak; end
        def legs; 4; end
        private
        def digest; end
      end

      class Dog < Animal
        include Walkable
        def bark; end
        def speak; "woof"; end        # override
        def self.breed; "mutt"; end
      end

      # instance_methods(false) — OWN methods only (overrides included), exact.
      p Dog.instance_methods(false).sort
      # default (inherited) — membership across the ancestry.
      p Dog.instance_methods.include?(:speak)     # own override
      p Dog.instance_methods.include?(:legs)      # inherited from Animal
      p Dog.instance_methods.include?(:walk)      # from module
      p Dog.instance_methods.include?(:digest)    # private → not listed

      # visibility variants
      p Animal.private_instance_methods(false)
      p Animal.public_instance_methods(false).sort

      # a module lists its own methods
      p Walkable.instance_methods

      # singleton (class) methods
      p Dog.singleton_methods
      p Dog.singleton_methods.include?(:breed)

      # object-side: methods / respond_to? agree
      d = Dog.new
      p d.methods.include?(:bark)
      p d.methods.include?(:walk)
      p d.methods.include?(:breed)                 # false — a class method
      p d.methods.include?(:frozen?)               # Kernel method
      p d.respond_to?(:bark)
      p d.respond_to?(:digest)                     # private → false
      p d.respond_to?(:digest, true)               # include_all → true

      # builtins expose (a subset of) their surface
      p "hello".methods.include?(:upcase)
      p [1, 2].methods.include?(:map)
      p 42.methods.include?(:+)
    RUBY

    _(result).must_answer <<~'OUT'
      [:bark, :speak]
      true
      true
      true
      false
      [:digest]
      [:legs, :speak]
      [:walk]
      [:breed]
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
    OUT
  end

  it "runtime class body carries nested classes mixins aliases and visibility" do
    result = zr(<<~'RUBY')
      # A class with a DYNAMIC superclass (`class Foo < base`, base a method) is
      # built at runtime; its body can now hold a nested class, `include`, a
      # constant, `alias`, and a visibility directive -- each rewritten to the
      # runtime self-send the class-value receiver serves (the same machinery
      # that lets `class Tempfile < DelegateClass(File)` compile).

      def base; Object; end
      module Mx; def mixed; "mx"; end; end
      class Foo < base
        VAL = 7
        include Mx
        def a; VAL; end
        alias b a
        protected :b
        class Inner
          def deep; "deep"; end
        end
        def use_inner; Inner.new.deep; end
      end
      puts Foo.new.a
      puts Foo.new.use_inner
      puts Foo.new.mixed
      puts Foo.ancestors.include?(Mx)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      deep
      mx
      true
    OUT
  end

  it "shared parent body reaches the right slot" do
    result = zr(<<~'RUBY')
      # One emitted body serves a parent and every descendant, and it indexes
      # `@x` by the slot the PARENT gave it. That is only sound because
      # `analyze::mro` lays each class out as `ivars(parent) ++ its own new
      # names`, so a descendant agrees about every slot its parent declared.
      #
      # The classes below disagree about everything else they can: each adds its
      # own ivars, in different numbers, some before their first use of an
      # inherited body and some after, and two of them add a module that brings
      # more. A shared body reading one slot too far answers another ivar's
      # value rather than raising, so the assertions read the values back.

      module Extra
        def extra_set; @e1 = "e1"; @e2 = "e2"; nil; end
      end

      class Parent
        def write(v); @x = "<#{v}>"; nil; end
        def read; @x.nil? ? "unset" : @x.upcase; end
      end

      class Bare < Parent; end

      class Adds < Parent
        def own_set; @a1 = 1; @a2 = 2; nil; end
      end

      class Mixes < Parent
        include Extra
        def own_set; @m1 = "m"; nil; end
      end

      class Deep < Adds
        include Extra
        def deep_set; @d1 = :d; nil; end
      end

      [Parent, Bare, Adds, Mixes, Deep].each do |k|
        o = k.new
        # Fill the subclass's OWN ivars first where it has them, so a body
        # reading the wrong slot finds a plausible value rather than nil.
        o.own_set if o.respond_to?(:own_set)
        o.extra_set if o.respond_to?(:extra_set)
        o.deep_set if o.respond_to?(:deep_set)
        o.write(k.name)
        puts "#{k}\t#{o.read}\t#{o.instance_variables.inspect}"
      end

      # The reverse direction: write through the shared body, then read the ivar
      # by name. The two must agree, whatever slot the body chose.
      [Parent, Bare, Adds, Mixes, Deep].each do |k|
        o = k.new
        o.write("direct")
        p [k.to_s, o.instance_variable_get(:@x), o.read]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Parent	<PARENT>	[:@x]
      Bare	<BARE>	[:@x]
      Adds	<ADDS>	[:@a1, :@a2, :@x]
      Mixes	<MIXES>	[:@m1, :@e1, :@e2, :@x]
      Deep	<DEEP>	[:@a1, :@a2, :@e1, :@e2, :@d1, :@x]
      ["Parent", "<direct>", "<DIRECT>"]
      ["Bare", "<direct>", "<DIRECT>"]
      ["Adds", "<direct>", "<DIRECT>"]
      ["Mixes", "<direct>", "<DIRECT>"]
      ["Deep", "<direct>", "<DIRECT>"]
    OUT
  end

  it "a send of its own does not take the core's hook, inject or member calls" do
    result = zr(<<~'RUBY')
      # A module or an object with a `send` of its own: the core's own calls
      # of a hook, of inject's operator and of a struct member's writer go by
      # name, as rb_funcall goes, and never through it.
      module Mixed
        def self.send(*) = raise("Mixed.send")
        def self.included(base) = (puts "included in #{base}")
      end
      class Host
        include Mixed
      end
      class Acc
        attr_reader :n
        def initialize(n) = @n = n
        def send(*) = raise("Acc#send")
        def +(other) = Acc.new(n + other)
      end
      p [1, 2, 3].inject(Acc.new(0), :+).n
      p [Acc.new(1), 2, 3].inject(:+).n
      S = Struct.new(:a) do
        def send(*) = raise("S#send")
      end
      p Marshal.load(Marshal.dump(S.new(4))).a
    RUBY

    _(result).must_answer <<~'OUT'
      included in Host
      6
      6
      4
    OUT
  end
end
