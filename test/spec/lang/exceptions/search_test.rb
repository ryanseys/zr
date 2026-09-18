# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: searching and matching" do
  it "begin rescue as expression" do
    result = ze0(<<~'RUBY')
      # Issue #704: begin/rescue used as an expression (puts arg).
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
    result = ze0(<<~'RUBY')
      # A `class Foo` after `module Foo`, and a reopen that names a different
      # superclass, are both TypeError in ruby -- a real exception at the definition,
      # not a broken program. zeo used to REFUSE these at compile time whenever no
      # `rescue` was lexically visible inside the definition's own statement, on the
      # reasoning that an uncatchable raise aborts and a compile error naming the
      # same problem is the better version of aborting.
      #
      # Two things were wrong with that. The lexical scan cannot see the handler a
      # CALLER wraps the `require` in, which catches these perfectly well. And four
      # of the five registration sites never consulted the scan at all, so the shape
      # below -- a top-level kind collision, which is every `hola_*` tutorial gem on
      # rubygems, and a whole family of generated SDKs that declare one class name
      # under two superclasses -- could not be compiled either way.
      #
      # Both halves of the message are ruby's, including the second line, whose
      # position is the one stamped when the CONSTANT was created.
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
    result = ze0(<<~'RUBY')
      # #548. Four shapes that compiled cleanly but hung at runtime.
      # Adam Doppelt's "Puzzles, third edition."
      #
      # 1. `a.concat(a, a)` -- two bugs in compile_call_stmt's concat
      #    arm. (a) Only the first arg was processed, so multi-arg
      #    concat dropped the tail silently. (b) The src-array length
      #    was queried inside the push loop; when an arg aliased the
      #    receiver (`a.concat(a)`) every push grew the source and
      #    the loop never terminated. Fix: snapshot each arg's length
      #    before its inner loop, then iterate every arg.
      #
      # 2. `/\#{re}/` -- regex compiler entered an infinite loop. The
      #    sequence `\#` lowered to literal `#`, then `{re}` arrived
      #    at compile_atom with `{` as the leading char. `{` was in
      #    compile_atom's "not an atom" filter, so the function
      #    returned without consuming and compile_seq's outer loop
      #    spun. CRuby treats `/{re}/` as matching the literal text
      #    `{re}` (`{...}` without a valid quantifier is literal); we
      #    mirror that by removing `{` from compile_atom's filter so
      #    a leading `{` falls through to the literal-char emit.
      #
      # 3. `while () ; 123 ; end` -- empty `()` infers as "void" and
      #    lowers to literal `0`. compile_cond_expr's catch-all
      #    `((expr), TRUE)` flipped the empty-parens condition to
      #    always-true and the loop hung. Treat "void" like "nil" in
      #    compile_cond_expr -- both lower to FALSE so `while ()`
      #    never enters the body, matching CRuby.
      #
      # 4. `i += 1; raise; rescue; retry unless i == 7` -- setjmp/
      #    longjmp local-preservation. `lv_i` modified inside the
      #    setjmp scope must be `volatile` to survive longjmp's
      #    register-unwind; with `-O3` the compiler register-cached
      #    `lv_i` and the rescue handler saw a stale 0, so `i == 7`
      #    was never satisfied and retry spun forever. Fix: pre-scan
      #    method bodies for setjmp-triggering shapes (begin/rescue,
      #    raise, retry) and mark non-pointer locals as `volatile`.
      #    Pointer locals stay non-volatile (GC-rooted via
      #    SP_GC_ROOT already keeps them stable; tagging them
      #    volatile triggers -Wdiscarded-qualifiers cascade at
      #    string/array helper call sites).

      # Repro 1: self-concat with self twice.
      a = [1, 2]
      a.concat(a, a)
      puts a.length      # 8 -- [1,2] + [1,2] + [1,2,1,2]

      # Repro 2: regex with literal `\#{re}` characters.
      re = /foo|bar/
      r2 = /\#{re}/
      puts "ok2"

      # Repro 3: while () never enters.
      while () ; 123 ; end
      puts "ok3"

      # Repro 4: retry-counter survives longjmp.
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # rescue of a namespaced exception class (rescue M::Err) must match a
      # raised M::Err. Both the raise and the rescue clause need to resolve
      # the ConstantPathNode (M::Err) to the registered class name (M_Err);
      # previously raise emitted a bare sp_raise (no class) and rescue
      # checked only the leaf name, so the handler never matched.
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # `rescue => target` accepts every lvalue Ruby accepts -- including an
      # attribute setter and an index write, which run only when the clause
      # fires (receiver evaluated at that moment, then `attr=`/`[]=` called
      # with the exception). zeo lowered only the variable-shaped targets and
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
    result = ze0(<<~'RUBY')
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
