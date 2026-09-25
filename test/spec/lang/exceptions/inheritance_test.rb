# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: inheritance and ancestors" do
  it "bare rescue standard error only" do
    result = zr(<<~'RUBY')
      # A bare `rescue` matches only StandardError and its subclasses. An Exception
      # or NotImplementedError (which is a ScriptError, not a StandardError) falls
      # through to a later `rescue Exception`.
      def br(e)
        begin
          raise e
        rescue => x
          "bare"
        rescue Exception => x
          "typed"
        end
      end

      p br(NotImplementedError.new)   # "typed"  (NotImplementedError < ScriptError)
      p br(Exception.new)             # "typed"
      p br(ArgumentError.new)         # "bare"   (ArgumentError < StandardError)
      p br(RuntimeError.new)          # "bare"
      p br(KeyError.new)              # "bare"   (KeyError < IndexError < StandardError)

      # NotImplementedError is NOT a StandardError.
      p NotImplementedError.new.is_a?(StandardError)   # false
      p NotImplementedError.new.is_a?(ScriptError)     # true
    RUBY

    _(result).must_answer <<~'OUT'
      "typed"
      "typed"
      "bare"
      "bare"
      "bare"
      false
      true
    OUT
  end

  it "core exception tree is nameable and rescuable" do
    result = zr(<<~'RUBY')
      # The `Exception`-direct classes (uncaught by a bare `rescue`) and the
      # refined `StandardError`-branch classes all register with the right
      # superclass and can be raised/rescued by name.

      p SystemExit.superclass
      p Interrupt.superclass
      p NoMemoryError.superclass
      p NoMatchingPatternKeyError.superclass
      p Regexp::TimeoutError.superclass
      p IO::TimeoutError.superclass
      begin
        raise SecurityError, "denied"
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Exception
      SignalException
      Exception
      NoMatchingPatternError
      RegexpError
      IOError
      SecurityError: denied
    OUT
  end

  it "exception classes work across namespaces" do
    result = zr(<<~'RUBY')
      # Subclassing a nested error class from outside, raising with a
      # qualified path, and rescue-matching through the shared ancestor.

      module Errs
        class Base3 < StandardError
        end
      end

      class Deep < Errs::Base3
      end

      begin
        raise Deep, "boom"
      rescue Errs::Base3 => e
        puts "caught #{e.message}"
      end

      begin
        raise Errs::Base3, "direct"
      rescue StandardError => e
        puts "caught #{e.message}"
      end
    RUBY

    _(result).must_answer "caught boom\ncaught direct\n"
  end

  it "exception detailed message" do
    result = zr(<<~'RUBY')
      # Exception#detailed_message returns "message (ClassName)". (The core method;
      # the optional error_highlight gem's source-snippet augmentation, which applies
      # to a few argument-style errors, is a separate concern and not reproduced.)

      # a RuntimeError carrying a message
      begin
        raise "boom"
      rescue => e
        p e.detailed_message            # "boom (RuntimeError)"
      end

      # an explicit class with a message
      begin
        raise StandardError, "bad state"
      rescue => e
        p e.detailed_message            # "bad state (StandardError)"
      end

      # no message -> the class name is used as the message
      begin
        raise RuntimeError
      rescue => e
        p e.detailed_message            # "RuntimeError (RuntimeError)"
      end

      # a user-defined exception subclass
      class MyError < StandardError; end
      begin
        raise MyError, "oops"
      rescue => e
        p e.detailed_message            # "oops (MyError)"
      end

      # message and detailed_message side by side
      begin
        raise "x"
      rescue => e
        p [e.message, e.detailed_message]   # ["x", "x (RuntimeError)"]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "boom (RuntimeError)"
      "bad state (StandardError)"
      "RuntimeError (RuntimeError)"
      "oops (MyError)"
      ["x", "x (RuntimeError)"]
    OUT
  end

  it "exception exception subclass copy" do
    result = zr(<<~'RUBY')
      class SimpleError < StandardError
        attr_reader :code
        def initialize(code); @code = code; super("simple"); end
      end
      e010 = SimpleError.new(3); f010 = e010.exception("other"); p f010.class; p f010.message

      e = SimpleError.new(7)
      f = e.exception("changed")
      p f.code
      p f.equal?(e)
      p e.exception.equal?(e)
      r = (raise SimpleError.new(9) rescue $!.exception("x")); p [r.class, r.message]
    RUBY

    _(result).must_answer <<~'OUT'
      SimpleError
      "other"
      7
      false
      true
      [SimpleError, "x"]
    OUT
  end

  it "exception namespaced default message" do
    result = zr(<<~'RUBY')
      # The default message of a namespaced exception class uses Ruby's
      # `::` module separator, as in "ActiveRecord::RecordNotFound".

      module ActiveRecord
        class RecordNotFound < StandardError
        end

        class RecordInvalid < StandardError
        end
      end

      module Outer
        module Inner
          class DeepError < StandardError
          end
        end
      end

      # Non-namespaced subclass with underscore in its name should NOT
      # get the underscore replaced (My_Class is one identifier).
      class My_Class < StandardError
      end

      puts ActiveRecord::RecordNotFound.new.message
      puts ActiveRecord::RecordInvalid.new.message
      puts Outer::Inner::DeepError.new.message
      puts My_Class.new.message
    RUBY

    _(result).must_answer <<~'OUT'
      ActiveRecord::RecordNotFound
      ActiveRecord::RecordInvalid
      Outer::Inner::DeepError
      My_Class
    OUT
  end

  it "exception subclass" do
    result = zr(<<~'RUBY')
      # A user exception subclass is backed by the native RubyException (D3): custom
      # ivars, `super` into the native initialize (hidden message slot), multi-level
      # inheritance, class methods, and rescue-by-ancestry all match CRuby.

      class AppError < StandardError
        def initialize(code)
          @code = code
          super("app error #{code}")
        end

        def code
          @code
        end

        def self.with_code(n)
          new(n)
        end
      end

      class NotFound < AppError
        def initialize
          super(404)
          @where = "here"
        end

        def where
          @where
        end
      end

      e = AppError.new(7)
      puts e.message
      puts e.code
      p e.instance_variables
      p e.instance_variable_get(:@message)

      nf = NotFound.new
      puts nf.message
      puts nf.code
      puts nf.where
      puts nf.is_a?(AppError)
      puts nf.is_a?(StandardError)

      puts AppError.with_code(9).message

      begin
        raise NotFound
      rescue AppError => ex
        puts "rescued #{ex.class}: #{ex.message}"
      end

      # A subclass with no initialize inherits the native default.
      class Plain < RuntimeError
      end
      puts Plain.new("plain msg").message
      p Plain.new("plain msg").instance_variables
    RUBY

    _(result).must_answer <<~'OUT'
      app error 7
      7
      [:@code]
      nil
      app error 404
      404
      here
      true
      true
      app error 9
      rescued NotFound: app error 404
      plain msg
      []
    OUT
  end

  it "exception subclass accessors" do
    result = zr(<<~'RUBY')
      class SubX < StandardError; end
      p(SubX.new("m").cause)
      p(SubX.new("m").backtrace)
      p(SubX.new("m").message)
      p(SubX.new("m").detailed_message)
      p(SubX.new("m").exception.class)
      e = (begin; raise SubX, "z"; rescue SubX => x; x; end)
      p e.cause
      p e.message
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      "m"
      "m (SubX)"
      SubX
      nil
      "z"
    OUT
  end

  it "exception subclass custom method" do
    result = zr(<<~'RUBY')
      # A user-defined method (or attr_reader) on an exception subclass dispatches:
      # the instance keeps its concrete class instead of collapsing to the base
      # exception type, while message/class/is_a? still route through the
      # exception machinery.
      class MyError < StandardError
        attr_reader :code
        def initialize(code = 7)
          super("failed(#{code})")
          @code = code
        end
        def detail = "boom detail"
      end

      puts MyError.new.detail
      e = MyError.new(42)
      puts e.detail
      puts e.code
      puts e.message
      puts e.class
      puts e.is_a?(MyError)
      puts e.is_a?(StandardError)
      puts e.is_a?(RuntimeError)
      begin
        raise MyError.new(9)
      rescue MyError => ex
        puts "#{ex.class}: #{ex.message} code=#{ex.code}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      boom detail
      boom detail
      42
      failed(42)
      MyError
      true
      true
      false
      MyError: failed(9) code=9
    OUT
  end

  it "exception subclass eq exception" do
    result = zr(<<~'RUBY')
      class SubX < StandardError; end
      p(SubX.new("t") == StandardError.new("t"))

      e001 = SubX.new(3); f001 = e001.exception("other"); p f001.class; p f001.message

      p(SubX.new("t") == SubX.new("t"))    # => true
      p(SubX.new("m").exception.class)     # => SubX
      p(SubX.new("m").cause)               # => nil
      begin; raise SubX, "m"; rescue SubX => e002; p e002.cause; end   # => nil
    RUBY

    _(result).must_answer <<~'OUT'
      false
      SubX
      "other"
      true
      SubX
      nil
      nil
    OUT
  end

  it "exception subclass instance is a boxed value everywhere" do
    result = zr(<<~'RUBY')
      # A user-defined `class EE < Exception` instance works correctly
      # wherever it is passed, even through indirect construction and
      # yielding across module and class boundaries (the shape used by the
      # timeout gem's `ExitException`).

      module T
        class EE < Exception
        end
        class Er < RuntimeError
          def self.go(m)
            exc = EE.new(m)
            yield exc
          end
        end
      end
      T::Er.go("x") { |e| puts e.class; puts e.message }
    RUBY

    _(result).must_answer "T::EE\nx\n"
  end

  it "exception subclass ivar" do
    result = zr(<<~'RUBY')
      class MyError < StandardError
        attr_reader :record
        def initialize(record)
          super("boom")
          @record = record
        end
      end
      begin
        raise MyError.new("the-record")
      rescue MyError => e
        puts e.message
        puts e.record
      end
    RUBY

    _(result).must_answer "boom\nthe-record\n"
  end

  it "exception subclass ivar reraise" do
    result = zr(<<~'RUBY')
      class PlainErr < StandardError; end
      class DataErr < StandardError
        attr_reader :data
        def initialize(d); super("data fail"); @data = d; end
      end
      begin
        raise PlainErr, "plain"
      rescue PlainErr => pe
        puts pe.message
      end
      begin
        raise DataErr.new(42)
      rescue StandardError => se   # broader catch: message works
        puts se.message
      end
      begin
        begin
          raise DataErr.new(7)
        rescue DataErr => de
          puts de.data
          raise
        end
      rescue => re
        puts "reraised: #{re.message}"
      end
      begin
        raise ArgumentError, "bad arg"
      rescue ArgumentError => ae
        puts ae.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      plain
      data fail
      7
      reraised: data fail
      bad arg
    OUT
  end

  it "exception subclass p inspect" do
    result = zr(<<~'RUBY')
      # `p` on a user exception subclass renders like #inspect does, not as the
      # object default.
      class E1 < StandardError; end
      class E2 < StandardError
        def initialize(m = "d"); super; end
      end
      p(E1.new("m"))
      p(E1.new("m").inspect)
      p(E1.new)
      p(E2.new)
      p(RuntimeError.new("via p"))
      a = [E1.new("in array")]
      p a
    RUBY

    _(result).must_answer <<~'OUT'
      #<E1: m>
      "#<E1: m>"
      #<E1: E1>
      #<E2: d>
      #<RuntimeError: via p>
      [#<E1: in array>]
    OUT
  end

  it "exception subclass raise 2arg" do
    result = zr(<<~'RUBY')
      class RecordInvalid < StandardError
        attr_reader :record
        def initialize(record)
          super("validation failed")
          @record = record
        end
      end
      begin
        raise RecordInvalid, "the-rec"
      rescue RecordInvalid => e
        puts e.message
        puts e.record
      end
    RUBY

    _(result).must_answer "validation failed\nthe-rec\n"
  end

  it "exception subclass result slot" do
    result = zr(<<~'RUBY')
      # An exception subclass with ivars keeps StopIteration#result apart from its
      # own ivars. A StopIteration subclass carrying an ivar reports nil #result,
      # because it got no iteration value. A non-nil #result would mean `result`
      # shares storage with @limit; 0 would mean `result` never got nil.
      class BoundedStop < StopIteration
        def initialize(limit)
          super("stop")
          @limit = limit
        end
      end

      begin
        raise BoundedStop.new(7)
      rescue StopIteration => e
        p e.result
      end

      # holds across repeated allocation churn (GC may scan live subclass exceptions)
      ok = true
      50.times do |i|
        begin
          raise BoundedStop.new(i)
        rescue StopIteration => e
          ok = false unless e.result.nil?
        end
      end
      p ok
    RUBY

    _(result).must_answer "nil\ntrue\n"
  end

  it "exception super message" do
    result = zr(<<~'RUBY')
      # A user Exception subclass with a custom initialize that forwards to super must
      # carry the resolved message when raised WITHOUT an explicit message argument.
      # `raise E` calls the custom initialize, so the message is the default or
      # super-built one, not the class name.

      # Bare `super` forwards the defaulted param.
      class E < StandardError
        def initialize(m = "def"); super; end
      end
      begin; raise E; rescue => e; p e.message; end          # "def"
      begin; raise E, "x"; rescue => e; p e.message; end      # "x"
      begin; raise E.new; rescue => e; p e.message; end       # "def"
      begin; raise E.new("y"); rescue => e; p e.message; end  # "y"

      # super("...") with interpolation, raised argless.
      class F < StandardError
        def initialize(m = "dd"); super("wrapped: #{m}"); end
      end
      begin; raise F; rescue => e; p e.message; end           # "wrapped: dd"

      # No custom initialize: message defaults to the class name (unchanged fast path).
      class G < StandardError; end
      begin; raise G; rescue => e; p e.message; end           # "G"

      # Inherited user initialize from a user parent.
      class Base < StandardError
        def initialize(m = "base-def"); super; end
      end
      class Sub < Base; end
      begin; raise Sub; rescue => e; p e.message; end          # "base-def"

      # Custom initialize that also sets an ivar, raised argless.
      class H < StandardError
        def initialize(m = "oops", code = 42); @code = code; super(m); end
      end
      begin; raise H; rescue => e; p e.message; end            # "oops"

      # Built-in raises are unaffected.
      begin; raise StandardError; rescue => e; p e.message; end  # "StandardError"
      begin; raise "boom"; rescue => e; p e.message; end         # "boom"
    RUBY

    _(result).must_answer <<~'OUT'
      "def"
      "x"
      "def"
      "y"
      "wrapped: dd"
      "G"
      "base-def"
      "oops"
      "StandardError"
      "boom"
    OUT
  end

  it "exception user subclass" do
    result = zr(<<~'RUBY')
      # User subclasses of built-in exception classes are real exceptions,
      # and their class is the subclass.
      class MyError < StandardError
        def initialize(msg = "default msg")
          super(msg)
        end
      end

      e = MyError.new("hello")
      puts e.message
      puts e.class

      e2 = MyError.new
      puts e2.message
      puts e2.class

      # is_a? walks the parent chain.
      puts e.is_a?(MyError)
      puts e.is_a?(StandardError)
      puts e.is_a?(RuntimeError)

      # raise + rescue with user subclass
      begin
        raise MyError, "raised"
      rescue MyError => caught
        puts "caught: #{caught.message}"
      end

      # rescue by parent matches subclass
      begin
        raise MyError, "via parent"
      rescue StandardError => parent_caught
        puts "parent caught: #{parent_caught.message}"
        puts "parent caught cls: #{parent_caught.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      MyError
      default msg
      MyError
      true
      true
      false
      caught: raised
      parent caught: via parent
      parent caught cls: MyError
    OUT
  end

  it "extending a non module raises type error" do
    result = zr(<<~'RUBY')
      begin
        Object.new.extend(42)
      rescue TypeError => e
        puts "TypeError"
      end
    RUBY

    _(result).must_answer "TypeError\n"
  end

  it "module superclass raises rubys own type error" do
    result = zr(<<~'RUBY')
      # Every built-in CLASS is subclassable (`zr_abi::NOT_PAYLOAD_ROOTS` is a
      # denylist of the shapes that are not payload wrappers, not an allowlist
      # of the ones that are). What is left is the two superclasses RUBY
      # refuses, and zr compiles each into ruby's own raise rather than a
      # compile error naming zr.

      begin
        class WantsModule < Comparable
        end
      rescue TypeError => e
        puts "module: #{e.message}"
      end
      begin
        class WantsClass < Class
        end
      rescue TypeError => e
        puts "class: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      module: superclass must be an instance of Class (given an instance of Module)
      class: can't make subclass of Class
    OUT
  end

  it "rescue builtin module include" do
    result = zr(<<~'RUBY')
      # `include IO::WaitReadable` -- a BUILTIN module named through its path -- was
      # dropped on the floor: the include recorder looked the name up in the class
      # table, found nothing (a builtin module has no user class), and skipped it
      # without a word. So `rescue IO::WaitReadable` fell through to the next arm
      # and `e.is_a?(IO::WaitReadable)` answered false, for an exception class that
      # said it included it.
      #
      # This is how a non-blocking read reports "would block" in CRuby:
      # OpenSSL::SSL::SSLErrorWaitReadable is a class including IO::WaitReadable,
      # not an SSLError extended at run time.
      module Plain
      end

      class ErrPlain < StandardError
        include Plain
      end

      class ErrWaitR < StandardError
        include IO::WaitReadable
      end

      class ErrWaitW < StandardError
        include IO::WaitWritable
      end

      # A user module already worked; the builtin one is what did not.
      begin
        raise ErrPlain, "a"
      rescue Plain => e
        puts "user module: #{e.class}"
      end

      begin
        raise ErrWaitR, "b"
      rescue IO::WaitReadable => e
        puts "builtin module: #{e.class}"
      rescue StandardError
        puts "WRONG: fell through"
      end

      # The two directions do not alias each other.
      begin
        raise ErrWaitW, "c"
      rescue IO::WaitReadable
        puts "WRONG arm"
      rescue IO::WaitWritable => e
        puts "other direction: #{e.class}"
      end

      p ErrWaitR.new("x").is_a?(IO::WaitReadable)
      p ErrWaitR.new("x").is_a?(IO::WaitWritable)
      p ErrWaitR.new("x").is_a?(StandardError)

      # An inherited include reaches the subclass too.
      class ErrChild < ErrWaitR
      end
      begin
        raise ErrChild, "d"
      rescue IO::WaitReadable => e
        puts "inherited: #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      user module: ErrPlain
      builtin module: ErrWaitR
      other direction: ErrWaitW
      true
      false
      true
      inherited: ErrChild
    OUT
  end

  it "rescue matches an included module" do
    result = zr(<<~'RUBY')
      module Alertable; end
      class AppError < StandardError
        include Alertable
      end
      begin
        raise AppError, "direct"
      rescue Alertable => e
        puts "alertable: #{e.message}"
      end
    RUBY

    _(result).must_answer "alertable: direct\n"
  end

  it "rescue var subclass method" do
    result = zr(<<~'RUBY')
      # A rescue arm binds its variable to the named exception subclass when that
      # class has state or behaviour of its own. Only ivars counted, so a subclass
      # whose body is a method was typed as the plain exception and the method could
      # not be called. A two-level chain missed on top of that: the parent links are
      # not resolved yet at that point, so the walk stopped at the subclass.
      class AErr < StandardError; end

      class BErr < AErr
        def code; 7; end
      end

      begin
        raise BErr
      rescue BErr => eb
        p eb.code
      end

      class CErr < StandardError
        def code; 9; end
        def label; "c"; end
      end

      begin
        raise CErr, "boom"
      rescue CErr => ec
        p ec.code
        p ec.label
        p ec.message
        p ec.class
      end

      # a subclass carrying ivars still specializes
      class DErr < StandardError
        def initialize(m, n)
          super(m)
          @n = n
        end
        def n; @n; end
      end

      begin
        raise DErr.new("m", 3)
      rescue DErr => ed
        p ed.n
        p ed.message
      end

      # a plain subclass keeps the exception face
      class EErr < StandardError; end
      begin
        raise EErr, "plain"
      rescue EErr => ee
        p ee.message
        p ee.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      7
      9
      "c"
      "boom"
      CErr
      3
      "m"
      "plain"
      EErr
    OUT
  end

  it "rescue walks class hierarchy" do
    result = zr(<<~'RUBY')
      # `rescue ParentClass => e` should catch a raised subclass
      # instance, and `e.is_a?(AncestorClass)` should walk the class
      # hierarchy. So a `raise C` where `C < B < A < StandardError` is
      # caught by `rescue B`, `rescue A` and `rescue StandardError`,
      # and `e.is_a?(X)` is true for each ancestor X.

      class A < StandardError; end
      class B < A; end
      class C < B; end

      # `rescue B` catches a raised C
      begin
        raise C, "boom"
      rescue B => e
        puts "caught B: " + e.message
      end

      # is_a? walks the chain
      begin
        raise C, "x"
      rescue => e
        puts "is_a A? " + (e.is_a?(A) ? "yes" : "no")
        puts "is_a B? " + (e.is_a?(B) ? "yes" : "no")
        puts "is_a C? " + (e.is_a?(C) ? "yes" : "no")
        puts "is_a StandardError? " + (e.is_a?(StandardError) ? "yes" : "no")
        puts "is_a String? " + (e.is_a?(String) ? "yes" : "no")
      end

      # Standard library exception hierarchy: ArgumentError < StandardError.
      # `rescue StandardError` should catch ArgumentError.
      begin
        raise ArgumentError, "bad"
      rescue StandardError => e
        puts "caught StandardError via ArgumentError: " + e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      caught B: boom
      is_a A? yes
      is_a B? yes
      is_a C? yes
      is_a StandardError? yes
      is_a String? no
      caught StandardError via ArgumentError: bad
    OUT
  end

  it "rescuing a middle class catches a raised leaf subclass" do
    result = zr(<<~'RUBY')
      class AppError < StandardError
      end
      class ValidationError < AppError
      end

      begin
        raise ValidationError, "bad input"
      rescue AppError => e
        puts "caught as AppError: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "caught as AppError: bad input\n"
  end

  it "runtime exception subclass" do
    result = zr(<<~'RUBY')
      # A class MINTED at runtime from an exception root is an exception like any
      # other: `.new` builds the native instance every inherited `Exception` method
      # reads, `raise` accepts it in all three of its shapes, and a `rescue` clause
      # matches it by ancestry.
      R = Class.new(StandardError)
      p R.ancestors.first(3)
      p R.new("hi").message
      p R.new.message
      p R.superclass

      # A body: an override, an addition, and a custom `initialize` that calls super.
      Coded = Class.new(StandardError) do
        attr_reader :code
        def initialize(code)
          @code = code
          super("code #{code}")
        end
        def to_s = "<#{@code}>"
      end
      e = Coded.new(42)
      p [e.code, e.message, e.to_s]

      # Deeper than one level, and off a root other than StandardError.
      Sub = Class.new(Coded)
      p Sub.new(7).message
      p Sub.ancestors.include?(StandardError)
      p Class.new(ArgumentError).new("a").is_a?(ArgumentError)
      p Class.new(Exception).new("x").is_a?(StandardError)

      def caught
        yield
      rescue => e
        [e.class.name, e.message]
      end
      p(caught { raise R })
      p(caught { raise R, "with message" })
      p(caught { raise R.new("prebuilt") })

      # Matching: by an ancestor, and by a sibling that misses.
      begin
        raise Sub, 3
      rescue Coded => e
        p [:by_parent, e.message, e.class == Sub]
      end

      begin
        begin
          raise R, "inner"
        rescue Coded
          p :wrong
        end
      rescue R => e
        p [:not_matched_by_sibling, e.message]
      end

      # An anonymous one carries the same surface.
      anon = Class.new(RuntimeError).new("nameless")
      p anon.class.ancestors.include?(RuntimeError)
      p anon.message
      p anon.backtrace

      err = R.new("surface")
      err.set_backtrace(["a.rb:1"])
      p err.backtrace
      p err.full_message(highlight: false, order: :top).lines.first.chomp
      p [err.cause, err.frozen?]
    RUBY

    _(result).must_answer <<~'OUT'
      [R, StandardError, Exception]
      "hi"
      "R"
      StandardError
      [42, "<42>", "<42>"]
      "<7>"
      true
      true
      false
      ["R", "R"]
      ["R", "with message"]
      ["R", "prebuilt"]
      [:by_parent, "<3>", true]
      [:not_matched_by_sibling, "inner"]
      true
      "nameless"
      nil
      ["a.rb:1"]
      "a.rb:1: surface (R)"
      [nil, false]
    OUT
  end

  it "super with no definition above raises at runtime" do
    result = zr(<<~'RUBY')
      # Real Ruby has no definition-time check for `super`: it resolves against
      # the receiver's live ancestry at CALL time and raises NoMethodError only
      # if that walk comes up empty (vm_search_super_method / vm_eval.c). So a
      # `super` with nothing above it must compile, and the raise must be
      # rescuable -- rejecting it at compile time would kill this whole program.

      class Rec
        def as_json
          h = super
          h[:x] = 1
          h
        end
      end
      begin
        Rec.new.as_json
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer "super: no superclass method 'as_json' for an instance of Rec\n"
  end

  it "user exception subclass class method constructs via runtime" do
    result = zr(<<~'RUBY')
      # A `def self.x` on an exception subclass can call a bare `new`. It makes an
      # instance of the subclass, with the message it gets.

      class D < StandardError
        def self.build(n)
          new("built-#{n}")
        end
      end
      e = D.build(3)
      puts e.message
      puts e.class
      puts e.is_a?(StandardError)
    RUBY

    _(result).must_answer <<~'OUT'
      built-3
      D
      true
    OUT
  end

  it "user exception subclass keyword initialize" do
    result = zr(<<~'RUBY')
      # An exception subclass whose `initialize` takes KEYWORD arguments (D3): the
      # runtime construction path (`construct_by_class_id`) must carry keywords as
      # the trailing-Hash the trampoline expects, or `code:` would default. Two
      # sibling subclasses -- neither's `message` param pinned to a String -- also
      # exercise the poly `super(message)` coercion into the native message slot.

      class AError < StandardError
        attr_reader :code
        def initialize(message, code: 3)
          super(message)
          @code = code
        end
      end
      class BError < StandardError
        attr_reader :level
        def initialize(message, level = 7)
          super(message)
          @level = level
        end
      end
      a = AError.new("boom", code: 9)
      puts a.code
      puts a.message
      b = BError.new("bad", 5)
      puts b.level
      puts b.message
      puts AError.new("d").code
    RUBY

    _(result).must_answer <<~'OUT'
      9
      boom
      5
      bad
      3
    OUT
  end

  it "user exception subclass super chain and inherited initialize" do
    result = zr(<<~'RUBY')
      # A user exception subclass with NO `initialize` inherits the native default:
      # `Plain.new(msg)` stores the message in the hidden slot, so `#message`
      # returns it and `instance_variables` is empty. Multi-level `super` chains
      # (`B < A < StandardError`, bare `super` forwarding) also resolve natively.

      class Plain < RuntimeError
      end
      p1 = Plain.new("hi")
      puts p1.message
      p p1.instance_variables

      class A < StandardError
        def initialize(msg = "a-default")
          super
        end
      end
      class B < A
        def initialize
          super()
          @tag = "b"
        end
        def tag; @tag; end
      end
      b = B.new
      puts b.message
      puts b.tag
      puts b.is_a?(A)

      class Done < StopIteration
      end
      puts Done.new("stop").message
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      []
      a-default
      b
      true
      stop
    OUT
  end

  it "user exception subclass uses native representation" do
    result = zr(<<~'RUBY')
      # A USER exception subclass is backed by the native `RubyException` (D3): a
      # custom ivar, `super` into the native `initialize` (which stores the message
      # in its hidden slot), and reflection all match CRuby -- `instance_variables`
      # is `[:@code]` only (NOT `@message`), and `@message` reads nil while
      # `#message` returns the super-provided text.

      class MyErr < StandardError
        def initialize(code)
          @code = code
          super("boom #{code}")
        end
        def code
          @code
        end
      end

      e = MyErr.new(42)
      puts e.message
      puts e.code
      puts e.is_a?(StandardError)
      p e.instance_variables
      p e.instance_variable_get(:@message)
      p e.instance_variable_get(:@code)
      begin
        raise MyErr, "direct"
      rescue StandardError => ex
        puts "#{ex.class}: #{ex.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      boom 42
      42
      true
      [:@code]
      nil
      42
      MyErr: boom direct
    OUT
  end
end
