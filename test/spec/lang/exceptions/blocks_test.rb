# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: blocks and yields" do
  it "block body rescue" do
    result = ze0(<<~'RUBY')
      r001 = [1, 2].map do |i|
        raise ArgumentError, "x" if i == 1
        i
      rescue ArgumentError
        :handled
      end
      p r001
      r2 = [1, 2].map { |i| begin; raise ArgumentError if i == 1; i; rescue ArgumentError; :h; end }
      p r2
      r3 = [1,2,3].each do |i|
        next if i == 2
      rescue StandardError
        :no
      end
      p r3
      def m3; yield 1; rescue; :caught; end
      p(m3 { |x| x * 2 })
    RUBY

    _(result).must_answer <<~'OUT'
      [:handled, 2]
      [:h, 2]
      [1, 2, 3]
      2
    OUT
  end

  it "block jump leaves an outer rescue its exception" do
    result = ze0(<<~'RUBY')
      # A `break`/`return` out of a block arms a signal and unwinds through the
      # landing chain, which pops `$!` itself -- the jump must not pop it too.
      def helper
        [1].each do
          begin
            raise "inner"
          rescue
            return 9
          end
        end
      end

      begin
        raise "outer"
      rescue
        r = [1].each do
          begin
            raise "nested"
          rescue
            break 7
          end
        end
        p r
        p $!.message
        p helper
        p $!.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      7
      "outer"
      9
      "outer"
    OUT
  end

  it "block tail rescue modifier" do
    result = ze0(<<~'RUBY')
      # A GNU statement-expression's value is its last statement only when that
      # statement is an EXPRESSION. The statement form of a `rescue` modifier is an
      # if/else over setjmp whose two arms compute the value and drop it, so a block
      # whose tail is one produced a void:
      #
      #   error: void value not ignored as it ought to be
      #
      # The if / case / begin tails were already on the list it was missing from.
      def wrap
        p(yield)
      end

      wrap { 1 rescue 9 }
      wrap { (raise "x") rescue 9 }
      wrap { Integer("101", 2) rescue 9 }
      wrap { Integer("nope") rescue -1 }

      def twice
        [yield, yield]
      end
      p(twice { 2 rescue 0 })

      p [1, 2, 0].map { |d| 10 / d rescue :div0 }
      p ["1", "x"].map { |s| Integer(s) rescue nil }

      # and the tails that already worked, unchanged
      wrap { if true then 1 else 2 end }
      wrap { case 1 when 1 then "one" else "other" end }
      wrap { begin; 5; end }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      9
      5
      -1
      [2, 2]
      [10, 5, :div0]
      [1, nil]
      1
      "one"
      5
    OUT
  end

  it "coercion type errors name nil true false as literals not class names" do
    result = ze0(<<~'RUBY')
      # CRuby renders nil/true/false in a coercion TypeError as those words, not
      # `NilClass`/`TrueClass`/`FalseClass`; every other object uses its class
      # name (`Integer`, `Symbol`).

      def msg
        yield
      rescue TypeError => e
        puts e.message
      end
      msg { "" + nil }
      msg { "" + true }
      msg { "" + false }
      msg { "" + 1 }
      msg { "" + :s }
      msg { Float(nil) }
      msg { Integer(true) }
      # A non-class target phrase ("an exact number") keeps the CLASS name,
      # even for nil -- the value-name rule is specific to class targets.
      msg { Time.at(nil) }
    RUBY

    _(result).must_answer <<~'OUT'
      no implicit conversion of nil into String
      no implicit conversion of true into String
      no implicit conversion of false into String
      no implicit conversion of Integer into String
      no implicit conversion of Symbol into String
      can't convert nil into Float
      can't convert true into Integer
      can't convert NilClass into an exact number
    OUT
  end

  it "exception introspection accessors" do
    result = ze0(<<~'RUBY')
      # Carried-state introspection accessors: KeyError#key/#receiver,
      # NameError/NoMethodError#receiver/#args/#private_call?, FrozenError#receiver,
      # LocalJumpError#reason/#exit_value, UncaughtThrowError#tag/#value,
      # and SystemExit (.new semantics, rescuable exit, #status/#success?).
      h = {"a" => 1}
      begin; h.fetch("zz"); rescue KeyError => e; p e.key; p e.receiver; end
      h0 = {}
      begin; h0.fetch(:x); rescue KeyError => e; p e.key; end
      ke = KeyError.new("m", key: :k, receiver: {1 => 2})
      p ke.key
      p ke.receiver
      p ke.message
      begin; nil.foo(1, 2); rescue NoMethodError => e; p e.receiver; p e.private_call?; end
      def m; yield; end
      begin; m; rescue LocalJumpError => e; p e.reason; p e.exit_value; end
      r = (begin; catch(:a) { throw :b }; rescue UncaughtThrowError => e; e.tag; end)
      p r
      r2 = (begin; catch(:a) { throw :b, 7 }; rescue UncaughtThrowError => e; e.value; end)
      p r2
      s = "x".freeze
      begin; s << "y"; rescue FrozenError => e; p e.receiver; end
      begin; raise "x"; rescue => e; (p e.key) rescue p $!.class; end
      p (SystemExit.new(2).class rescue $!.class)
      se = SystemExit.new(2)
      p se.message
      p se.status
      p se.success?
      p SystemExit.new.success?
      p SystemExit.new(true, "bye").message
      p SystemExit.superclass
      r3 = (begin; exit(false); "no"; rescue SystemExit; "caught"; end)
      p r3
      r4 = (begin; exit(3); "no"; rescue SystemExit => sx; sx.status; end)
      p r4
    RUBY

    _(result).must_answer <<~'OUT'
      "zz"
      {"a" => 1}
      :x
      :k
      {1 => 2}
      "m"
      nil
      false
      :noreason
      nil
      :b
      7
      "x"
      NoMethodError
      SystemExit
      "SystemExit"
      2
      false
      true
      "bye"
      Exception
      "caught"
      3
    OUT
  end

  it "proc return ensure raise" do
    _(ze0(<<~'RUBY')).must_answer "rescued: from ensure\n"
      # An exception raised inside an `ensure` that runs during a proc-return unwind
      # supersedes the return: it must propagate as a real exception, not be swallowed
      # while the abandoned non-local return is silently resumed.
      def home
        proc {
          begin
            return 1
          ensure
            raise "from ensure"
          end
        }.call
        2
      end
      begin
        puts home
      rescue => e
        puts "rescued: #{e.message}"
      end
    RUBY
  end

  it "proc return nested ensure" do
    _(ze0(<<~'RUBY')).must_answer "  inner ensure\nensure ran (10)\nouter-value\n"
      # A nested non-local return that itself runs an ensure -- and so completes a
      # full unwind -- while executing inside an outer proc-return's ensure must not
      # discard the outer return. The outer `return "outer-value"` runs its ensure,
      # which calls inner_ret (whose own proc-return passes an ensure and resolves);
      # the outer return value still has to be delivered.
      def inner_ret
        proc {
          begin
            return 10
          ensure
            puts "  inner ensure"
          end
        }.call
        20
      end
      def outer
        proc {
          begin
            return "outer-value"
          ensure
            x = inner_ret
            puts "ensure ran (#{x})"
          end
        }.call
        "WRONG: fell through"
      end
      puts outer
    RUBY
  end

  it "proc return rescue modifier escape" do
    result = ze0(<<~'RUBY')
      # Same home-escape-via-exception case as proc_return_escape_localjump, but the
      # exception is caught by an *expression-form* `rescue` modifier (a distinct
      # codegen path). The home node must still be dropped as the exception unwinds,
      # so the later return raises LocalJumpError rather than longjmping into a freed
      # frame.
      $escaped = nil
      def home
        $escaped = proc { return 99 }
        raise "boom"
      end
      v = (home rescue 123)
      p v
      begin
        $escaped.call
        puts "WRONG: no error"
      rescue LocalJumpError => e
        puts "localjump: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      123
      localjump: unexpected return
    OUT
  end

  it "proc unknown tail raise" do
    result = ze0(<<~'RUBY')
      # A proc whose tail is an sp_RbVal- or sp_Class-valued raising expression
      # (unresolved-call gate / NameError constant read) must coerce into the proc's
      # mrb_int return carrier instead of returning the mismatched C type raw.
      x = [1, "a"].sample
      g = -> { x.no_such_method_here }   # gate: sp_raise_nomethod (sp_RbVal tail)
      h = -> { NoSuchConst }             # NameError constant read (sp_Class dummy)
      begin
        g.call
      rescue Exception => e
        puts e.class
      end
      begin
        h.call
      rescue Exception => e
        puts e.class
      end
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
      NameError
      done
    OUT
  end

  it "raise in an argument keeps the block unbuilt" do
    result = ze0(<<~'RUBY', env: {"ZEO_RT_LEAKCHECK" => "1"})

      # A literal block's proc is MOVED to the callee, so no landing can release
      # it: on every path but the raise the callee has already taken the value
      # out of the slot. That makes the window between building the proc and
      # making the call load-bearing -- an argument that raises inside it leaks
      # the proc, once per execution.
      #
      # The emitter used to build the proc FIRST, before the receiver and the
      # argument list, at five call shapes. Each of the sends below raises from
      # an argument, and each leaked one `Proc` (tag 24) per iteration. The block
      # is now built last, which is also ruby's own order.
      #
      # `ZEO_RT_LEAKCHECK=1` is what makes this a test: the answers printed here
      # are the same either way, and the ledger's exit balance is the measurement.

      def missing
        raise ArgumentError, "no argument for you"
      end

      def takes_one(n)
        yield n
      end

      class Holder
        def initialize(n)
          @n = n
        end
      end

      def attempt
        yield
        "no raise"
      rescue ArgumentError
        "raised"
      end

      # A call to a compiled method, whose block rides its own parameter.
      p attempt { takes_one(missing) { |x| x } }

      # A dynamic send on a receiver the compiler cannot name.
      p attempt { [1, 2].fetch(missing) { |x| x } }

      # A splatted argument list, which builds its Array in the runtime.
      p attempt { takes_one(*[missing]) { |x| x } }

      # A keyword send.
      p attempt { [1, 2].each_slice(missing) { |x| x } }

      # A constructor, whose block forwards to `initialize`.
      p attempt { Holder.new(missing) { |x| x } }

      # Once more in a loop: a leak here is unbounded, not a one-off.
      10.times { attempt { takes_one(missing) { |x| x } } }
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      "raised"
      "raised"
      "raised"
      "raised"
      "raised"
      done
    OUT
  end

  it "raise kinds" do
    result = ze0(<<~'RUBY')
      # `raise` accepts several operand shapes: a message string raises a
      # RuntimeError, an exception class (with an optional message) raises an
      # instance of it, and any NON-exception value is a TypeError.
      def try
        yield
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      try { raise "boom" }                # RuntimeError: boom
      try { raise ArgumentError, "bad" }  # ArgumentError: bad
      try { raise ArgumentError }         # ArgumentError: ArgumentError
      try { raise 42 }                    # TypeError: exception class/object expected
      try { raise nil }                   # TypeError: exception class/object expected
      try { raise [1, 2] }                # TypeError: exception class/object expected
      try { raise :nope }                 # TypeError: exception class/object expected

      # The operand can be a runtime-typed (poly) value; raise dispatches on its
      # actual class.
      things = ["late", 99]
      try { raise things[0] }             # RuntimeError: late
      try { raise things[1] }             # TypeError: exception class/object expected
    RUBY

    _(result).must_answer <<~'OUT'
      RuntimeError: boom
      ArgumentError: bad
      ArgumentError: ArgumentError
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      RuntimeError: late
      TypeError: exception class/object expected
    OUT
  end

  it "raise non exception typeerror" do
    result = ze0(<<~'RUBY')
      # `raise <non-exception>` is CRuby's TypeError, not a value smuggled into
      # the message slot (a C type error for scalars, garbage for the rest).
      def try
        yield
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      try { raise 42 }
      try { raise nil }
      try { raise [1, 2] }
      try { raise :sym }
      try { raise 3.5 }
      try { raise({ a: 1 }) }
      # a string still raises RuntimeError with the message
      begin
        raise "boom"
      rescue RuntimeError => e
        puts "RuntimeError: #{e.message}"
      end
      # a runtime-typed (poly) operand dispatches on the value
      mixed = [Object.new, "msg"]
      begin
        raise mixed[1]
      rescue RuntimeError => e
        puts "poly string: #{e.message}"
      end
      begin
        raise mixed[0]
      rescue TypeError => e
        puts "poly object: #{e.message}"
      end
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      RuntimeError: boom
      poly string: msg
      poly object: exception class/object expected
      after
    OUT
  end

  it "raise with a splat argument reraises the class and message" do
    _(ze0(<<~'RUBY')).must_answer "wrapped: orig\n"
      # `raise(*exc)` -- a splat whose element count is a runtime value -- routes
      # through the runtime `Kernel#raise` (optparse's `{|*exc| raise(*exc)}`),
      # rather than the static 0..3-arg form.

      def relay
        yield
      rescue => e
        exc = [ArgumentError, "wrapped: #{e.message}"]
        raise(*exc)
      end
      begin
        relay { raise "orig" }
      rescue ArgumentError => e
        puts e.message
      end
    RUBY
  end

  it "recursion ten thousand deep" do
    result = ze0(<<~'RUBY')
      # Bounded recursion 10_000 deep -- plain, mutual, through a lambda, and on a
      # spawned thread -- answers rather than raising. CRuby's default VM stack
      # takes this depth; zeo's frames are native frames on a 64 MiB stack
      # (`zeo_rt::exec::MAIN_STACK_SIZE`), which the darwin link line sizes and a
      # spawned thread carries elsewhere. `infinite_recursion_aborts.rb` pins the
      # other side: past the stack, `SystemStackError` is rescuable.
      #
      # The lambda recurses by naming itself, so it holds the cell that holds it.
      # At exit: cycle leak: 2 objects (Proc x1, cell x1)

      def down(n) = n.zero? ? 0 : 1 + down(n - 1)
      p down(10_000)

      def ping(n) = n.zero? ? :ping : pong(n - 1)
      def pong(n) = n.zero? ? :pong : ping(n - 1)
      p ping(10_000)

      count = nil
      count = ->(n) { n.zero? ? 0 : 1 + count.(n - 1) }
      p count.(10_000)

      p Thread.new { down(10_000) }.value
    RUBY

    _(result).must_answer <<~'OUT'
      10000
      :ping
      10000
      10000
    OUT
  end

  it "rescue bind in lambda proc body" do
    result = ze0(<<~'RUBY')
      # `rescue => e` inside a lambda / proc body binds `e` as a body-local
      # exception. Before the fix the binding leaked to the enclosing scope so
      # the closure referenced an undeclared `lv_e`, and infer_type recomputed
      # `e.message` as int (a `#{e.message}` interp formatted the string
      # pointer with %lld). The string is observed inside the body so the test
      # is independent of the proc-call return-value ABI.
      lambda { begin; raise "a"; rescue => e; puts "got #{e.message}"; end }.call
      proc { begin; raise "boom"; rescue => e; puts "p #{e.message} (#{e.class})"; end }.call

      # Same construct, stored then called.
      f = lambda { begin; raise "late"; rescue => e; puts "f: #{e.message}"; end }
      f.call

      # A non-raising path through the body still compiles and runs.
      g = proc { begin; puts "no raise"; rescue => e; puts "unreached #{e.message}"; end }
      g.call
    RUBY

    _(result).must_answer <<~'OUT'
      got a
      p boom (RuntimeError)
      f: late
      no raise
    OUT
  end

  it "vcall miss is a name error" do
    result = ze0(<<~'RUBY')
      # A VCALL is a bare identifier ruby could have read as a local (`foo`, never
      # `foo()` or `self.foo`). The lookup is an ordinary send; the MISS is not.
      # Ruby cannot tell which the writer meant, so it says "undefined local
      # variable or method" and raises NameError. With parens or arguments it is
      # unambiguously a call, and a miss is NoMethodError.

      def show
        yield
      rescue NameError => e
        [e.class, e.message]
      end

      p(show { nope })
      p(show { nope() })
      p(show { nope(1) })
      p(show { self.nope })

      # In a method body, named for the instance.
      class K
        def go = show { missing }
        def show = (yield rescue [$!.class, $!.message])
      end
      p K.new.go

      # In a class body, named for the class -- an enclosing local is NOT in scope
      # there, which is exactly the case the message is written for.
      outer = 1
      class Arr
        begin
          outer
        rescue NameError => e
          p [e.class, e.message]
        end
      end

      # A name that IS a local reads it, no send at all.
      defined_local = :read
      p(defined_local)

      # NameError carries the name it could not find.
      begin
        absent_thing
      rescue NameError => e
        p [e.name, e.receiver == self]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [NameError, "undefined local variable or method 'nope' for main"]
      [NoMethodError, "undefined method 'nope' for main"]
      [NoMethodError, "undefined method 'nope' for main"]
      [NoMethodError, "undefined method 'nope' for main"]
      [NameError, "undefined local variable or method 'missing' for an instance of K"]
      [NameError, "undefined local variable or method 'outer' for class Arr"]
      :read
      [:absent_thing, true]
    OUT
  end

  it "yield no block raises" do
    result = ze0(<<~'RUBY')
      # An unguarded yield in a method called with no block raises LocalJumpError.
      # A block_given?-guarded yield does not.
      def run
        yield
      end
      begin
        run
      rescue LocalJumpError => e
        puts "stmt: #{e.message}"
      end

      def ex
        x = yield
        x + 1
      end
      begin
        ex
      rescue LocalJumpError => e
        puts "expr: #{e.message}"
      end

      def guarded
        block_given? ? yield : 42
      end
      puts guarded

      def maybe
        yield if block_given?
        "done"
      end
      puts maybe

      # same method used with a block still works
      def twice
        yield + yield
      end
      puts twice { 21 }
    RUBY

    _(result).must_answer <<~'OUT'
      stmt: no block given (yield)
      expr: no block given (yield)
      42
      done
      42
    OUT
  end

  it "yielding call in rescue expr" do
    result = ze0(<<~'RUBY')
      def wrap001
        yield
      end
      r001 = (begin; wrap001 { raise ArgumentError, "d" }; rescue => e001; 0; end); p r001
      r002 = (begin; wrap001 { 5 }; rescue => e; 0; end); p r002
      def w2; yield; end
      r003 = begin; w2 { raise "z" }; rescue => e; :c; end; p r003
      def w3(a); yield a; end
      r004 = (begin; w3(2) { |x| raise ArgumentError if x == 2; x }; rescue ArgumentError; :r; end); p r004
    RUBY

    _(result).must_answer <<~'OUT'
      0
      5
      :c
      :r
    OUT
  end
end
