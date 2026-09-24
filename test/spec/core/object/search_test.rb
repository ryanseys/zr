# frozen_string_literal: true

require "spec_helper"

describe "Object: searching and matching" do
  it "boxs class method is absent from mains reflection" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # Reflection agrees with dispatch. A name the box defined must not appear
      # in main's `singleton_methods`, which reads a name set with no box axis of
      # its own.



      b = Ruby::Box.new
      b.eval("class Array; def self.zzz = 1; end")
      p Array.singleton_methods(false).include?(:zzz)
      p b.eval("Array.singleton_methods(false).include?(:zzz)")
    RUBY

    _(result).must_answer "false\ntrue\n"
  end

  it "core method owners match" do
    skip "runs only on macos" unless ["macos"].include?(Zr::Spec.platform)

    result = zr(<<~'RUBY')

      # The methods each core class and module defines itself, by visibility,
      # and the constants it holds, as ruby 4.0 lists them. Names that rubygems
      # and irb's Binding#irb define are left out, and so is RubyVM's parse.y
      # surface: the ISEQ class and the AST's nodes.
      LATER = %i[Gem RUBYGEMS_ACTIVATION_MONITOR irb InstructionSequence Location Node parse parse_file].freeze
      GEMS = %i[gem gem_original_require require require_relative].freeze
      mods = [BasicObject, Object, Kernel, Module, Class, Comparable, Enumerable, NilClass, TrueClass, FalseClass,
              Integer, Float, Numeric, Rational, Complex, String, Symbol, Array, Hash, Range, Struct, Data, Set,
              Proc, Method, UnboundMethod, Binding, Exception, StandardError, NameError, NoMethodError, KeyError,
              StopIteration, FrozenError, SystemExit, SignalException, SystemCallError, UncaughtThrowError,
              IO, File, File::Stat, Dir, Time, Random, Regexp, MatchData, Encoding, Encoding::Converter,
              Enumerator, Enumerator::Lazy, Enumerator::Yielder, Enumerator::Generator, Enumerator::Chain,
              Enumerator::ArithmeticSequence, Enumerator::Product,
              Thread, Thread::Mutex, Thread::Queue, Thread::SizedQueue, Thread::ConditionVariable, ThreadGroup,
              Fiber, Process::Status, ObjectSpace::WeakMap, ObjectSpace::WeakKeyMap, Marshal, Math, GC, Process,
              Signal, Warning, TracePoint, Ractor, Refinement, ObjectSpace, FileTest, Errno::ENOENT,
              RubyVM, RubyVM::AbstractSyntaxTree, RubyVM::YJIT]
      mods.each do |m|
        rows = {
          public: m.public_instance_methods(false),
          protected: m.protected_instance_methods(false),
          private: m.private_instance_methods(false) - GEMS,
          singleton: m.singleton_methods(false),
          constants: m.constants(false)
        }
        rows.each do |kind, names|
          names -= LATER
          puts "#{m} #{kind}: #{names.sort.join(' ')}"
        end
      end




    RUBY

    _(result).must_answer fixture("core/object/method_owners.out")
  end

  it "define singleton method in a def installs at runtime" do
    result = zr(<<~'RUBY')
      # `SomeClass.define_singleton_method(:name) { }` written INSIDE a method
      # body (cannon and `by` retarget class methods mid-run; rails_admin
      # intercepts Object.const_missing this way) is a runtime overlay install,
      # not a class reopen -- there is no class-body site to register in a def.
      # (Whether a runtime-installed `const_missing` HOOK is consulted by a
      # folded constant read is the separate, documented divergence in
      # const_missing_on_a_named_class.rb.)
      class Router
        def self.routes
          "static routes"
        end
      end

      class App
        def boot(answer)
          Router.define_singleton_method(:routes) { "runtime #{answer}" }
        end
      end

      p Router.routes
      App.new.boot(42)
      p Router.routes
      p Router.singleton_methods.include?(:routes)

      # A fresh singleton method (no static row at all), with a capture.
      class Gauge; end
      def calibrate(offset)
        Gauge.define_singleton_method(:read) { 100 + offset }
      end
      calibrate(7)
      p Gauge.read

      # Receiverless inside a def installs on the method's own self.
      class Widget
        def specialize
          define_singleton_method(:kind) { :special }
          self
        end
      end
      w = Widget.new.specialize
      p w.kind
      p Widget.new.respond_to?(:kind)
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      "static routes"
      "runtime 42"
      true
      107
      :special
      false
      still running
    OUT
  end

  it "enum chain with index object" do
    result = zr(<<~'RUBY')
      # str.each_char.with_index (block form) and enum.each.with_object desugar
      # into the shapes the chain emitters already serve.
      "abc".each_char.with_index { |c, i| print "#{i}#{c}" }
      puts
      "xy".each_char.with_index(10) { |c, i| print "#{i}:#{c} " }
      puts
      x = [1, 2, 3].each.with_object([]) { |v, a| a << v * 2 }
      p x
      h = [1, 2].each.with_object({}) { |v, acc| acc[v.to_s] = v }
      p h.size
    RUBY

    _(result).must_answer "0a1b2c\n10:x 11:y \n[2, 4, 6]\n2\n"
  end

  it "is a and instance of answer through class values" do
    result = zr(<<~'RUBY')
      class Widget
      end
      module Helper
      end

      w = Widget.new
      puts w.instance_of?(Widget)
      puts w.instance_of?(Object)
      puts 5.instance_of?(Integer)
      puts Widget.is_a?(Class)
      puts Widget.is_a?(Module)
      puts Helper.is_a?(Module)
      puts Helper.is_a?(Class)
      puts Widget.ancestors.first == Widget
      puts Widget.ancestors.include?(Object)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      true
      false
      true
      true
    OUT
  end

  it "is a included module" do
    result = zr(<<~'RUBY')
      module M
        def foo; 42; end
      end

      module N
      end

      class C
        include M
      end

      class D
        include M
        include N
      end

      c = C.new
      p c.foo
      p c.is_a?(M)
      p c.is_a?(N)
      p C.ancestors.include?(M)
      p C.ancestors.include?(N)

      d = D.new
      p d.is_a?(M)
      p d.is_a?(N)
      p D.ancestors.include?(M)
      p D.ancestors.include?(N)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      true
      false
      true
      false
      true
      true
      true
      true
    OUT
  end

  it "is a undefined const" do
    result = zr(<<~'RUBY')
      # x.is_a?(NoSuchConst): the is_a?-family arms match the target constant
      # textually and never emit the constant read, so an undefined constant
      # silently answered false where CRuby raises NameError.
      [5, "s", String].each do |x|
        begin
          x.is_a?(NoSuchConst)
          puts "no raise"
        rescue NameError => e
          puts "NameError: #{e.message}"
        end
      end
      # defined targets keep their answers
      p 5.is_a?(Integer)
      p 5.is_a?(Comparable)
      p String.is_a?(Module)
      p String.is_a?(Comparable)
    RUBY

    _(result).must_answer <<~'OUT'
      NameError: uninitialized constant NoSuchConst
      NameError: uninitialized constant NoSuchConst
      NameError: uninitialized constant NoSuchConst
      true
      true
      true
      false
    OUT
  end

  it "nil sentinel from index compact" do
    result = zr(<<~'RUBY')
      # A miss from String#index / #rindex is nil, and every consumer has to agree:
      # an int slot carrying the nil sentinel must box as nil, so compact drops it
      # and filter_map treats it as falsy.
      v = "a".rindex("/")
      w = "abc".index("b")
      p v.nil?
      p v.class
      p [v, 1].compact
      p [v, 1].filter_map { |x| x }
      p [v, w, 3].compact
      p [v, 1].compact.size
      p [1, v, 2].compact.sum

      # the same for an out-of-range slice on a String array and a Float miss
      s = "x"[5, 1]
      p [s, "y"].compact
      g = [].first
      p [g, 1.5].compact

      # a live nil in the same position still behaves
      p [nil, 1].compact
      p [v].compact.empty?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      NilClass
      [1]
      [1]
      [1, 3]
      1
      3
      ["y"]
      [1.5]
      [1]
      true
    OUT
  end
end
