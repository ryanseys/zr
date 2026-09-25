# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: searching and matching" do
  it "begin rescue as expression" do
    result = zr(<<~'RUBY')
      # begin/rescue used as an expression (puts arg).
      # Three shapes:
      #   - rescue path (raise + rescue + else + ensure)
      #   - else path (no raise, rescue chain skipped)
      #   - multi-class rescue (raise SubClass, match second clause)
      puts (begin; raise "x"; rescue; "caught"; else; "no error"; ensure; "ensured"; end)
      puts (begin; 42; rescue; "caught"; else; "no error"; end)
      puts (begin; raise ArgumentError; rescue TypeError; "type"; rescue ArgumentError; "arg"; end)

      # Bare begin..end as expression (no rescue / ensure).
      puts (begin; 100; end)

      # Single-class raise + rescue.
      puts (begin; raise NotImplementedError; rescue NotImplementedError; "ni"; end)
    RUBY

    _(result).must_answer <<~'OUT'
      caught
      no error
      arg
      100
      ni
    OUT
  end

  it "definition ruby raises on raises" do
    result = zr(<<~'RUBY')
      # A `class Foo` after `module Foo`, and a reopen that names a different
      # superclass, are both TypeError in ruby -- a real exception at the definition,
      # not a broken program. So the program compiles, and the TypeError raises at
      # run time, also when no `rescue` is visible in the definition's own statement.
      #
      # A CALLER can wrap the `require` in a handler that catches these. The shape
      # below -- a top-level kind collision -- is in every `hola_*` tutorial gem on
      # rubygems, and in a whole family of generated SDKs that declare one class
      # name under two superclasses.
      #
      # Both halves of the message are ruby's, including the second line, whose
      # position is the one stamped when the CONSTANT was created.

      # The blank lines keep the line numbers that the expected output names.


      module Foo
        X = 1
      end

      begin
        class Foo
          def never = "unreachable"
        end
      rescue TypeError => e
        puts e.message
      end

      # The definition that raised changed nothing: ruby leaves the module exactly
      # as it was.
      p Foo::X
      p Foo.instance_of?(Module)
      p Foo.respond_to?(:never)

      class Base; end
      class Other; end
      class Sub < Base; end

      begin
        class Sub < Other; end
      rescue TypeError => e
        puts e.message
      end

      p Sub.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      Foo is not a class
      lang/exceptions/search_test.rb:17: previous definition of Foo was here
      1
      true
      false
      superclass mismatch for class Sub
      Base
    OUT
  end

  it "hangs 548" do
    result = zr(<<~'RUBY')
      # Four shapes that must end, not hang, at runtime.
      # Adam Doppelt's "Puzzles, third edition."
      #
      # 1. `a.concat(a, a)` -- concat appends every arg. When an arg is
      #    the receiver itself, concat uses the arg's length from before
      #    the call, so the loop ends.
      #
      # 2. `/\#{re}/` -- `\#` is a literal `#`, and then `{re}` follows.
      #    CRuby treats `/{re}/` as matching the literal text `{re}`
      #    (`{...}` without a valid quantifier is literal).
      #
      # 3. `while () ; 123 ; end` -- the empty `()` is nil, so it is
      #    false. `while ()` never enters the body, as in CRuby.
      #
      # 4. `i += 1; raise; rescue; retry unless i == 7` -- the local `i`
      #    keeps its value across each raise and retry. So `i == 7`
      #    becomes true and the retry loop ends.

      # Repro 1: self-concat with self twice.
      a = [1, 2]
      a.concat(a, a)
      puts a.length      # 6 -- [1,2] + [1,2] + [1,2]

      # Repro 2: regex with literal `\#{re}` characters.
      re = /foo|bar/
      r2 = /\#{re}/
      puts "ok2"

      # Repro 3: while () never enters.
      while () ; 123 ; end
      puts "ok3"

      # Repro 4: retry-counter keeps its value across retry.
      def foo
        i = 0
        begin ; i += 1 ; raise "bar" ; rescue ; retry unless i == 7 ; end
        raise "baz" unless i == 7
      rescue
        123
      end
      puts foo  # 123  (foo's body would also raise "baz" if i != 7; here i == 7
                #       so no raise, and the function falls through. The
                #       outer rescue is dead code for this path.)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      ok2
      ok3

    OUT
  end

  it "a raise inside a method that yields stops before the block runs" do
    result = zr(<<~'RUBY')
      def check(selector, body)
        tag = selector[/\A[a-z]+/]
        raise "no #{selector}" unless tag && body.include?("<#{tag}")
        yield
      end
      check("div", "<div>x</div>") { puts "found div" }
      begin
        check("p", "<div>x</div>") { puts "unreachable" }
      rescue => e
        puts "raised: #{e.message}"
      end
    RUBY

    _(result).must_answer "found div\nraised: no p\n"
  end

  it "rescue matches a namespaced exception class by its full path" do
    result = zr(<<~'RUBY')
      # rescue of a namespaced exception class (rescue M::Err) must match a
      # raised M::Err. Both the raise and the rescue clause use the full
      # path M::Err, not only the leaf name Err.
      module M
        class Err < StandardError; end
      end

      begin
        raise M::Err, "boom"
      rescue M::Err => e
        puts "caught: " + e.message
      end

      # Control: bare base class still matches a namespaced raise.
      begin
        raise M::Err, "again"
      rescue StandardError => e
        puts "base: " + e.message
      end

      # Control: top-level class name still matches.
      class TopErr < StandardError; end
      begin
        raise TopErr, "top"
      rescue TopErr => e
        puts "top: " + e.message
      end

      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      caught: boom
      base: again
      top: top
      after
    OUT
  end

  it "raise branch does not widen" do
    result = zr(<<~'RUBY')
      # a branch that raises contributes no type to the case/if it sits in
      def enc(o)
        case o
        when Integer then 7
        when String  then 12
        else raise ArgumentError, "no"
        end
      end
      v = enc("ab")
      p v.class
      p v.succ
      p v.succ.class

      def s(o)
        case o
        when Integer then "i"
        when String  then "sample text"
        else raise ArgumentError, "no"
        end
      end
      p s("ab").count("s")
      p s("ab").sum
      p s("ab").match?(/\w/)

      def enc2(o)
        if o.is_a?(String) then "sample text" else raise ArgumentError, "no" end
      end
      p enc2("ab").match?(/\w/)

      def h(o)
        case o
        when Integer then {"a" => 1}
        when String  then {"b" => 2}
        else raise ArgumentError, "no"
        end
      end
      p h("ab").sum { |_k, v| v }

      # the raising branch is still taken when it should be
      r = (enc(1.5) rescue $!.class)
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      13
      Integer
      1
      1127
      true
      true
      2
      ArgumentError
    OUT
  end

  it "rescue target may be an attribute or index" do
    result = zr(<<~'RUBY')
      # `rescue => target` accepts every lvalue Ruby accepts -- including an
      # attribute setter and an index write, which run only when the clause
      # fires (receiver evaluated at that moment, then `attr=`/`[]=` called
      # with the exception). zr lowered only the variable-shaped targets and
      # rejected these two.
      class Holder
        attr_accessor :err
      end

      h = Holder.new
      begin
        raise ArgumentError, "boom"
      rescue => h.err
        puts "rescued into attr"
      end
      p h.err.class
      p h.err.message

      slot = {}
      begin
        raise KeyError, "missing"
      rescue KeyError => slot[:why]
        puts "rescued into index"
      end
      p slot[:why].class

      # The receiver expression is evaluated when the clause fires, not before.
      def fresh
        $built += 1
        Holder.new
      end
      $built = 0
      begin
        raise "later"
      rescue => fresh.err
      end
      p $built
    RUBY

    _(result).must_answer <<~'OUT'
      rescued into attr
      ArgumentError
      "boom"
      rescued into index
      KeyError
      1
    OUT
  end

  it "rescue with a splatted exception list" do
    result = zr(<<~'RUBY')
      ERRS = [ArgumentError, TypeError]

      # A constant array of classes.
      begin
        raise TypeError, "t"
      rescue *ERRS => e
        puts "const #{e.class}"
      end

      # A local array; no `=> e` capture.
      errs = [KeyError]
      begin
        raise KeyError, "k"
      rescue *errs
        puts "local no-capture"
      end

      # Static class mixed with a splat, in either order.
      extra = [TypeError]
      begin; raise TypeError, "t"; rescue ArgumentError, *extra => e; puts "mixed1 #{e.class}"; end
      lead = [KeyError]
      begin; raise TypeError, "t"; rescue *lead, TypeError => e; puts "mixed2 #{e.class}"; end

      # Splatting a single class (not an array) wraps it: `*one` == `[one]`.
      one = RuntimeError
      begin; raise "r"; rescue *one => e; puts "single #{e.class}"; end

      # An empty array catches nothing -> propagates.
      empty = []
      begin
        begin; raise TypeError, "t"; rescue *empty; puts "wrong"; end
      rescue TypeError
        puts "empty catches nothing"
      end

      # A non-matching splat re-raises to an outer handler.
      only_arg = [ArgumentError]
      begin
        begin; raise TypeError, "t"; rescue *only_arg; puts "wrong"; end
      rescue TypeError => e2
        puts "propagated #{e2.class}"
      end

      # ensure still runs; $! is the caught exception; module-include matches.
      module Alertable; end
      class Alarmed < StandardError; include Alertable; end
      mods = [Alertable]
      begin
        raise Alarmed, "a"
      rescue *mods
        puts "module-match #{$!.class}"
      ensure
        puts "ensure ran"
      end

      # Splat rescue as a method-body clause, with retry.
      E = [RuntimeError]
      def flaky
        @n = (@n || 0) + 1
        raise "x" if @n < 2
        "ok n=#{@n}"
      rescue *E
        retry if @n < 2
      end
      puts flaky
    RUBY

    _(result).must_answer <<~'OUT'
      const TypeError
      local no-capture
      mixed1 TypeError
      mixed2 TypeError
      single RuntimeError
      empty catches nothing
      propagated TypeError
      module-match Alarmed
      ensure ran
      ok n=2
    OUT
  end
end
