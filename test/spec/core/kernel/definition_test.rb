# frozen_string_literal: true

require "spec_helper"

describe "Kernel: defining and naming methods" do
  it "callee answers the called name" do
    result = zr(<<~'RUBY')
      class Klass
        def self.original = __callee__
        singleton_class.alias_method :nickname, :original
      end
      p [Klass.original, Klass.nickname]

      [1].each do
        def blk = [__method__, __callee__]
        alias blk_alias blk
      end
      p [blk, blk_alias]

      o = Object.new
      def o.sing = [__method__, __callee__]
      o.singleton_class.alias_method :sing_alias, :sing
      p [o.sing, o.sing_alias]

      class Runtime
        def base = __callee__
      end
      Runtime.send(:alias_method, :late, :base)
      p [Runtime.new.base, Runtime.new.late]
    RUBY

    _(result).must_answer <<~'OUT'
      [:original, :nickname]
      [[:blk, :blk], [:blk, :blk_alias]]
      [[:sing, :sing], [:sing, :sing_alias]]
      [:base, :late]
    OUT
  end

  it "implicit self and respond to" do
    result = zr(<<~'RUBY')
      class Greeter
        def greet
          hello
        end

        def hello
          "hi from hello"
        end
      end

      puts Greeter.new.greet

      class Counter
        def initialize
          @count = 0
        end

        def bump(n)
          add(n)
          @count
        end

        def add(n)
          @count = @count + n
        end
      end

      c = Counter.new
      puts c.bump(5)
      puts c.bump(2)

      class Box
        def initialize(v)
          @v = v
        end

        def value
          @v
        end

        def describe
          self.value
        end

        def identity
          self
        end
      end

      b = Box.new(42)
      puts b.describe
      puts b.identity.value

      class Dog
        def bark
          "woof"
        end
      end

      d = Dog.new
      puts d.respond_to?(:bark)
      puts d.respond_to?(:meow)

      class Collector
        def initialize(tag)
          @tag = tag
        end

        def tag
          @tag
        end

        def each_num(a, b)
          yield a
          yield b
        end

        def run(a, b)
          each_num(a, b) { |n| puts "tag=#{self.tag}:#{n}" }
        end
      end

      Collector.new("x").run(1, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      hi from hello
      5
      7
      42
      42
      true
      false
      tag=x:1
      tag=x:2
    OUT
  end

  it "implicit self send" do
    result = zr(<<~'RUBY')
      # Implicit-self send(:literal), __send__ and public_send call the method.
      # A `send(:` inside a string literal is only text.
      class Dispatcher
        def greet; "hi"; end
        def add(a, b); a + b; end
        def call_greet; send(:greet); end
        def call_add; send(:add, 2, 3); end
        def str_form; __send__("greet"); end
        def pub; public_send(:greet); end
      end
      d = Dispatcher.new
      puts d.call_greet
      puts d.call_add
      puts d.str_form
      puts d.pub
      puts "x".send(:upcase)             # explicit receiver still works
      puts "literal send(:foo) stays"    # string literal must be untouched
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      5
      hi
      hi
      X
      literal send(:foo) stays
    OUT
  end

  it "fail is an exact alias of raise, a bare one inside a rescue included" do
    result = zr(<<~'RUBY')
      # Kernel#fail is an exact alias of Kernel#raise: a bare message raises a
      # RuntimeError, an explicit class + message raises that class, and a bare `fail`
      # inside a rescue re-raises the current exception.

      # message form -> RuntimeError
      begin
        fail "boom"
      rescue => e
        puts "#{e.class}: #{e.message}"   # RuntimeError: boom
      end

      # explicit class + message
      class MyError < StandardError; end
      begin
        fail MyError, "bad input"
      rescue => e
        puts "#{e.class}: #{e.message}"   # MyError: bad input
      end

      # explicit class only -> default message is the class name
      begin
        fail MyError
      rescue => e
        puts "#{e.class}: #{e.message}"   # MyError: MyError
      end

      # bare `fail` inside a rescue re-raises the current exception
      begin
        begin
          raise "original"
        rescue
          fail
        end
      rescue => e
        puts "#{e.class}: #{e.message}"   # RuntimeError: original
      end

      # raise still works alongside fail
      begin
        raise ArgumentError, "still works"
      rescue => e
        puts "#{e.class}: #{e.message}"   # ArgumentError: still works
      end
    RUBY

    _(result).must_answer <<~'OUT'
      RuntimeError: boom
      MyError: bad input
      MyError: MyError
      RuntimeError: original
      ArgumentError: still works
    OUT
  end

  it "__id__ is an alias of object_id" do
    result = zr(<<~'RUBY')
      # Kernel#__id__ is an alias of #object_id.
      p(42.__id__ == 42.object_id)
      p("x".__id__.class)
      p(nil.__id__)
      p(:sym.__id__ == :sym.object_id)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      Integer
      4
      true
    OUT
  end

  it "respond to implicit self" do
    result = zr(<<~'RUBY')
      class Screen
        attr_accessor :width
        attr_writer :depth
        attr_reader :label

        def initialize
          @width = 320
          @depth = 8
          @label = "screen"
          @fullscreen = false
        end

        def fullscreen=(v)
          @fullscreen = v
        end

        def resize
          42
        end

        def apply(key, value)
          case key
          when :fullscreen
            self.fullscreen = value if respond_to?(:fullscreen=)
            puts "fullscreen set"
          when :width
            self.width = value if respond_to?(:width=)
            puts "width set"
          end
        end

        def probe
          puts respond_to?(:resize)
          puts respond_to?(:width)
          puts respond_to?(:width=)
          puts respond_to?(:depth=)
          puts respond_to?(:label)
          puts respond_to?(:label=)
          puts respond_to?(:missing_method)
          puts respond_to?(:to_s)
        end

        def self.build
          puts respond_to?(:build)
          puts respond_to?(:nope)
          # builtin Class capabilities on the implicit class object
          puts respond_to?(:new)
          puts respond_to?(:allocate)
          puts respond_to?(:name)
          new
        end
      end

      module Palette
        def self.probe
          puts respond_to?(:probe)
          puts respond_to?(:new)  # a module does not respond to new
        end
      end

      s = Screen.build
      Palette.probe
      s.apply(:fullscreen, true)
      s.apply(:width, 640)
      s.probe
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      true
      false
      fullscreen set
      width set
      true
      true
      true
      true
      true
      false
      false
      true
    OUT
  end

  it "respond to kernel mixin" do
    result = zr(<<~'RUBY')
      class C; end
      c = C.new
      puts c.respond_to?(:display)
      puts c.respond_to?(:yield_self)
      puts c.respond_to?(:no_such_method)
      class Nums
        include Enumerable
        def initialize(*xs)
          @xs = xs
        end
        def each
          @xs.each { |x| yield x }
        end
      end
      p(Nums.new(1, 2).respond_to?(:map))
      p(Nums.new(1, 2).respond_to?(:sort_by))
      p(Nums.new(1, 2).respond_to?(:no_such))
      p(:abc.respond_to?(:to_proc))
      pr = ->(x) { x }
      p pr.respond_to?(:call)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      true
      false
      true
      true
    OUT
  end

  it "respond to on implicit self inside a class method" do
    result = zr(<<~'RUBY')
      # Implicit-self respond_to? inside a `def self.x` resolves against the
      # class value (like explicit self.respond_to?), so a sibling class method
      # answers true, not false.

      class Screen
        def self.build
          puts respond_to?(:build)
          puts respond_to?(:name)
          puts respond_to?(:nope_xyz)
        end
        def self.other; end
      end
      Screen.build
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
    OUT
  end

  it "runtime define method in a class body loop" do
    result = zr(<<~'RUBY')
      # A class-body `each` loop whose `define_method` block captures the loop
      # variable installs each method into the runtime overlay, reachable on
      # every instance and by `respond_to?`.

      class Robot
        [:beep, :boop].each do |sound|
          define_method(sound) { "#{sound}!" }
        end
      end
      r = Robot.new
      puts r.beep
      puts r.boop
      puts r.respond_to?(:beep)
      puts r.respond_to?(:whir)
    RUBY

    _(result).must_answer <<~'OUT'
      beep!
      boop!
      true
      false
    OUT
  end

  it "user def fail outranks the kernel alias" do
    result = zr(<<~'RUBY')
      # `fail` is `Kernel#raise`'s exact synonym -- and a popular USER method
      # name. Resolution order is real Ruby's: a `def fail` in the receiver's
      # chain wins over the Kernel meaning, however many arguments it takes.
      #
      # zr desugared every receiverless `fail` to `HirNode::Raise` at parse
      # time, before method resolution existed -- riot's reporter (`def fail(
      # description, message, line, file)`, four arguments) died with "wrong
      # number of arguments (given 4, expected 0..3)", and took ten gems with it.
      class Reporter
        def fail(description, message, line, file)
          puts "FAIL #{description}: #{message} (#{file}:#{line})"
        end

        def report
          fail("addition", "1 != 2", 3, "math.rb")
          :reported
        end
      end

      puts Reporter.new.report

      # The Kernel meaning survives everywhere no user `fail` is in scope:
      # bare re-raise semantics, the class-and-message form, and rescue.
      begin
        fail "plain kernel fail"
      rescue RuntimeError => e
        puts e.message
      end

      begin
        fail ArgumentError, "typed kernel fail"
      rescue ArgumentError => e
        puts e.message
      end

      # ...including inside a method of a class that defines NO fail.
      class Quiet
        def go
          fail "from a quiet method"
        end
      end

      begin
        Quiet.new.go
      rescue RuntimeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      FAIL addition: 1 != 2 (math.rb:3)
      reported
      plain kernel fail
      typed kernel fail
      from a quiet method
    OUT
  end
end
