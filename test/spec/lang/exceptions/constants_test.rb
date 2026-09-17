# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: constants" do
  it "compact definition with an absent container" do
    result = ze0(<<~'RUBY')
      # `class A::B` evaluates `A` when the definition RUNS. If nothing defines it,
      # ruby raises NameError right there and the class never comes into being --
      # it is not a load-time error, and the rest of the file is unaffected until
      # execution reaches it. zeo used to fail the whole compile instead, which cost
      # 68 gems: mostly Rails extensions reopening a host they don't depend on.

      # Reached and rescued: the constant read is what raises.
      begin
        class ActiveRecord::Associations::CollectionProxy
          def bulk_import(*args) = :never
        end
      rescue NameError => e
        puts e.class
        puts e.message
      end

      # A deeper path names its OUTERMOST missing segment, not the leaf.
      begin
        module Nope::Deeper::Still
        end
      rescue NameError => e
        puts e.message
      end

      # The definition really did not happen.
      p defined?(ActiveRecord)
      p Object.const_defined?(:Nope)

      # A container that DOES exist still works, including one reached through the
      # enclosing lexical scope.
      module Toolkit
        module CLI; end
      end
      module Toolkit
        class CLI::Common
          def helpful = :yes
        end
      end
      p Toolkit::CLI::Common.new.helpful
      p Toolkit::CLI::Common.name

      # ... and a top-anchored one.
      module Outer; end
      class ::Outer::Inner
        def here = :top
      end
      p Outer::Inner.new.here
    RUBY

    _(result).must_answer <<~'OUT'
      NameError
      uninitialized constant ActiveRecord
      uninitialized constant Nope
      nil
      false
      :yes
      "Toolkit::CLI::Common"
      :top
    OUT
  end

  it "const path deep nesting" do
    result = ze0(<<~'RUBY')
      # Stress test: ConstantPathNode resolution at depths beyond what
      # typical Ruby code reaches. const_ref_flat_name and
      # resolve_const_ref_name now have a depth=32 guard; this test
      # exercises 6 levels (well below the cap, well above the 3-4
      # levels seen in the rest of the regression suite) to catch
      # off-by-one errors in the depth bookkeeping or any premature
      # truncation.

      module L1
        module L2
          module L3
            module L4
              module L5
                class L6
                  def self.tag
                    "L1::L2::L3::L4::L5::L6"
                  end

                  def echo(s)
                    s + " <- " + L1::L2::L3::L4::L5::L6.tag
                  end
                end
              end
            end
          end
        end
      end

      puts L1::L2::L3::L4::L5::L6.tag
      puts L1::L2::L3::L4::L5::L6.new.echo("hi")
    RUBY

    _(result).must_answer <<~'OUT'
      L1::L2::L3::L4::L5::L6
      hi <- L1::L2::L3::L4::L5::L6
    OUT
  end

  it "const self ref raises name error" do
    result = ze0(<<~'RUBY')
      # Issue #646: a top-level const assigned via `<CONST> = <Class>.
      # new(...)` whose initialize body (or any method transitively
      # called from initialize) reads <CONST> now raises NameError at
      # runtime, matching MRI semantics.
      #
      # Before the fix the read returned NULL (cst_<CONST> = NULL during
      # the assignment's RHS evaluation), and a subsequent `.method` or
      # `->iv_` deref segfaulted. The reporter's tep#13 case hit this
      # via PG::Connection.new -> Tep::Scheduler.scheduled_context? ->
      # Tep::APP.sched_current.
      #
      # Implementation:
      # * analyze records `<CONST>`'s init RHS class (when it's
      #   `<Class>.new(...)`) in @const_init_class.
      # * codegen emits `static int sp_init_in_progress_<CONST>` and
      #   sets it around the assignment in main.
      # * read sites of <CONST> wrap with `(flag ? raise_NameError :
      #   cst_<CONST>)`.

      class App
        def initialize
          @arr = []
          @arr << 1   # force heap allocation so App is not value-type
          begin
            _ = APP
            puts "direct: no raise"
          rescue NameError => e
            puts "direct: " + e.message
          end
          helper
        end

        def helper
          begin
            _ = APP
            puts "indirect: no raise"
          rescue NameError => e
            puts "indirect: " + e.message
          end
        end
      end

      APP = App.new
      puts "after: APP class = " + APP.class.name
    RUBY

    _(result).must_answer <<~'OUT'
      direct: uninitialized constant App::APP
      indirect: uninitialized constant App::APP
      after: APP class = App
    OUT
  end

  it "exception class constants" do
    result = ze0(<<~'RUBY')
      # Builtin exception classes as first-class values: referencing the constant
      # (raise_error matchers, e.class comparisons, superclass walks) works like any
      # other builtin class object; raise/rescue position already resolved by name.
      # RuntimeError.superclass is StandardError (CRuby), previously Exception.
      p IndexError
      p FrozenError
      x = ZeroDivisionError
      p x
      p IndexError.name
      begin; raise IndexError, "m"; rescue => e; p e.class == IndexError; end
      p KeyError.superclass
      p FrozenError.superclass
      p RuntimeError.superclass
      p NotImplementedError.superclass
      p FloatDomainError.ancestors.include?(RangeError)
      p IndexError < StandardError
      p LocalJumpError <= Exception
    RUBY

    _(result).must_answer <<~'OUT'
      IndexError
      FrozenError
      ZeroDivisionError
      "IndexError"
      true
      IndexError
      RuntimeError
      StandardError
      ScriptError
      true
      true
      true
    OUT
  end

  it "missing qualified constant raises name error with the full path" do
    _(ze0(<<~'RUBY')).must_answer "NameError: uninitialized constant Store::MISSING\n"
      module Store
      end

      begin
        puts Store::MISSING
      rescue NameError => e
        puts "NameError: #{e.message}"
      end
    RUBY
  end

  it "module const get resolves or raises name error" do
    result = ze0(<<~'RUBY')
      class Foo; BAR = 42; end
      p Foo.const_get(:BAR)
      p Foo.const_get("BAR")
      p Object.const_get(:Foo)
      p((Object.const_get(:MissingXYZ) rescue $!.class))
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      Foo
      NameError
    OUT
  end

  it "nameerror name for constant" do
    result = ze0(<<~'RUBY')
      module CM
        A = 1
      end
      begin
        CM.const_get(:nope)
      rescue NameError => e
        p e.name
      end
      begin
        CM::Nope
      rescue NameError => e
        p e.name
      end
    RUBY

    _(result).must_answer <<~'OUT'
      :nope
      :Nope
    OUT
  end

  it "raise class value" do
    result = ze0(<<~'RUBY')
      # `raise` given the exception CLASS as a VALUE -- a local, an element of a
      # table of error classes, a retry list -- rather than as a syntactically
      # literal constant name. Codegen builds the literal form directly and hands
      # every other operand to the runtime coercion, which raises a fresh instance
      # of an Exception class through `#exception` (so a custom `initialize` runs),
      # raises an Exception object as itself, wraps a String in a `RuntimeError`,
      # and answers `TypeError: exception class/object expected` for anything else.
      module App
        class Failed < RuntimeError; end
        class Refused < App::Failed; end
      end

      k = App::Failed
      begin
        raise k
      rescue => e
        puts "#{e.class}|#{e.message}|#{e.is_a?(App::Failed)}"
      end

      [App::Failed, App::Refused, ArgumentError].each do |kk|
        begin
          raise kk
        rescue => e
          puts "#{e.class}|#{e.is_a?(App::Failed)}"
        end
      end

      # a rescue arm still selects on the raised class
      begin
        raise App::Refused
      rescue App::Failed => e
        puts "caught #{e.class}"
      end

      # a non-exception class is still CRuby's TypeError
      bad = String
      begin
        raise bad
      rescue TypeError => e
        puts "TypeError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      App::Failed|App::Failed|true
      App::Failed|true
      App::Refused|true
      ArgumentError|false
      caught App::Refused
      TypeError
    OUT
  end

  it "raising an undefined constant with a message raises name error" do
    _(ze0(<<~'RUBY')).must_answer "NameError: uninitialized constant Nope\n"
      # `raise UndefinedConst, "msg"` -- CRuby evaluates the constant (and
      # raises NameError) before the message is ever consulted.

      r = begin
        raise Nope, "msg"
      rescue => e
        "#{e.class}: #{e.message}"
      end
      puts r
    RUBY
  end

  it "rescue naming an undefined constant raises name error when matched" do
    _(ze0(<<~'RUBY')).must_answer "NameError: uninitialized constant NeverDefined\n"
      # When the body DOES raise, evaluating the undefined rescue constant is a
      # runtime NameError (which replaces the original exception) -- exactly
      # CRuby's behavior.

      begin
        begin
          raise "boom"
        rescue NeverDefined
          puts "caught"
        end
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY
  end

  it "rescue undefined constant" do
    result = ze0(<<~'RUBY')
      # A `rescue` clause naming an undefined constant compiles cleanly: CRuby only
      # evaluates the clause's class while matching an actually-raised exception.

      # Never fires -> the undefined name is never evaluated.
      begin
        1 + 1
      rescue NeverDefined
        puts "unreachable"
      end
      puts "no exception: ok"

      # Fires -> evaluating the undefined constant is a runtime NameError, which
      # replaces the original exception.
      begin
        begin
          raise "boom"
        rescue NeverDefined
          puts "unreachable"
        end
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      no exception: ok
      NameError: uninitialized constant NeverDefined
    OUT
  end

  it "rescued missing constant quiet" do
    result = ze0(<<~'RUBY')
      # Referencing a constant the program never defines, on purpose, behind a rescue
      # that catches the NameError is how a program probes for one -- ruby/spec does
      # exactly this. CRuby says nothing about it at any stage, and spinel's
      # defined-nowhere warning reported a program whose behaviour was already right
      # (#4062). The warning is for a reference nothing catches, and still fires there.
      p(begin; NoSuchConstA; rescue NameError => e; e.class.to_s; end)

      r = begin
        NoSuchConstB
      rescue => e
        e.class.to_s
      end
      p r

      c = (NoSuchConstC rescue "caught")
      p c

      def probe
        NoSuchConstD
      rescue NameError
        "rescued in a method"
      end
      p probe

      # a nested rescue whose OUTER clause is the one that catches it
      p(begin
          begin
            NoSuchConstE
          rescue TypeError
            "wrong one"
          end
        rescue NameError
          "outer caught it"
        end)
    RUBY

    _(result).must_answer <<~'OUT'
      "NameError"
      "NameError"
      "caught"
      "rescued in a method"
      "outer caught it"
    OUT
  end

  it "undefined constant deferred raise" do
    result = ze0(<<~'RUBY')
      # An undefined constant used in class position raises a runtime NameError,
      # never a compile-time failure -- shown across a pattern, a scoped constant
      # write, and `raise Const, msg`.

      x = 5
      begin
        case x
        in NopeClass then puts "unreachable"
        else puts "unreachable"
        end
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      # The scope is resolved BEFORE the RHS runs, so "rhs" never prints.
      begin
        Nope::X = (puts "rhs"; 5)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        raise Nope, "msg"
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      NameError: uninitialized constant NopeClass
      NameError: uninitialized constant Nope
      NameError: uninitialized constant Nope
    OUT
  end

  it "uninit const raises nameerror" do
    result = ze0(<<~'RUBY')
      # Uninitialised constant reads raise NameError instead of
      # silently returning 0.

      begin
        puts NONEXISTENT_CONST
      rescue NameError
        puts "uninit raised"
      end

      # Self-referential init `X = X + 1` reads X before X is bound;
      # CRuby raises NameError. Spinel previously evaluated X as 0
      # and assigned 1.
      begin
        X = X + 1
        puts X
      rescue NameError
        puts "self-ref raised"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      uninit raised
      self-ref raised
    OUT
  end

  it "unset constant raises a name error" do
    _(ze0(<<~'RUBY')).must_answer "caught: uninitialized constant UNDEFINED_CONST\n"
      begin
        puts UNDEFINED_CONST
      rescue NameError => e
        puts "caught: #{e.message}"
      end
    RUBY
  end
end
