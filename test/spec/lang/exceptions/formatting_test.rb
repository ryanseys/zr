# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: formatting and inspection" do
  it "basicobject blank slate" do
    result = zr(<<~'RUBY')
      # A BasicObject subclass is a blank slate: it answers only
      # BasicObject's own methods (==, equal?, instance_eval, ...) and what the user
      # defined; the Object/Kernel surface raises NoMethodError.
      class BO < BasicObject
        def greet; "hi"; end
      end
      a = BO.new
      r = (a.class rescue $!.class)
      p r
      p a.greet
      r2 = (a.inspect rescue "no-inspect")
      p r2
      r3 = (a.respond_to?(:greet) rescue "no-respond_to")
      p r3
      p(a == a)
      b = BO.new
      p(a == b)
      p(a.equal?(a))
      class Normal; end
      p Normal.new.class
    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
      "hi"
      "no-inspect"
      "no-respond_to"
      true
      false
      true
      Normal
    OUT
  end

  it "begin else value" do
    result = zr(<<~'RUBY')
      # The value of `begin ... rescue ... else ... end`: the else clause's on
      # success (including an empty else), the rescue arm's on an exception, in
      # expression and method-tail position and inside a block. CRuby generated
      # the expectations.
      a = begin; :body; rescue; :r; else; false; end
      p a
      b = begin; :body; rescue; :r; else; 3; end
      p b
      c = begin; 1; rescue; 2; else; nil; end
      p c
      d = begin; 1; rescue; 2; else; 42; end
      p d
      e = begin; "s"; rescue; "r"; else; "e"; end
      p e
      f = begin; raise "x"; rescue; :r; else; :e; end
      p f
      def g; begin; 1; rescue; 2; else; false; end; end
      p g
      h = begin; 1; rescue; 2; else; 7; ensure; 99; end
      p h
      i = begin; :body; rescue; :r; end
      p i
      def j(n)
        begin
          Integer(n)
        rescue ArgumentError
          :bad
        else
          [n, true]
        end
      end
      p j("1")
      p j("x")
      k = [1, 2].map { |v| begin; v; rescue; 0; else; v.to_s; end }
      p k
      m = begin; 1; rescue; 2; else; end
      p m
      def n; begin; :x; rescue; :r; else; end; end
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      false
      3
      nil
      42
      "e"
      :r
      false
      7
      :body
      ["1", true]
      :bad
      ["1", "2"]
      nil
      nil
    OUT
  end

  it "call arg valueless" do
    result = zr(<<~'RUBY')
      # An argument with no value -- an unresolved call, which lowers to a raise --
      # sitting in a non-final position beside another side-effecting argument. The
      # argument-sequencing pass has nothing to sequence it into: a valueless
      # expression has no C storage, and it does not return, so no sibling can
      # observe it. Left to the argument slot, it coerces to the parameter's type.

      def join(a, b)
        a.to_s + b
      end

      key = "sid"
      begin
        puts join(nil.missing_method, "cookie." + key)
      rescue NoMethodError
        puts "raised"
      end
    RUBY

    _(result).must_answer "raised\n"
  end

  it "case when qualified exception" do
    result = zr(<<~'RUBY')
      # An exception carries its fully qualified Ruby name at run time, but a
      # `when Mod::Klass` pattern node holds only the last segment. Comparing that
      # directly never matched, so the branch was silently skipped -- the case fell
      # through to no arm at all rather than mismatching visibly.
      module App
        class HelpRequested < RuntimeError; end
        class BadUsage < App::HelpRequested; end
        class Unrelated < RuntimeError; end
      end

      def classify(e)
        case e
        when App::BadUsage then "usage"
        when App::HelpRequested then "help"
        when App::Unrelated then "other"
        else "none"
        end
      end

      begin; raise App::HelpRequested; rescue => e; puts classify(e); end
      begin; raise App::BadUsage;      rescue => e; puts classify(e); end
      begin; raise App::Unrelated;     rescue => e; puts classify(e); end
      begin; raise RuntimeError;       rescue => e; puts classify(e); end

      # the subclass still matches its qualified ancestor
      begin
        raise App::BadUsage
      rescue App::HelpRequested => e
        puts e.is_a?(App::HelpRequested)
        puts e.class.to_s
      end

      # a case directly on the rescue-captured variable (the reported shape)
      $events = []
      begin
        raise App::HelpRequested
      rescue App::HelpRequested => e
        case e
        when App::HelpRequested then $events << "help"
        end
      end
      p $events
    RUBY

    _(result).must_answer <<~'OUT'
      help
      usage
      other
      none
      true
      App::BadUsage
      ["help"]
    OUT
  end

  it "current exception" do
    result = zr(<<~'RUBY')
      # `$!` is the exception currently being handled -- inside any rescue,
      # including the one-line modifier form, it refers to the caught exception,
      # and is nil outside a rescue.
      p $!                                    # nil (nothing being handled)

      result = Integer("not a number") rescue $!.class
      p result                                # ArgumentError

      begin
        raise TypeError, "bad value"
      rescue
        puts "handling: #{$!.message}"        # handling: bad value
        puts "class: #{$!.class}"             # class: TypeError
      end

      p $!                                    # nil again (handling finished)

      # Exception#inspect renders "#<ClassName: message>", or just the class name
      # when the message is empty.
      p RuntimeError.new("boom").inspect      # "#<RuntimeError: boom>"
      p ArgumentError.new("").inspect         # "ArgumentError"
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      ArgumentError
      handling: bad value
      class: TypeError
      nil
      "#<RuntimeError: boom>"
      "ArgumentError"
    OUT
  end

  it "definition hook defaults" do
    result = zr(<<~'RUBY')
      # Ruby tells a class what was just defined in it, through eight private hooks.
      # This file covers only their DEFAULTS -- that they exist, that they are
      # private, that `super` reaches them, and that the three mix-in primitives
      # really do the mixing. What CALLS them is covered elsewhere.

      p Module.private_instance_methods(false).grep(/features|extend_object|added|removed|undefined/).sort
      p BasicObject.private_instance_methods(false).sort
      p [Module.private_method_defined?(:prepend_features), Module.method_defined?(:prepend_features)]
      p Module.instance_method(:const_added).arity

      # Private means private: an explicit receiver is refused.
      begin
        Comparable.prepend_features(Class.new)
      rescue NoMethodError => e
        puts "explicit: #{e.message}"
      end

      # The defaults answer nil and take exactly one argument.
      class Probe
        def self.reach(hook, arg) = send(hook, arg)
      end
      %i[method_added method_removed method_undefined const_added].each do |hook|
        puts "#{hook} -> #{Probe.reach(hook, :x).inspect}"
      end
      %i[singleton_method_added singleton_method_removed singleton_method_undefined].each do |hook|
        puts "#{hook} -> #{Object.new.send(hook, :x).inspect}"
      end

      # `prepend_features`/`append_features`/`extend_object` are the primitives that
      # perform the mixin -- not notifications. Called directly, they mix in.
      m = Module.new { def hi = "hi from M" }
      k = Class.new
      m.send(:prepend_features, k)
      p [k.ancestors.include?(m), k.new.hi]

      n = Module.new { def yo = "yo from N" }
      k2 = Class.new
      n.send(:append_features, k2)
      p [k2.ancestors.include?(n), k2.new.yo]

      o = Object.new
      Module.new { def ext = "extended" }.send(:extend_object, o)
      p o.ext

      # An override reaches the default through `super`, which is the whole reason
      # the defaults exist.
      class Sub
        def self.method_added(name)
          puts "Sub saw #{name.inspect}, super -> #{super.inspect}"
        end
      end
      p Sub.send(:method_added, :manual)
    RUBY

    _(result).must_answer <<~'OUT'
      [:append_features, :const_added, :extend_object, :method_added, :method_removed, :method_undefined, :prepend_features]
      [:initialize, :method_missing, :singleton_method_added, :singleton_method_removed, :singleton_method_undefined]
      [true, false]
      1
      explicit: private method 'prepend_features' called for module Comparable
      method_added -> nil
      method_removed -> nil
      method_undefined -> nil
      const_added -> nil
      singleton_method_added -> nil
      singleton_method_removed -> nil
      singleton_method_undefined -> nil
      [true, "hi from M"]
      [true, "yo from N"]
      "extended"
      Sub saw :manual, super -> nil
      nil
    OUT
  end

  it "diverging receiver still compiles" do
    result = zr(<<~'RUBY')
      # A receiver can DIVERGE -- `raise("x").foo`, or a `const_get` whose literal
      # name folds at compile time to a NameError. Such an expression has no value
      # type at all, and a dynamic send wants a receiver to borrow. So the whole
      # program failed to compile over an expression that never runs.
      begin
        Object.const_get("Bad.Name")
      rescue NameError => e
        p [e.class, e.message]
      end

      begin
        Object.const_get("Bad Name").to_s
      rescue NameError => e
        p [e.class, e.message, e.name.to_sym, e.receiver.to_s]
      end

      begin
        p Object.const_get("bad").anything
      rescue NameError => e
        p e.message
      end

      begin
        raise("boom").foo
      rescue RuntimeError => e
        p [e.class, e.message]
      end

      begin
        p [Object.const_get("1A")]
      rescue NameError => e
        p e.message
      end

      # The value positions that already worked, kept honest.
      begin
        p({ a: (raise "in a hash") })
      rescue RuntimeError => e
        p e.message
      end

      begin
        x = Object.const_get("also bad")
        p x
      rescue NameError => e
        p e.message
      end

      # A well-formed name still folds to the real answer.
      p Object.const_get("String")
      p Object.const_get(:Integer).name
    RUBY

    _(result).must_answer <<~'OUT'
      [NameError, "wrong constant name Bad.Name"]
      [NameError, "wrong constant name Bad Name", :"Bad Name", "Object"]
      "wrong constant name bad"
      [RuntimeError, "boom"]
      "wrong constant name 1A"
      "in a hash"
      "wrong constant name also bad"
      String
      "Integer"
    OUT
  end

  it "env dup clone freeze raise type error" do
    result = zr(<<~'RUBY')
      # ENV overrides Kernel#dup/#clone/#freeze to raise (copy it via ENV.to_h).
      # These must route through dispatch, not the universal value fast paths,
      # which would silently shallow-copy/freeze the singleton instead.

      ENV['ZZ_E2E'] = '1'
      p (ENV.dup rescue $!.message)
      p (ENV.clone rescue $!.message)
      p (ENV.freeze rescue $!.message)
      p ENV['ZZ_E2E']
      p ENV.store('ZZ_E2E2', '3')
      p ENV.delete('ZZ_E2E2')
      p ENV.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "Cannot dup ENV, use ENV.to_h to get a copy of ENV as a hash"
      "Cannot clone ENV, use ENV.to_h to get a copy of ENV as a hash"
      "cannot freeze ENV"
      "1"
      "3"
      "3"
      "ENV"
    OUT
  end

  it "error protocol edges" do
    result = zr(<<~'RUBY')
      # CRuby error-protocol edges:
      # - float modulo by zero raises ZeroDivisionError (int or float divisor);
      #   the divisor-sign result rule is preserved for nonzero divisors
      # - Array#first(n)/#last(n) with a negative count raise ArgumentError
      # - a rescue binding inside a yield-inlined method body resolves (the
      #   assignment used the unrenamed local and did not compile)
      def t
        yield
      rescue => e
        e.class.to_s
      end
      p t { 5.0 % 0 }
      p t { 5.0 % 0.0 }
      p t { -5.5 % 2 }
      p t { [1, 2, 3].first(-1) }
      p t { [1, 2, 3].last(-2) }
      p t { [1.0, 2.0].first(-1) }
      p t { [1, 2, 3].first(2) }
      p t { [1, 2, 3].last(2) }
      p t { 5 % 0 }
    RUBY

    _(result).must_answer <<~'OUT'
      "ZeroDivisionError"
      "ZeroDivisionError"
      0.5
      "ArgumentError"
      "ArgumentError"
      "ArgumentError"
      [1, 2]
      [2, 3]
      "ZeroDivisionError"
    OUT
  end

  it "exception cause ensure reraise" do
    result = zr(<<~'RUBY')
      r001 = (begin
        begin
          raise ArgumentError, "orig"
        ensure
          raise TypeError, "in-ensure"
        end
      rescue => e001
        [e001.class.to_s, e001.cause.class.to_s]
      end); p r001

      r002 = (begin
        begin
          begin; raise ArgumentError, "a"; rescue; raise TypeError, "b"; end
        rescue
          raise
        end
      rescue => e002
        [e002.class.to_s, e002.cause.class.to_s]
      end); p r002
      r3 = (begin; begin; raise "x"; rescue => e; raise ArgumentError, "y"; end; rescue => f; [f.class.to_s, f.cause.class.to_s]; end); p r3
      r4 = (begin; raise "z"; rescue => g; g.cause.inspect; end); p r4
    RUBY

    _(result).must_answer <<~'OUT'
      ["TypeError", "ArgumentError"]
      ["TypeError", "ArgumentError"]
      ["ArgumentError", "RuntimeError"]
      "nil"
    OUT
  end

  it "exception empty message" do
    result = zr(<<~'RUBY')
      r001 = (begin; raise; rescue RuntimeError => e001; [e001.class.to_s, e001.message]; end); p r001
      p RuntimeError.new.message
      r2 = (begin; raise "x"; rescue => e; e.message; end); p r2
      r3 = (begin; raise RuntimeError; rescue => e; e.message; end); p r3
      r4 = (begin; raise ArgumentError, ""; rescue => e; e.message; end); p r4
    RUBY

    _(result).must_answer <<~'OUT'
      ["RuntimeError", ""]
      "RuntimeError"
      "x"
      "RuntimeError"
      ""
    OUT
  end

  it "exception full message without backtrace" do
    result = zr(<<~'RUBY')
      # `full_message` renders through CRuby's `rb_error_write0`: the head line, the
      # `from` trail, then the cause chain. An exception carrying NO backtrace hangs
      # the head off the CALLER's own position under the reporting method's name,
      # which is why the first line below names `full_message`.
      e = StandardError.new("msg")
      p e.backtrace
      p e.full_message(highlight: false, order: :top)

      # An empty message prints the class alone -- `unhandled exception` for a bare
      # RuntimeError, which is what an argumentless `raise` builds.
      p RuntimeError.new("").full_message(highlight: false)
      p StandardError.new("").full_message(highlight: false)
      p StandardError.new("").detailed_message(highlight: false)
      p RuntimeError.new("").detailed_message(highlight: true)

      # `order:` picks the direction. `:bottom` numbers the trail, right-aligned to
      # the widest index, under the Traceback banner.
      b = StandardError.new("msg")
      b.set_backtrace(["a.rb:1:in 'x'", "b.rb:2:in 'y'", "c.rb:3:in 'z'"])
      p b.full_message(highlight: false, order: :top)
      p b.full_message(highlight: false, order: :bottom)
      p b.full_message(highlight: true, order: :top)
      p b.full_message(highlight: true, order: :bottom)
      wide = StandardError.new("m")
      wide.set_backtrace((1..12).map { |i| "f#{i}.rb:#{i}:in 'g'" })
      puts wide.full_message(highlight: false, order: :bottom)

      # Both keywords refuse anything else, in CRuby's own words.
      begin; b.full_message(order: :sideways); rescue => x; p [x.class, x.message]; end
      begin; b.full_message(highlight: 3); rescue => x; p [x.class, x.message]; end

      # `detailed_message` is SENT, not computed -- an override changes every report.
      class Custom < StandardError
        def detailed_message(**opt) = "CUSTOM(#{opt[:highlight]})"
      end
      c = Custom.new("m")
      c.set_backtrace(["a.rb:1:in 'x'"])
      p c.full_message(highlight: false)
      p c.full_message(highlight: true)

      # A multi-line message keeps the class tag on its first line.
      class Wide < StandardError
        def to_s = "line one\nline two"
      end
      w = Wide.new
      w.set_backtrace(["a.rb:1:in 'x'"])
      p w.full_message(highlight: false)
      p w.full_message(highlight: true)

      # The cause chain renders after the exception it caused (before it, reversed).
      begin
        begin
          raise "inner"
        rescue
          raise "outer"
        end
      rescue => chained
        p chained.full_message(highlight: false, order: :top)
        p chained.full_message(highlight: false, order: :bottom)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "lang/exceptions/formatting_test.rb:7:in 'full_message': msg (StandardError)\n"
      "lang/exceptions/formatting_test.rb:11:in 'full_message': unhandled exception\n"
      "lang/exceptions/formatting_test.rb:12:in 'full_message': StandardError\n"
      "StandardError"
      "\e[1;4munhandled exception\e[m"
      "a.rb:1:in 'x': msg (StandardError)\n\tfrom b.rb:2:in 'y'\n\tfrom c.rb:3:in 'z'\n"
      "Traceback (most recent call last):\n\t2: from c.rb:3:in 'z'\n\t1: from b.rb:2:in 'y'\na.rb:1:in 'x': msg (StandardError)\n"
      "a.rb:1:in 'x': \e[1mmsg (\e[1;4mStandardError\e[m\e[1m)\e[m\n\tfrom b.rb:2:in 'y'\n\tfrom c.rb:3:in 'z'\n"
      "\e[1mTraceback\e[m (most recent call last):\n\t2: from c.rb:3:in 'z'\n\t1: from b.rb:2:in 'y'\na.rb:1:in 'x': \e[1mmsg (\e[1;4mStandardError\e[m\e[1m)\e[m\n"
      Traceback (most recent call last):
      	11: from f12.rb:12:in 'g'
      	10: from f11.rb:11:in 'g'
      	 9: from f10.rb:10:in 'g'
      	 8: from f9.rb:9:in 'g'
      	 7: from f8.rb:8:in 'g'
      	 6: from f7.rb:7:in 'g'
      	 5: from f6.rb:6:in 'g'
      	 4: from f5.rb:5:in 'g'
      	 3: from f4.rb:4:in 'g'
      	 2: from f3.rb:3:in 'g'
      	 1: from f2.rb:2:in 'g'
      f1.rb:1:in 'g': m (StandardError)
      [ArgumentError, "expected :top or :bottom as order: :sideways"]
      [ArgumentError, "expected true or false as highlight: 3"]
      "a.rb:1:in 'x': CUSTOM(false)\n"
      "a.rb:1:in 'x': CUSTOM(true)\n"
      "a.rb:1:in 'x': line one (Wide)\nline two\n"
      "a.rb:1:in 'x': \e[1mline one (\e[1;4mWide\e[m\e[1m)\e[m\n\e[1mline two\e[m\n"
      "lang/exceptions/formatting_test.rb:55:in '<main>': outer (RuntimeError)\nlang/exceptions/formatting_test.rb:53:in '<main>': inner (RuntimeError)\n"
      "Traceback (most recent call last):\nlang/exceptions/formatting_test.rb:53:in '<main>': inner (RuntimeError)\nlang/exceptions/formatting_test.rb:55:in '<main>': outer (RuntimeError)\n"
    OUT
  end

  it "exception inspect" do
    result = zr(<<~'RUBY')
      class SubIns < StandardError; end
      p(SubIns.new("m").inspect)
      i = SubIns.new("m").inspect
      p i
      p(RuntimeError.new("m").inspect)
      p(StandardError.new.inspect)
      p(SubIns.new.inspect)
      begin
        raise SubIns, "z"
      rescue => e
        p e.inspect
      end
      p [RuntimeError.new("boxed")].first.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "#<SubIns: m>"
      "#<SubIns: m>"
      "#<RuntimeError: m>"
      "#<StandardError: StandardError>"
      "#<SubIns: SubIns>"
      "#<SubIns: z>"
      "#<RuntimeError: boxed>"
    OUT
  end

  it "exception inspect empty message" do
    result = zr(<<~'RUBY')
      class SubIns < StandardError; end
      p(SubIns.new("m").inspect)
      i001 = SubIns.new("m").inspect; p i001
      p(RuntimeError.new("").inspect)
      i002 = RuntimeError.new("").inspect; p i002
      p(RuntimeError.new("q").inspect)
      p RuntimeError.new.message
      p RuntimeError.new("").message
      p SubIns.new("").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "#<SubIns: m>"
      "#<SubIns: m>"
      "RuntimeError"
      "RuntimeError"
      "#<RuntimeError: q>"
      "RuntimeError"
      ""
      "SubIns"
    OUT
  end

  it "exception message override" do
    result = zr(<<~'RUBY')
      # A user exception's #message / #to_s override must drive the reported message.
      # Ruby's Exception#message calls #to_s, so overriding either changes #message,
      # while overriding only #message leaves #to_s at the default (the class name).

      class MsgOnly < StandardError
        def message = "msg-only"
      end

      class TosOnly < StandardError
        def to_s = "tos-only"
      end

      class Both < StandardError
        def message = "the-message"
        def to_s = "the-to-s"
      end

      class WithIvar < StandardError
        def initialize(n)
          @n = n
          super("stored")
        end
        def message = "n=#{@n}"
      end

      class Plain < StandardError
      end

      def show(e)
        puts "message=#{e.message} to_s=#{e.to_s}"
      end

      begin; raise MsgOnly; rescue => e; show(e); end
      begin; raise TosOnly; rescue => e; show(e); end
      begin; raise Both; rescue => e; show(e); end
      begin; raise Both, "ignored-arg"; rescue => e; show(e); end
      begin; raise WithIvar.new(7); rescue => e; show(e); end
      begin; raise Plain, "explicit"; rescue => e; show(e); end
      begin; raise Plain; rescue => e; show(e); end

      # specialized rescue (statically-typed binding) hits the override too
      begin; raise Both; rescue Both => e; show(e); end
    RUBY

    _(result).must_answer <<~'OUT'
      message=msg-only to_s=MsgOnly
      message=tos-only to_s=tos-only
      message=the-message to_s=the-to-s
      message=the-message to_s=the-to-s
      message=n=7 to_s=stored
      message=explicit to_s=explicit
      message=Plain to_s=Plain
      message=the-message to_s=the-to-s
    OUT
  end

  it "exception new nil message" do
    result = zr(<<~'RUBY')
      # `Exception.new(nil)`: nil is not a message, so the class name answers, the
      # way the no-argument form does; an empty String is a message.
      p RuntimeError.new(nil).message
      p KeyError.new(nil).message
      p StandardError.new(nil).to_s
      p RuntimeError.new("").message
      p RuntimeError.new.message
      p RuntimeError.new("real").message
      class MyErr < StandardError; end
      p MyErr.new(nil).message
      p MyErr.new("m").message
      begin
        raise RuntimeError, nil
      rescue => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "RuntimeError"
      "KeyError"
      "StandardError"
      ""
      "RuntimeError"
      "real"
      "MyErr"
      "m"
      "RuntimeError"
    OUT
  end

  it "exception nonstring message" do
    result = zr(<<~'RUBY')
      class TS < StandardError
        def to_s; :sym; end
      end
      p(TS.new.message)

      r001 = (raise TS rescue $!.message); p r001   # => :sym

      p(TS.new.to_s)   # => :sym

      class TI < StandardError
        def to_s; 42; end
      end
      r = (raise TI rescue $!.message); p r
      r = (raise TI rescue $!.to_s); p r
      r = (raise "plain" rescue $!.message); p r
      class TM < StandardError
        def message; :mm; end
      end
      r = (raise TM rescue $!.message); p r
    RUBY

    _(result).must_answer <<~'OUT'
      :sym
      :sym
      :sym
      42
      42
      "plain"
      :mm
    OUT
  end

  it "exception nonstring to s" do
    result = zr(<<~'RUBY')
      class TS < StandardError
        def to_s; :sym; end
      end
      p(TS.new.message)
      class TS2 < StandardError
        def to_s; "text"; end
      end
      p(TS2.new.message)
      p(StandardError.new("plain").message)
    RUBY

    _(result).must_answer <<~'OUT'
      :sym
      "text"
      "plain"
    OUT
  end

  it "exception object methods" do
    result = zr(<<~'RUBY')
      # Exception variable methods bound by `rescue => e`:
      # .message returns the message string
      # .class returns the class name string
      # .to_s returns the message
      # .inspect returns "#<ClassName: message>"
      # Bare raise re-raises the original class+message rather than
      # fabricating a fresh RuntimeError.

      # .message
      begin
        raise "boom"
      rescue => e
        puts "msg: #{e.message}"
      end

      # .class on default raise (RuntimeError)
      begin
        raise "boom2"
      rescue => e
        puts "cls: #{e.class}"
      end

      # .class with explicit class
      begin
        raise ArgumentError, "bad"
      rescue => e
        puts "cls2: #{e.class}"
        puts "msg2: #{e.message}"
      end

      # .to_s and .inspect
      begin
        raise TypeError, "wrong"
      rescue => e
        puts "tos: #{e.to_s}"
        puts "ins: #{e.inspect}"
      end

      # Bare `raise` inside a rescue body re-raises with original class+msg.
      begin
        begin
          raise ArgumentError, "inner"
        rescue => e
          raise
        end
      rescue => e
        puts "re-raised cls: #{e.class}"
        puts "re-raised msg: #{e.message}"
      end

      # Backward-compat: `puts e` still prints the message string,
      # preserving the existing test/rescue.rb shape.
      begin
        raise "compat-msg"
      rescue => e
        puts e
      end

      # Propagation when no rescue type matches: the exception goes on to an
      # enclosing handler.
      begin
        begin
          raise ArgumentError, "propagate"
        rescue TypeError => e
          puts "should not be caught here"
        end
      rescue ArgumentError => e
        puts "caught propagated: #{e.class}"
        puts "msg: #{e.message}"
      end

      # .backtrace carries the real stamped frames (non-empty after a raise).
      begin
        raise "trace"
      rescue => e
        puts "backtrace is empty: #{e.backtrace.empty?}"
      end

      # .full_message renders the uncaught-report shape from the stamped frames;
      # path-portable via the frame suffix.
      begin
        raise ArgumentError, "fm"
      rescue => e
        puts "full: #{e.full_message(highlight: false).lines.first.chomp.end_with?("in '<main>': fm (ArgumentError)")}"
      end

      # Multi-clause rescue chain: first clause misses, second clause catches.
      begin
        raise TypeError, "multi"
      rescue ArgumentError => e
        puts "should not match"
      rescue TypeError => e
        puts "second clause: #{e.class} #{e.message}"
      rescue StandardError => e
        puts "should not reach"
      end

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      msg: boom
      cls: RuntimeError
      cls2: ArgumentError
      msg2: bad
      tos: wrong
      ins: #<TypeError: wrong>
      re-raised cls: ArgumentError
      re-raised msg: inner
      compat-msg
      caught propagated: ArgumentError
      msg: propagate
      backtrace is empty: false
      full: true
      second clause: TypeError multi
      done
    OUT
  end

  it "exception own to s" do
    result = zr(<<~'RUBY')
      # An exception subclass that defines its own to_s answers whatever that method
      # answers -- a Symbol, say. The call went through the message helper instead,
      # whose result is a string, and the Symbol came back empty.
      class TS < StandardError
        def to_s; :sym; end
      end
      p(TS.new.to_s)

      class TT < StandardError
        def to_s; "custom"; end
      end
      p(TT.new.to_s)
      begin
        raise TT
      rescue => e
        p e.to_s
      end

      class TU < StandardError; end
      p(TU.new("m").message)
      p(TU.new("m").to_s)
      p(TU.new.message)
    RUBY

    _(result).must_answer <<~'OUT'
      :sym
      "custom"
      "custom"
      "m"
      "m"
      "TU"
    OUT
  end

  it "exception real objects" do
    result = zr(<<~'RUBY')
      # An exception is a real object: $! and `rescue => e` bind the same object, its
      # #class is a real Class (usable in ==, case, printing), and `p` inspects it.

      # $! is the actual rescued object (identity), and its class/message read through
      begin
        raise "boom"
      rescue => e
        p $!.equal?(e)              # true
        p $!.class                  # RuntimeError
        p $!.class == RuntimeError  # true
        p $!.message                # "boom"
        p $!                        # #<RuntimeError: boom>
      end

      # outside any rescue, $! is nil
      p $!                          # nil

      # a typed exception class flows through == and drives a case
      begin
        raise ArgumentError, "bad arg"
      rescue => e
        p e.class                   # ArgumentError
        p e.class == ArgumentError  # true
        label = case e.class.to_s
                when "ArgumentError" then "arg"
                else "other"
                end
        p label                     # "arg"
      end

      # nested rescue: $! is the innermost handled exception and is identical to its
      # `=> e` binding
      begin
        raise TypeError, "outer"
      rescue => outer
        p outer.class               # TypeError
        begin
          raise IndexError, "inner"
        rescue => inner
          p $!.class                # IndexError
          p $!.equal?(inner)        # true
        end
      end

      # a user exception subclass keeps its class and custom message through => e
      class MyErr < StandardError
        def initialize(code)
          super("code #{code}")
        end
      end
      begin
        raise MyErr.new(42)
      rescue => e
        p e.class                   # MyErr
        p e.message                 # "code 42"
        p $!.equal?(e)              # true
      end

      # a nil $! (outside any rescue) reports NilClass; equal? against a non-exception
      # value is always false, since neither can be the one raised object
      p $!.class                    # NilClass
      begin
        raise "again"
      rescue => e
        p e.equal?(42)              # false
        p e.equal?("again")         # false
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      RuntimeError
      true
      "boom"
      #<RuntimeError: boom>
      nil
      ArgumentError
      true
      "arg"
      TypeError
      IndexError
      true
      MyErr
      "code 42"
      true
      NilClass
      false
      false
    OUT
  end

  it "isa namespaced exception collision" do
    result = zr(<<~'RUBY')
      # `is_a?` against a namespaced exception class answers true, also when
      # another module holds a class of the same leaf name. is_a?, kind_of? and
      # instance_of? agree with `rescue` and #ancestors. The shape comes from
      # net/http, where Timeout::Error sits beside URI::Error.
      module A
        class Error < StandardError; end
        class Sub < Error; end
      end

      module B
        class Error < RuntimeError; end
        class Sub < Error; end
      end

      a = A::Sub.new("x")
      b = B::Sub.new("x")

      # Each answers its own namespace's parent...
      p a.is_a?(A::Error)
      p b.is_a?(B::Error)
      # ...and not the other one's, which shares the leaf name.
      p a.is_a?(B::Error)
      p b.is_a?(A::Error)

      # The builtin grandparents still answer, and they differ between the two.
      p a.is_a?(StandardError)
      p b.is_a?(RuntimeError)
      p a.is_a?(RuntimeError)

      # instance_of? goes through the same name, and is exact.
      p a.instance_of?(A::Sub)
      p a.instance_of?(A::Error)

      # ancestors was never wrong; pinned so the two cannot drift apart.
      p A::Sub.ancestors.take(3).map(&:to_s)
      p B::Sub.ancestors.take(3).map(&:to_s)

      # rescue was never wrong either.
      begin
        raise A::Sub, "boom"
      rescue B::Error
        puts "WRONG namespace"
      rescue A::Error => e
        puts "rescued: #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      true
      true
      false
      true
      false
      ["A::Sub", "A::Error", "StandardError"]
      ["B::Sub", "B::Error", "RuntimeError"]
      rescued: A::Sub
    OUT
  end

  it "modifier rescue standard error" do
    result = zr(<<~'RUBY')
      # A modifier rescue catches StandardError and its descendants only, the way the
      # full begin/rescue form does. This arm caught everything, so a subclass of
      # Exception was swallowed.
      class NotStd < Exception; end
      class Std < StandardError; end

      p((raise(Std, "s") rescue "caught-std"))
      p((raise("plain") rescue "caught-runtime"))
      p((raise(ArgumentError, "a") rescue "caught-arg"))

      # a non-StandardError passes straight through the modifier rescue
      r = begin
        (raise(NotStd, "x") rescue "should-not-catch")
      rescue Exception => e
        [e.class.to_s, e.message]
      end
      p r

      # and an explicit rescue of it still catches
      s = begin
        raise NotStd, "y"
      rescue NotStd => e2
        e2.message
      end
      p s
    RUBY

    _(result).must_answer <<~'OUT'
      "caught-std"
      "caught-runtime"
      "caught-arg"
      ["NotStd", "x"]
      "y"
    OUT
  end

  it "native exception reopen adds and overrides" do
    result = zr(<<~'RUBY')
      # Reopening a NATIVE exception class (D3): a reopen `def` ADDS a method that
      # reaches every subclass, and OVERRIDES an existing native method everywhere.
      # The native message lives in a hidden slot, so a reopened `message` reading
      # `@message` sees nil (CRuby parity) -- here it reads `to_s`.

      class StandardError
        def code
          42
        end
      end
      class Exception
        def message
          "patched: " + to_s
        end
      end
      begin
        raise ArgumentError, "bad value"
      rescue => e
        puts e.code
        puts e.message
        puts e.is_a?(StandardError)
      end
      begin
        raise "plain"
      rescue => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      42
      patched: bad value
      true
      patched: plain
    OUT
  end

  it "nomethod scalar slot" do
    result = zr(<<~'RUBY')
      # A call to a method that the receiver does not have, in a position that
      # expects a scalar value. The call raises NoMethodError at runtime, as in
      # CRuby.
      class CommentRow
        def created_at; "2020-01-01"; end
      end
      class StoryRow
        def created_at; "2021-02-02"; end
      end
      class Wrap
        def initialize(note); @note = note; end
        def render
          s = @note.created_at.strftime("%Y")
          s.to_s
        end
      end
      begin
        puts Wrap.new(CommentRow.new).render
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer "NoMethodError\n"
  end

  it "raise with a bare class runs the classs own initialize" do
    result = zr(<<~'RUBY')
      # `raise E` must CONSTRUCT via `E.new` -- running defaults and `super`
      # -- rather than short-cutting the message to the class name. The
      # class-name default lives in the prelude's `Exception#to_s`.

      class E < StandardError
        def initialize(m = "def")
          super
        end
      end
      class F < StandardError
        def initialize(m = "dd")
          super("wrapped: #{m}")
        end
      end
      class G < StandardError; end

      begin; raise E; rescue => e; p e.message; end
      begin; raise E, "x"; rescue => e; p e.message; end
      begin; raise E.new; rescue => e; p e.message; end
      begin; raise F; rescue => e; p e.message; end
      begin; raise G; rescue => e; p e.message; end
      begin; raise StandardError; rescue => e; p e.message; end
    RUBY

    _(result).must_answer <<~'OUT'
      "def"
      "x"
      "def"
      "wrapped: dd"
      "G"
      "StandardError"
    OUT
  end

  it "rescue operand validation" do
    result = zr(<<~'RUBY')
      r001 = (begin; begin; raise "x"; rescue 5; :matched; end; rescue TypeError => e001; e001.class.to_s; end); p r001
      empty002 = []
      r002 = (begin; begin; raise ArgumentError, "a"; rescue *empty002; :matched; end; rescue ArgumentError => e002; e002.message; end); p r002
      lst = [ArgumentError, TypeError]
      r1 = (begin; raise TypeError, "t"; rescue *lst => e; e.class.to_s; end); p r1
      r2 = (begin; raise "x"; rescue *lst; :m; rescue => e; e.class.to_s; end); p r2
      r3 = (begin; raise ArgumentError, "a"; rescue *[]; :m; rescue => e; e.message; end); p r3
    RUBY

    _(result).must_answer <<~'OUT'
      "TypeError"
      "a"
      "TypeError"
      "RuntimeError"
      "a"
    OUT
  end

  it "rescue widens nil local to exception" do
    result = zr(<<~'RUBY')
      def f
        raised = nil
        begin
          raise NotImplementedError, "boom"
        rescue NotImplementedError => e
          raised = e
        end
        raised
      end

      puts f.inspect
    RUBY

    _(result).must_answer "#<NotImplementedError: boom>\n"
  end

  it "uncaught exception message" do
    result = zr(<<~'RUBY')
      # An uncaught exception's tail format: the message, the source line, and
      # the callers of the raising frame.
      def boom(v)
        v.length
      end

      begin
        boom(nil)
      rescue NoMethodError => e
        p e.message
      end

      p "before"
      boom(nil)
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR', status: 1
      "undefined method 'length' for nil"
      "before"
    OUT
      lang/exceptions/formatting_test.rb:4:in 'Object#boom': undefined method 'length' for nil (NoMethodError)

        v.length
         ^^^^^^^
      	from lang/exceptions/formatting_test.rb:14:in '<main>'
    ERR
  end

  it "unresolved call raises" do
    result = zr(<<~'RUBY')
      def id(x); x; end
      begin
        id({}).no_such_method_xyz
        puts "not reached"
      rescue NoMethodError => e
        puts e.class
      end
      begin
        r = id(nil).no_such_method_abc
        puts r.inspect
      rescue NoMethodError => e
        puts e.class
      end
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
      NoMethodError
      after
    OUT
  end

  it "void value in value position" do
    result = zr(<<~'RUBY')
      # A method that always raises never returns a value. Its result can still
      # sit in value position -- assigned to a local or passed as an argument.
      # That use never runs, because the call raises first.

      def boom
        raise "always raises"
      end

      def sink(x)
        x.to_s
      end

      def use_arg
        sink(boom)        # boom never returns; arg in value position
      end

      def use_local
        v = boom          # boom never returns; local in value position
        v.to_s
      end

      # Never executed (CRuby never raises), but all must AOT-compile -- including
      # a void value handed straight to puts / print / p.
      if false
        use_arg
        use_local
        puts boom
        print boom
        p boom
      end
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end
end
