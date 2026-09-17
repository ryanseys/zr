# frozen_string_literal: true

require "spec_helper"

describe "String: evaluating a string" do
  it "builds its cref on the callers" do
    result = ze0(<<~'RUBY')
      # A string `class_eval`/`module_eval` builds its cref on the CALLER's
      # lexical chain -- CRuby pushes the receiver onto the cref of the frame the
      # call is written in, so a constant beside the CALL SITE resolves inside
      # the snippet. rss's dublincore writes `class DublinCoreTitle < Element`
      # in a module_eval string and Element lives two scopes out.
      module Outer
        class Element
          def self.tag = :outer_element
        end
        module Model; end
        Model.module_eval("p Module.nesting")
        Model.module_eval("class Kid < Element; end", __FILE__, __LINE__)
      end
      p Outer::Model::Kid.superclass
      p Outer::Model::Kid.tag

      module Outer
        module Deep
          Outer::Model.module_eval("p Module.nesting")
        end
      end

      def indirect_eval(mod, src)
        mod.class_eval(src)
      end
      module Outer
        module Deep
          E2 = Element
        end
      end
      p Outer::Deep.class_eval("E2") == Outer::Element

      # A method's OWN lexical scope is the cref an eval written in it uses,
      # wherever it is called from.
      module Outer
        module Deep
          def self.probe = Outer::Model.module_eval("Module.nesting")
        end
      end
      p Outer::Deep.probe
    RUBY

    _(result).must_answer <<~'OUT'
      [Outer::Model, Outer]
      Outer::Element
      :outer_element
      [Outer::Model, Outer::Deep, Outer]
      true
      [Outer::Model, Outer::Deep, Outer]
    OUT
  end

  it "class eval string constant scope" do
    result = ze0(<<~'RUBY')
      # The STRING forms of `class_eval`/`module_eval`/`instance_eval` evaluate with
      # the receiver as the constant lookup scope. zeo evaluates them with the
      # caller's scope, so a constant owned by the receiver is not found.
      #
      #     Outer::Host.class_eval("HOST_C")   ruby :host   zeo NameError
      #
      # The BLOCK form is the opposite and zeo gets it right: a block keeps the
      # lexical scope where it was written, which is why `class_eval { VAL }` sees
      # the caller's constants and `class_eval("VAL")` does not. That contrast is the
      # documented reason both forms exist, and a library that builds code as a
      # string -- the classic `class_eval <<~RUBY` accessor generator -- depends on
      # the string form seeing the receiver.
      #
      # The NameError message shows the same missing scope: ruby names the constant
      # it looked for as `Outer::Host::VAL`, zeo as a bare `VAL`.

      module Outer
        VAL = :outer_val
        class Host
          HOST_C = :host
        end
      end

      p Outer::Host.class_eval("HOST_C")

      # `instance_eval`'s scope is the SINGLETON class, so an instance-level constant
      # is correctly absent there -- but the message names the scope it searched, and
      # that is the same information the case above is missing.
      begin
        Outer::Host.instance_eval("HOST_C")
      rescue NameError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        Outer::Host.class_eval("VAL")
      rescue NameError => e
        puts "#{e.class}: #{e.message}"
      end

      # The block form keeps the caller's lexical scope -- already correct.
      p Outer::Host.class_eval { Outer::VAL }
      p Outer::Host.class_eval { const_defined?(:HOST_C) }

      # A string that DEFINES a method lands on the receiver either way.
      Outer::Host.class_eval("def from_string = HOST_C")
      p Outer::Host.new.from_string
    RUBY

    _(result).must_answer <<~'OUT'
      :host
      NameError: uninitialized constant #<Class:Outer::Host>::HOST_C
      NameError: uninitialized constant Outer::Host::VAL
      :outer_val
      true
      :host
    OUT
  end

  it "eval non string argument is a type error" do
    _(ze0(<<~'RUBY')).must_answer "no implicit conversion of Integer into String\n"
      begin
        eval(123)
      rescue TypeError => e
        puts e.message
      end
    RUBY
  end

  it "eval string defines a module" do
    result = ze0(<<~'RUBY')
      # `eval` of a literal string that defines a `class`/`module`. At the TOP LEVEL
      # zeo parses the snippet at compile time and inlines it, so the definition is
      # ordinary; inside a METHOD body it falls through to the runtime eval VM,
      # which had no constant-write node -- `WHO = "made"` was the whole refusal,
      # not the `module` the gap header blamed.
      #
      # The second half is the cref: an eval'd `def self.hi` reading a bare constant
      # resolves against the module it was DEFINED into. Deriving that from the
      # receiver answers `Module`, which knows none of the module's constants.
      def make
        eval('module Made
          WHO = "made"
          INNER = [WHO, 1].freeze
          def self.hi = "made hi #{WHO}"
          class Deep
            D = :d
          end
        end')
      end

      make
      p [Made::WHO, Made.hi, Made.class]
      p [Made::INNER, Made::Deep::D, Made.const_get(:WHO)]
      p Made.constants.sort

      # A reopen from a second eval adds to the same module.
      def more
        eval('module Made
          SECOND = 2
        end')
      end
      more
      p [Made::SECOND, Made.constants.sort]

      # A scoped write, and the value an assignment answers.
      module Ns; end
      def scoped
        eval('Ns::SCOPED = 3')
      end
      p [scoped, Ns::SCOPED]

      # ...and the top-level form, which the compile-time path already covered.
      class Base
        def hi = "base"
      end

      eval('class Derived < Base
        def hi = "derived (#{super})"
      end')
      p Derived.new.hi
    RUBY

    _(result).must_answer <<~'OUT'
      ["made", "made hi made", Module]
      [["made", 1], :d, "made"]
      [:Deep, :INNER, :WHO]
      [2, [:Deep, :INNER, :SECOND, :WHO]]
      [3, 3]
      "derived (base)"
    OUT
  end

  it "eval string interpolation inside source" do
    _(ze0(<<~'RUBY')).must_answer "n=36\n"
      code = 'n = 6; "n=#{n * n}"'; puts eval(code)
    RUBY
  end

  it "instance eval string mutates an ivar" do
    _(ze0(<<~'RUBY')).must_answer "3\n"
      class Counter
        def initialize
          @n = 0
        end
      end
      c = Counter.new
      c.instance_eval("@n = @n + 3")
      puts c.instance_eval("@n")
    RUBY
  end

  it "instance eval string reads the receivers ivars" do
    _(ze0(<<~'RUBY')).must_answer "105\n"
      class Account
        def initialize(n)
          @balance = n
        end
      end
      acct = Account.new(100)
      src = "@balance + 5"
      puts acct.instance_eval(src)
    RUBY
  end

  it "instance eval string rebinds self to a literal receiver" do
    _(ze0(<<~'RUBY')).must_answer "OLLEH\n"
      src = "upcase.reverse"; puts "hello".instance_eval(src)
    RUBY
  end
end
