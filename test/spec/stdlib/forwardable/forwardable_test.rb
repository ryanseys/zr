# frozen_string_literal: true

require "spec_helper"

describe "Forwardable programs" do
  it "issue 3300 forwardable" do
    _(ze0(<<~'RUBY')).must_answer "ok\n"
      require "forwardable"

      class Wrapped
        def initialize
          @items = []
        end

        def add(x)
          @items << x
          self
        end

        def size
          @items.size
        end

        def label(prefix, sep)
          "#{prefix}#{sep}#{@items.size}"
        end
      end

      class Inner
        def greet
          "hi"
        end
      end

      class MyClass
        extend Forwardable

        def_delegator :@foo, :to_s, :value
        def_delegator :inner, :greet
        def_delegators :@w, :add, :size, :label

        def initialize
          @foo = 6
          @w = Wrapped.new
        end

        def inner
          @inner ||= Inner.new
        end
      end

      m = MyClass.new
      raise "FAIL1" unless m.value == "6"
      raise "FAIL2" unless m.value(2) == "110"
      m.add(10)
      m.add(20)
      raise "FAIL3" unless m.size == 2
      raise "FAIL4" unless m.label("n", ":") == "n:2"
      raise "FAIL5" unless m.greet == "hi"
      puts "ok"
    RUBY
  end

  it "singleton body macro calls" do
    result = ze0(<<~'RUBY')
      # A `class << self` body whose statements are CALLS: they run with the singleton
      # class as self, so the macros they invoke define class methods of the enclosing
      # class. The `extend Forwardable` + `def_delegators` pair is the corpus's most
      # common shape; `public`/`private` over a name list is fileutils'.

      require "forwardable"

      class Config
        def initialize
          @timeout = 30
          @retries = 2
        end

        attr_reader :timeout, :retries
      end

      class Client
        SETTINGS = Config.new

        class << self
          extend Forwardable

          def_delegators :settings, :timeout, :retries

          def settings
            SETTINGS
          end

          def a
            "a"
          end

          def b
            "b"
          end

          private :b
        end
      end

      puts Client.timeout
      puts Client.retries
      puts Client.a
      puts Client.respond_to?(:b)
      puts Client.send(:b)
      puts Client.singleton_class.private_method_defined?(:b)
    RUBY

    _(result).must_answer <<~'OUT'
      30
      2
      a
      false
      b
      true
    OUT
  end
end
