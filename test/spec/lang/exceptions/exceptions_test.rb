# frozen_string_literal: true

require "spec_helper"

describe "Exceptions programs" do
  it "bang exception object" do
    result = ze0(<<~'RUBY')
      # $! is the exception object the innermost active rescue is handling (nil
      # outside one): same identity as the rescue variable and the raised object.
      e = StandardError.new 'foo'
      begin
        raise e
      rescue => err
        puts err.message
        puts $!.message
        puts $!.equal?(err)
        puts $!.equal?(e)
      end
      p $!
      begin
        raise ArgumentError, "inner"
      rescue
        puts $!.message
        begin
          raise TypeError, "deep"
        rescue
          puts $!.message
        end
        puts $!.message
      end
      p $!
    RUBY

    _(result).must_answer <<~'OUT'
      foo
      foo
      true
      true
      nil
      inner
      deep
      inner
      nil
    OUT
  end

  it "bare raise re raises preserving a custom exceptions own ivars" do
    result = ze0(<<~'RUBY')
      class MyError < StandardError
        def initialize(msg, code)
          super(msg)
          @code = code
        end
        def code
          @code
        end
      end

      class Inner
        def call
          begin
            raise MyError.new("failed with code 42", 42)
          rescue MyError => e
            puts "inner saw code #{e.send(:code)}"
            raise
          end
        end
      end

      begin
        Inner.new.call
      rescue MyError => e
        puts "outer saw code #{e.send(:code)}"
        puts "outer message: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      inner saw code 42
      outer saw code 42
      outer message: failed with code 42
    OUT
  end

  it "bare raise with no active rescue constructs a runtime error" do
    _(ze0(<<~'RUBY')).must_answer "[]\n"
      # Bare `raise` (re-raise) outside any active `rescue` clause -- real
      # Ruby constructs a fresh `RuntimeError` with an EMPTY message rather
      # than erroring (oracle-verified: `ruby -e 'begin; raise; rescue => e;
      # puts "[#{e.message}]"; end'` -> `"[]"`).

      begin
        raise
      rescue => e
        puts "[#{e.message}]"
      end
    RUBY
  end

  it "basicobject dup rescued" do
    result = ze0(<<~'RUBY')
      # An absent Object method on a blank-slate receiver raises INSIDE the
      # enclosing handler's region (#2726): the raise is an expression-arm prelude,
      # which used to emit before the rescue modifier's setjmp.
      class BO < BasicObject
        def initialize; @x = 1; end
        def own; @x; end
      end
      a = BO.new
      r = (a.dup.own rescue $!.class)
      p r
      p a.own
    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
      1
    OUT
  end

  it "begin rescue used as an expressions value" do
    _(ze0(<<~'RUBY')).must_answer "-1\n"
      x = begin
        raise "bad"
      rescue
        -1
      end
      puts x
    RUBY
  end

  it "bigint div by zero" do
    result = ze0(<<~'RUBY')
      # Bigint division / modulo by zero raises ZeroDivisionError.
      #
      # Bigint detection: `a = a * 2` inside a `while` loop promotes the
      # local to bigint via scan_bigint_in_loop_node. Raising 1 by *2 50
      # times overflows the mrb_int range so `a` is bigint-typed by the
      # time we hit the / 0 expression.
      #
      # Runtime path: sp_bigint_div / sp_bigint_mod call into mini-gmp,
      # which detects the zero divisor at sp_bigint.c:2718 and calls
      # mrb_raise(mrb, E_ZERODIV_ERROR, "divided by 0"). The mrb_raise
      # macro now dispatches to sp_bigint_raise_zerodiv (defined non-
      # static in sp_runtime.h, linked from gen.c), which calls
      # sp_raise_cls — same longjmp path as the int-div case.

      a = 1
      i = 0
      while i < 50
        a = a * 2
        i = i + 1
      end

      # `a` is now 2^50, well above the mrb_int range — bigint-typed.

      begin
        x = a / 0
        puts "no raise"
      rescue ZeroDivisionError => e
        puts "caught bigint div: #{e}"
      end

      begin
        x = a % 0
        puts "no raise"
      rescue ZeroDivisionError => e
        puts "caught bigint mod: #{e}"
      end

      # Bare rescue also catches.
      begin
        a / 0
      rescue => e
        puts "bare-rescue: #{e}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      caught bigint div: divided by 0
      caught bigint mod: divided by 0
      bare-rescue: divided by 0
    OUT
  end

  it "bigint volatile combo" do
    result = ze0(<<~'RUBY')
      # Regression test: bigint operations inside begin/rescue must compile
      # clean under -Werror. Locals in setjmp-bearing functions are emitted
      # `volatile sp_Bigint *`, but the bigint runtime takes plain
      # `sp_Bigint *`. Without (sp_Bigint *) casts at every emit site, gcc
      # / clang warn about discarded qualifiers, and the test runner's
      # -Werror promotes that to a hard fail.
      #
      # Exercises every bigint operator dispatch path that previously
      # emitted a cast-free local read. Output values are not the focus —
      # the test runner gates on the C code compiling clean with -Werror.

      a = 1
      i = 0
      while i < 50
        a = a * 2
        i = i + 1
      end

      # Inside begin/rescue: every binary operator + comparison + to_s/to_i
      begin
        b = a + a
        puts b.to_s.length > 0
        c = a - a
        puts c.to_s.length > 0
        d = a * a
        puts d.to_s.length > 0
        e = a / 2
        puts e.to_s.length > 0
        f = a % 7
        puts f.to_s.length > 0
        puts a > 0
        puts a < 0
        puts a >= 0
        puts a <= 0
        puts a == a
        puts a != 0
        puts a.to_s.length > 0
        puts a.to_i > 0
      rescue
        puts "caught"
      end

      # Compound assignment inside begin/rescue. `x = x + 1` desugars to
      # LocalVariableWriteNode + CallNode; the `+=` family lowers through
      # LocalVariableOperatorWriteNode, a distinct code path that has its
      # own bigint cast in compile_LocalVariableAndWriteNode.
      begin
        x = a
        x += 1
        x *= 2
        x -= 1
        x /= 2
        x %= 7
        puts x.to_s.length > 0
      rescue
        puts "caught"
      end

      # puts/p of bigint inside begin/rescue. Single-arg dispatches through
      # compile_puts_single; multi-arg through compile_puts. Both arms have
      # their own bigint cast and need exercising. `print` lands in the
      # multi-arg path too.
      begin
        puts a
        puts a, a
        print a, "\n"
      rescue
        puts "caught"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      false
      true
      false
      true
      true
      true
      true
      true
      1125899906842624
      1125899906842624
      1125899906842624
      1125899906842624
    OUT
  end

  it "case in pattern matching inside a rescue body" do
    _(ze0(<<~'RUBY')).must_answer "matched string: boom\n"
      # Composes pattern matching with exception handling --
      # `e.send(:message)` is a `Poly` expression, matched via `case/in`'s own
      # `#deconstruct`-independent `ClassCheck`/`Capture` path.

      begin
        raise "boom"
      rescue => e
        case e.send(:message)
        in String => s
          puts "matched string: #{s}"
        end
      end
    RUBY
  end

  it "case in with no matching arm and no else raises" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/case_in_with_no_matching_arm_and_no_else_raises.rb")
      # The message names the value and the sub-test that rejected it,
      # which is the whole diagnostic for a `case/in` -- oracle-verified.

      case 5
      in String
        puts "no"
      end
    RUBY

    _(result).must_answer "", stderr: "lang/exceptions/case_in_with_no_matching_arm_and_no_else_raises.rb:4:in '<main>': 5: String === 5 does not return true (NoMatchingPatternError)\n", status: 1
  end

  it "catch throw delivers values and uncaught throw raises" do
    result = ze0(<<~'RUBY')
      def thrower; throw :done, [1, 2]; end
      p catch(:done) { thrower }
      outer = Object.new; inner = Object.new
      p (catch(outer) { catch(inner) { throw outer, :to_outer }; :nr })
      begin
        throw :nope, 5; puts "WRONG"
      rescue UncaughtThrowError => e
        puts e.message
      end
      catch(:gone) { }
      begin
        throw :gone
      rescue UncaughtThrowError => e
        puts "gone: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      :to_outer
      uncaught throw :nope
      gone: uncaught throw :gone
    OUT
  end

  it "collection leaf methods" do
    result = ze0(<<~'RUBY')
      # Array, Hash, and Range leaf methods.

      # Array#rfind scans from the right; Array#fetch_values is strict.
      p [1, 2, 3, 4].rfind { |x| x.even? }
      p [1, 2, 3, 4].rfind { |x| x > 9 }
      p [10, 20, 30].fetch_values(0, 2)
      p([10, 20, 30].fetch_values(0, 5) { |i| i * 100 })
      begin
        [10, 20, 30].fetch_values(0, 9)
      rescue IndexError => e
        puts e.message
      end

      # Hash#to_proc turns a hash into a key-lookup callable; transform_keys! mutates.
      lookup = { a: 1, b: 2 }.to_proc
      p lookup.call(:a)
      p [:a, :b].map(&{ a: 10, b: 20 }.to_proc)
      h = { a: 1, b: 2 }
      p h.transform_keys!(&:to_s)
      p h

      # Range#overlap? tests whether two ranges share an element.
      p (1..5).overlap?(5..8)
      p (1...5).overlap?(5..8)
      p (1..5).overlap?(6..8)
      p (1..5).overlap?(0..0)
      p (1..10).overlap?(3..4)

      # String#upto walks succ values; the byte* methods index/slice on bytes.
      p "a8".upto("b1").to_a
      p "hello".byteindex("l")
      p "hello".byterindex("l")
      p "café".byteslice(0, 3)
      p "hello".byteslice(-2, 2)

      # tr_s squeezes translated runs; scrub! returns self.
      p "hello".tr_s("l", "r")
      p "aabbcc".tr_s("a-c", "x")
      p "clean".scrub!

      # Enumerable methods now reach Range and Hash.
      p (1..3).zip([4, 5, 6], [7, 8, 9])
      p (1..5).compact
      p (1..3).chain([4, 5]).to_a
      seen = []
      (1..3).cycle(2) { |x| seen << x }
      p seen
      p({ a: 1, b: 2 }.zip([10, 20]))
      p({ a: 1 }.rehash)
    RUBY

    _(result).must_answer <<~'OUT'
      4
      nil
      [10, 30]
      [10, 500]
      index 9 outside of array bounds: -3...3
      1
      [10, 20]
      {"a" => 1, "b" => 2}
      {"a" => 1, "b" => 2}
      true
      false
      false
      false
      true
      ["a8", "a9", "b0", "b1"]
      2
      3
      "caf"
      "lo"
      "hero"
      "x"
      "clean"
      [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
      [1, 2, 3, 4, 5]
      [1, 2, 3, 4, 5]
      [1, 2, 3, 1, 2, 3]
      [[[:a, 1], 10], [[:b, 2], 20]]
      {a: 1}
    OUT
  end

  it "core error shows only ruby frames" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/a_core_error_shows_only_ruby_frames.rb")
      # An error a core method raises shows the frames of the methods the
      # program called and the C methods ruby shows, and none of the helpers
      # the runtime keeps for itself: in a block, in sort_by, in Integer(), in
      # JSON.parse, in fetch, in eval and in Comparable.
      require "json"
      def show
        yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
        puts e.backtrace_locations.map { |l| "#{File.basename(l.path)}:#{l.lineno}:#{l.label}" }
      end
      show { "a\xffb".force_encoding("UTF-8").grapheme_clusters.map { |c| c.foo } }
      show { [3, 1].sort_by { |x| x.zork } }
      show { %w[1 x].map { |v| Integer(v) } }
      show { JSON.parse("{") }
      show { {a: 1}.fetch(:b) }
      show { [1].fetch(5) }
      show { [1, "a"].sort }
      show { [1, 2].each_slice(0) }
      show { "abc".unpack("@9") }
      show { [1, 2].min_by { |x| raise "in min_by" } }
      show { {a: 1}.each { |k, v| raise "in each" } }
      show { eval("1 +") }
      show { Struct.new(:a).new(1, 2) }
      show { "x".encode("NOPE") }
      show { Comparable.instance_method(:clamp).bind_call(3, 5, 1) }

    RUBY

    _(result).must_answer "NoMethodError: undefined method 'foo' for an instance of String\na_core_error_shows_only_ruby_frames.rb:12:block (2 levels) in <main>\na_core_error_shows_only_ruby_frames.rb:12:Array#map\na_core_error_shows_only_ruby_frames.rb:12:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:12:<main>\nNoMethodError: undefined method 'zork' for an instance of Integer\na_core_error_shows_only_ruby_frames.rb:13:block (2 levels) in <main>\na_core_error_shows_only_ruby_frames.rb:13:Array#each\na_core_error_shows_only_ruby_frames.rb:13:Enumerable#sort_by\na_core_error_shows_only_ruby_frames.rb:13:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:13:<main>\nArgumentError: invalid value for Integer(): \"x\"\na_core_error_shows_only_ruby_frames.rb:14:Kernel#Integer\na_core_error_shows_only_ruby_frames.rb:14:block (2 levels) in <main>\na_core_error_shows_only_ruby_frames.rb:14:Array#map\na_core_error_shows_only_ruby_frames.rb:14:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:14:<main>\nJSON::ParserError: expected object key, got EOF at line 1 column 2\ncommon.rb:364:JSON::Ext::Parser.parse\ncommon.rb:364:JSON.parse\na_core_error_shows_only_ruby_frames.rb:15:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:15:<main>\nKeyError: key not found: :b\na_core_error_shows_only_ruby_frames.rb:16:Hash#fetch\na_core_error_shows_only_ruby_frames.rb:16:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:16:<main>\nIndexError: index 5 outside of array bounds: -1...1\na_core_error_shows_only_ruby_frames.rb:17:Array#fetch\na_core_error_shows_only_ruby_frames.rb:17:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:17:<main>\nArgumentError: comparison of Integer with String failed\na_core_error_shows_only_ruby_frames.rb:18:Array#sort\na_core_error_shows_only_ruby_frames.rb:18:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:18:<main>\nArgumentError: invalid slice size\na_core_error_shows_only_ruby_frames.rb:19:Enumerable#each_slice\na_core_error_shows_only_ruby_frames.rb:19:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:19:<main>\nArgumentError: @ outside of string\na_core_error_shows_only_ruby_frames.rb:20:String#unpack\na_core_error_shows_only_ruby_frames.rb:20:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:20:<main>\nRuntimeError: in min_by\na_core_error_shows_only_ruby_frames.rb:21:block (2 levels) in <main>\na_core_error_shows_only_ruby_frames.rb:21:Array#each\na_core_error_shows_only_ruby_frames.rb:21:Enumerable#min_by\na_core_error_shows_only_ruby_frames.rb:21:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:21:<main>\nRuntimeError: in each\na_core_error_shows_only_ruby_frames.rb:22:block (2 levels) in <main>\na_core_error_shows_only_ruby_frames.rb:22:Hash#each\na_core_error_shows_only_ruby_frames.rb:22:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:22:<main>\nSyntaxError: (eval at lang/exceptions/a_core_error_shows_only_ruby_frames.rb:23):1: syntax errors found\n> 1 | 1 +\n    |    ^ unexpected end-of-input, assuming it is closing the parent top level context\n    |    ^ unexpected end-of-input; expected an expression after the operator\na_core_error_shows_only_ruby_frames.rb:23:Kernel#eval\na_core_error_shows_only_ruby_frames.rb:23:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:23:<main>\nArgumentError: struct size differs\na_core_error_shows_only_ruby_frames.rb:24:Struct#initialize\na_core_error_shows_only_ruby_frames.rb:24:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:24:<main>\nEncoding::ConverterNotFoundError: code converter not found (UTF-8 to NOPE)\na_core_error_shows_only_ruby_frames.rb:25:String#encode\na_core_error_shows_only_ruby_frames.rb:25:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:25:<main>\nArgumentError: min argument must be less than or equal to max argument\na_core_error_shows_only_ruby_frames.rb:26:Comparable#clamp\na_core_error_shows_only_ruby_frames.rb:26:UnboundMethod#bind_call\na_core_error_shows_only_ruby_frames.rb:26:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:26:<main>\n"
  end

  it "core error shows only ruby frames pack" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb")
      # A pack or unpack that raises shows the frame of the method the program
      # called, and none of the helpers ze0 keeps for itself: CRuby does that
      # work in C, with no frame and no constant a program can see.

      def show
        yield
      rescue => e
        puts "#{e.class}: #{e.message}"
        puts e.backtrace
      end

      show { "abc".unpack("@9") }
      show { "abc".unpack1("x9") }
      show { [1].pack(1) }
      show { [1].pack("y") }
      show { "abc".unpack("m0") }
      p Object.constants.include?(:Packing)

    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: @ outside of string
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:12:in 'String#unpack'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:12:in 'block in <main>'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:12:in '<main>'
      ArgumentError: x outside of string
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:13:in 'String#unpack1'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:13:in 'block in <main>'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:13:in '<main>'
      TypeError: no implicit conversion of Integer into String
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:14:in 'Array#pack'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:14:in 'block in <main>'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:14:in '<main>'
      ArgumentError: unknown pack directive 'y' in 'y'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:15:in 'Array#pack'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:15:in 'block in <main>'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:15:in '<main>'
      ArgumentError: invalid base64
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:16:in 'String#unpack'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:16:in 'block in <main>'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:16:in '<main>'
      false
    OUT
  end

  it "deep object chain release" do
    result = ze0(<<~'RUBY')
      # Releasing a long chain of objects must not cost one stack frame per link.
      class Link
        attr_accessor :nxt
        def initialize(n)
          @nxt = n
          @tag = "link"
        end
      end

      def chain(len)
        head = nil
        len.times { head = Link.new(head) }
        head
      end

      head = chain(200_000)
      n = 0
      cur = head
      while cur
        n += 1
        cur = cur.nxt
      end
      p n

      # Dropping the only reference releases all 200,000 at once.
      head = nil
      GC.start
      p chain(200_000).nxt.nxt.nil?

      # A chain through an ivar that a runtime path invented releases the same way.
      deep = Link.new(nil)
      200_000.times do
        outer = Link.new(nil)
        outer.instance_variable_set(:@inner, deep)
        deep = outer
      end
      p deep.instance_variable_get(:@inner).class
      deep = nil
      GC.start
      p "released"
    RUBY

    _(result).must_answer <<~'OUT'
      200000
      false
      Link
      "released"
    OUT
  end

  it "definition ruby raises on is rescuable" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb")
      # `superclass mismatch` is an EXCEPTION in ruby, raised at the definition -- not
      # a broken program. A `begin ... rescue TypeError` around one catches it, prints,
      # and carries on, so a program that does that has to compile and do the same.
      #
      # Unrescued, zeo refuses the compile instead of emitting a program that aborts:
      # same problem, named earlier. That split is the whole point of this file -- the
      # rescued half is what a compile-time-only rejection would have made impossible.
      #
      # The KIND mismatch at the bottom is the same rule with a two-line message, and
      # both lines were wrong. `unmatched_redefinition` (vm_insnhelper.c) names the
      # LEAF -- `rb_id2str(id)`, the id off the cpath -- so `module Outer::Inner`
      # reports `Inner`, where zeo reported the qualified `Outer::Inner`. Then it
      # appends the previous definition's position, read from
      # `rb_const_source_location_at`: the point the CONSTANT was created, which is
      # the first declaring site, so a reopen leaves the first line standing. zeo
      # omitted that line entirely.

      class A; end
      class B < A; end

      # A cycle: `A < B` while `B < A`. Ruby raises rather than closing the loop --
      # and zeo must not build it either, because a superclass chain that points at
      # itself is an infinite walk for every pass that follows it.
      begin
        class A < B; end
      rescue TypeError => e
        p e.message
      end
      p A.superclass
      p B.superclass

      # A plain conflict: two different superclasses for one name.
      class D < String; end
      begin
        class D < Array; end
      rescue TypeError => e
        p e.message
      end
      p D.superclass

      # The definition RAISED, so it changed nothing -- the class is exactly what it
      # was, and the program keeps running.
      p D.new.class
      p B.new.is_a?(A)

      # --- the KIND mismatch, both directions -------------------------------------
      begin
        module D; end
      rescue TypeError => e
        p e.message
      end
      p D.superclass

      module M; end
      begin
        class M; end
      rescue TypeError => e
        p e.message
      end
      p M.class

      # The name reported is the LEAF, and the position is the first declaring site.
      module Outer
        class Inner; end
      end
      begin
        module Outer::Inner
        end
      rescue TypeError => e
        p e.message
      end

      # A REOPEN does not restamp the position: the line below is the one above.
      class Reopened; end
      class Reopened; end
      begin
        module Reopened; end
      rescue TypeError => e
        p e.message
      end

      # A builtin's constant carries no recorded position, and ruby prints the line
      # anyway -- with both fields empty.
      begin
        module String; end
      rescue TypeError => e
        p e.message
      end

      # A REOPEN creates no constant either, so a builtin a program reopened still
      # carries none.
      class Integer
        def doubled = self * 2
      end
      begin
        module Integer; end
      rescue TypeError => e
        p e.message
      end
      p 21.doubled

      p :after
    RUBY

    _(result).must_answer <<~'OUT'
      "superclass mismatch for class A"
      Object
      A
      "superclass mismatch for class D"
      String
      D
      true
      "D is not a module\nlang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb:33: previous definition of D was here"
      String
      "M is not a class\nlang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb:54: previous definition of M was here"
      Module
      "Inner is not a module\nlang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb:64: previous definition of Inner was here"
      "Reopened is not a module\nlang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb:74: previous definition of Reopened was here"
      "String is not a module\n:: previous definition of String was here"
      "Integer is not a module\n:: previous definition of Integer was here"
      42
      :after
    OUT
  end

  it "dollar bang reads the exception being handled" do
    result = ze0(<<~'RUBY')
      # `$!` is the current exception inside a rescue (block or modifier form),
      # nil outside one.

      p $!
      r = (Integer("x") rescue $!.class)
      p r
      begin
        raise "boom"
      rescue
        puts $!.message
      end
      p $!
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      ArgumentError
      boom
      nil
    OUT
  end

  it "dot class works on rescue bindings and poly receivers" do
    result = ze0(<<~'RUBY')
      begin
        raise "boom"
      rescue => e
        puts e.class
      end

      mixed = [1, "two", nil]
      mixed.each do |v|
        puts v.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      RuntimeError
      Integer
      String
      NilClass
    OUT
  end

  it "dup and clone of uncopyable handles raise cruby shapes" do
    result = ze0(<<~'RUBY')
      # The former loud-panic tier is real, rescuable raises now -- every
      # message verbatim from ruby 4.0.6. Fiber is the special one: CRuby's
      # shallow copy succeeds but skips the machine stack, so the COPY is an
      # uninitialized fiber (resume raises) while the original still runs.
      # Concurrent join/value on one Thread hands every joiner the outcome.

      begin; Thread.current.dup; rescue TypeError => e; puts "thread: #{e.message}"; end
      begin; Queue.new.clone; rescue NoMethodError => e; puts "queue: #{e.message}"; end
      begin; SizedQueue.new(1).dup; rescue NoMethodError => e; puts "sq: #{e.message}"; end
      g = Fiber.new { 42 }.dup
      begin; g.resume; rescue FiberError => e; puts "fiber: #{e.message}"; end
      f = Fiber.new { 7 }
      f.dup
      puts "orig: #{f.resume}"
      e = [1, 2].each
      e.next
      begin; e.dup; rescue TypeError => ex; puts "enum: #{ex.message}"; end
      t = Thread.new { sleep 0.05; :done }
      a = Thread.new { t.value }
      b = Thread.new { t.value }
      puts "joins: #{a.value} #{b.value}"
    RUBY

    _(result).must_answer <<~'OUT'
      thread: allocator undefined for Thread
      queue: undefined method 'initialize_copy' for an instance of Thread::Queue
      sq: undefined method 'initialize_copy' for an instance of Thread::SizedQueue
      fiber: uninitialized fiber
      orig: 7
      enum: can't copy execution context
      joins: done done
    OUT
  end

  it "else clause runs only on the no exception path" do
    result = ze0(<<~'RUBY')
      begin
        puts "body"
      rescue
        puts "rescued"
      else
        puts "else ran"
      ensure
        puts "ensure ran"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      body
      else ran
      ensure ran
    OUT
  end

  it "ensure runs when no exception is raised and there is no rescue at all" do
    result = ze0(<<~'RUBY')
      begin
        puts "no exception"
      ensure
        puts "ensure always"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      no exception
      ensure always
    OUT
  end

  it "env error shapes" do
    result = ze0(<<~'RUBY')
      # ENV's error shapes: a non-String key is a TypeError, a bare `fetch` miss
      # is a KeyError.

      begin
        ENV[:PATH]
      rescue TypeError => e
        puts "TypeError"
      end
      begin
        ENV.fetch("ZEO_DEFINITELY_ABSENT")
      rescue KeyError => e
        puts "KeyError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      KeyError
    OUT
  end

  it "errno messages name crubys call sites" do
    result = ze0(<<~'RUBY')
      # A SystemCallError message's `@ site` names CRuby's own C function, not
      # the syscall: `@ rb_sysopen`, `@ io_fread`, `@ dir_chdir0`,
      # `@ rb_check_realpath_internal`, `@ rb_file_s_stat`, `@ apply2files`, and
      # `@ rb_file_s_rename - (a, b)` with BOTH paths. zeo names the syscall
      # (`@ read`, `@ chdir`, ...). `File.expand_path("~nouser")` also words its
      # ArgumentError differently. (Found by the 2026-08-24 probe sweep.)
      def show
        yield
      rescue SystemCallError, ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
      show { File.read("/tmp") }
      show { Dir.chdir("/nonexistent_zeo_probe_xyz") { } }
      show { File.realpath("/nonexistent_zeo_probe_xyz") }
      show { File.stat("/nonexistent_zeo_probe_xyz") }
      show { File.delete("/nonexistent_zeo_probe_xyz") }
      show { File.rename("/nonexistent_zeo_probe_xyz", "/tmp/zzz") }
      show { File.expand_path("~xyz_no_such_user_probe") }
    RUBY

    _(result).must_answer <<~'OUT'
      Errno::EISDIR: Is a directory @ io_fread - /tmp
      Errno::ENOENT: No such file or directory @ dir_chdir0 - /nonexistent_zeo_probe_xyz
      Errno::ENOENT: No such file or directory @ rb_check_realpath_internal - /nonexistent_zeo_probe_xyz
      Errno::ENOENT: No such file or directory @ rb_file_s_stat - /nonexistent_zeo_probe_xyz
      Errno::ENOENT: No such file or directory @ apply2files - /nonexistent_zeo_probe_xyz
      Errno::ENOENT: No such file or directory @ rb_file_s_rename - (/nonexistent_zeo_probe_xyz, /tmp/zzz)
      ArgumentError: user xyz_no_such_user_probe doesn't exist
    OUT
  end

  it "errno sites name crubys c functions" do
    result = ze0(<<~'RUBY')
      # The `@ site` in a SystemCallError message names CRuby's own C FUNCTION,
      # not the syscall underneath it. `File.stat` says `rb_file_s_stat`,
      # `File.delete` says `apply2files` (the shared helper behind chmod, chown,
      # utime and unlink alike), and a two-path operation prints BOTH operands:
      # `... @ rb_file_s_rename - (from, to)`.
      #
      # Two rows are where the mapping stops being mechanical. `Dir.chdir` names
      # a DIFFERENT function per form -- `dir_chdir0` with a block, `chdir_path`
      # without -- and reading a DIRECTORY says `io_fread`, because CRuby opens
      # and then reads, and only the read can answer EISDIR. One native call covers
      # both steps, so that site is picked from the errno.
      #
      # `File.readlines(a_directory)` is deliberately absent: CRuby answers
      # `@ io_fillbuf - fd:6 <path>`, naming a buffered-read helper AND the raw
      # descriptor number, which is not reproducible across runs.

      require "tmpdir"
      D = Dir.mktmpdir
      M = File.join(D, "gone")
      E = File.join(D, "here")
      File.write(E, "hi")
      def show(n)
        yield
      rescue Exception => e
        puts "#{n}\t#{e.class}: #{e.message.gsub(D, '<T>')}"
      end
      show("atime") { File.atime(M) }
      show("ctime") { File.ctime(M) }
      show("birthtime") { File.birthtime(M) }
      show("lstat") { File.lstat(M) }
      show("stat") { File.stat(M) }
      show("size") { File.size(M) }
      show("mtime") { File.mtime(M) }
      show("truncate") { File.truncate(M, 0) }
      show("realdirpath") { File.realdirpath(M) }
      show("link") { File.link(E, E) }
      show("symlink") { File.symlink(E, E) }
      show("rename") { File.rename(M, E) }
      show("chmod") { File.chmod(0o600, M) }
      show("chown") { File.chown(nil, nil, M) }
      show("utime") { File.utime(Time.now, Time.now, M) }
      show("delete") { File.delete(M) }
      show("readlink") { File.readlink(M) }
      show("expand ~x") { File.expand_path("~xyz_no_user") }
      show("Dir.mkdir") { Dir.mkdir(D) }
      show("Dir.rmdir") { Dir.rmdir(M) }
      show("Dir.entries") { Dir.entries(M) }
      show("Dir.open") { Dir.open(M) }
      show("Dir.new") { Dir.new(M) }
      show("IO.read dir") { IO.read(D) }
      show("chdir no block") { Dir.chdir(M) }
      show("chdir block") { Dir.chdir(M) { 1 } }
      show("File.read dir") { File.read(D) }
      show("File.open missing") { File.open(M) }
      show("File.write dir") { File.write(D, "x") }
    RUBY

    _(result).must_answer <<~'OUT'
      atime	Errno::ENOENT: No such file or directory @ rb_file_s_atime - <T>/gone
      ctime	Errno::ENOENT: No such file or directory @ rb_file_s_ctime - <T>/gone
      birthtime	Errno::ENOENT: No such file or directory @ rb_file_s_birthtime - <T>/gone
      lstat	Errno::ENOENT: No such file or directory @ rb_file_s_lstat - <T>/gone
      stat	Errno::ENOENT: No such file or directory @ rb_file_s_stat - <T>/gone
      size	Errno::ENOENT: No such file or directory @ rb_file_s_size - <T>/gone
      mtime	Errno::ENOENT: No such file or directory @ rb_file_s_mtime - <T>/gone
      truncate	Errno::ENOENT: No such file or directory @ rb_file_s_truncate - <T>/gone
      link	Errno::EEXIST: File exists @ syserr_fail2_in - <T>/here
      symlink	Errno::EEXIST: File exists @ syserr_fail2_in - <T>/here
      rename	Errno::ENOENT: No such file or directory @ rb_file_s_rename - (<T>/gone, <T>/here)
      chmod	Errno::ENOENT: No such file or directory @ apply2files - <T>/gone
      chown	Errno::ENOENT: No such file or directory @ apply2files - <T>/gone
      utime	Errno::ENOENT: No such file or directory @ apply2files - <T>/gone
      delete	Errno::ENOENT: No such file or directory @ apply2files - <T>/gone
      readlink	Errno::ENOENT: No such file or directory @ rb_readlink - <T>/gone
      expand ~x	ArgumentError: user xyz_no_user doesn't exist
      Dir.mkdir	Errno::EEXIST: File exists @ dir_s_mkdir - <T>
      Dir.rmdir	Errno::ENOENT: No such file or directory @ dir_s_rmdir - <T>/gone
      Dir.entries	Errno::ENOENT: No such file or directory @ dir_initialize - <T>/gone
      Dir.open	Errno::ENOENT: No such file or directory @ dir_initialize - <T>/gone
      Dir.new	Errno::ENOENT: No such file or directory @ dir_initialize - <T>/gone
      IO.read dir	Errno::EISDIR: Is a directory @ io_fread - <T>
      chdir no block	Errno::ENOENT: No such file or directory @ chdir_path - <T>/gone
      chdir block	Errno::ENOENT: No such file or directory @ dir_chdir0 - <T>/gone
      File.read dir	Errno::EISDIR: Is a directory @ io_fread - <T>
      File.open missing	Errno::ENOENT: No such file or directory @ rb_sysopen - <T>/gone
      File.write dir	Errno::EISDIR: Is a directory @ rb_sysopen - <T>
    OUT
  end

  it "eval of invalid literal source raises a catchable syntax error" do
    _(ze0(<<~'RUBY')).must_answer "caught\n"
      # A literal `eval("...")` whose source doesn't parse does not fail the
      # COMPILE: it falls through to the runtime `eval` and raises a catchable
      # SyntaxError, exactly as CRuby does.

      begin; eval("1 +"); rescue SyntaxError; puts "caught"; end
    RUBY
  end

  it "eval syntax error is catchable at runtime" do
    _(ze0(<<~'RUBY')).must_answer "caught\n"
      bad = "1 +"
      begin
        eval(bad)
      rescue SyntaxError
        puts "caught"
      end
    RUBY
  end

  it "exception attributes raise when unset and private call flag" do
    result = ze0(<<~'RUBY')
      # KeyError#key / #receiver and NameError#receiver raise ArgumentError when
      # never set, but a real miss (nil.foo, h.fetch) sets them. NoMethodError's
      # 4th positional is the private_call? flag.

      p((begin; KeyError.new("m").key; rescue => e; e.class; end))
      p((begin; KeyError.new("m").receiver; rescue => e; e.class; end))
      p((begin; NoMethodError.new("m").receiver; rescue => e; e.class; end))
      p((begin; NameError.new("m", :n).receiver; rescue => e; e.class; end))
      p((begin; KeyError.new("m", key: :k, receiver: {}).key; rescue => e; e.class; end))
      p((begin; nil.foo; rescue => e; e.receiver; end))
      h = { a: 1 }
      p((begin; h.fetch(:z); rescue => e; e.key; end))
      p NoMethodError.new("m", :nm, [1], true).private_call?
      p NoMethodError.new("m", :nm, [1]).private_call?
      p NoMethodError.new("m", :nm, [1, 2]).args
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      :k
      nil
      :z
      true
      false
      [1, 2]
    OUT
  end

  it "exception cause chains from active rescue" do
    result = ze0(<<~'RUBY')
      begin
        begin
          raise "inner"
        rescue
          raise "outer"
        end
      rescue => e
        puts e.message
        puts e.cause.message
        puts e.cause.class
      end
      begin
        raise "solo"
      rescue => e
        p e.cause
      end
      begin
        begin
          Integer("x")
        rescue
          raise ArgumentError, "wrapped"
        end
      rescue => e
        puts e.cause.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      outer
      inner
      RuntimeError
      nil
      ArgumentError
    OUT
  end

  it "exception class new" do
    result = ze0(<<~'RUBY')
      # Phase 1C: built-in exception class `.new("msg")`.
      # `RuntimeError.new(...)`, `ArgumentError.new(...)` etc. previously
      # emitted an undefined `sp_RuntimeError` type (the analyze inferred
      # obj_RuntimeError but no struct backed it). Spinel now models
      # built-in exception objects as their message string plus a
      # side-channel cls name -- the same convention `rescue => e` uses.
      #
      # Covers (Phase 1C):
      #   - CLS.new("msg") with various exception classes
      #   - .class returns the class name (string in spinel)
      #   - .message returns the msg
      #   - .is_a? walks the hierarchy
      #
      # Covers (Phase 1D):
      #   - raise <exception_object> -- raise a pre-built exc
      #   - raise CLS.new("msg") -- raise an inline-constructed exc

      err = RuntimeError.new("created")
      puts err.class                     # RuntimeError
      puts err.message                   # created
      puts err.is_a?(RuntimeError)       # true
      puts err.is_a?(StandardError)      # true
      puts err.is_a?(Exception)          # true

      # raise the saved object
      begin
        raise err
      rescue => e
        puts "caught: #{e.class}: #{e.message}"
      end

      # raise an inline-constructed exception (1D)
      begin
        raise ArgumentError.new("inline ae")
      rescue => e
        puts "inline: #{e.class}: #{e.message}"
      end

      # StandardError subclass with .new
      e2 = TypeError.new("bad type")
      puts e2.class                      # TypeError
      puts e2.message                    # bad type

      # Various built-in exception classes
      e3 = NoMethodError.new("missing")
      puts e3.class                      # NoMethodError
    RUBY

    _(result).must_answer <<~'OUT'
      RuntimeError
      created
      true
      true
      true
      caught: RuntimeError: created
      inline: ArgumentError: inline ae
      TypeError
      bad type
      NoMethodError
    OUT
  end

  it "exception equality exception method and message coercion" do
    result = ze0(<<~'RUBY')
      e = RuntimeError.new("m")
      e2 = RuntimeError.new("m")
      p e == e2
      p e == RuntimeError.new("other")
      p e == "not an exception"
      p e.eql?(e)
      p e.eql?(e2)
      p e.exception.equal?(e)
      p e.exception("n").message
      p e.exception("n").equal?(e)
      p RuntimeError.exception("z").message
      p RuntimeError.exception("z").class
      p RuntimeError.new(42).message
      p RuntimeError.new(:sym).message
      p ArgumentError.new([1, 2]).message
      p [true, false].include?(Exception.to_tty?)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      false
      true
      "n"
      false
      "z"
      RuntimeError
      "42"
      "sym"
      "[1, 2]"
      true
    OUT
  end

  it "exception messages" do
    result = ze0(<<~'RUBY')
      # An exception's message comes from its own `initialize`/`to_s` chain, so
      # `raise SomeError` (no message) must actually RUN the class's constructor --
      # defaults, `super` and all -- rather than short-cutting to the class name.
      # The class-name default lives in Exception#to_s (`@message || self.class.name`).

      # Bare `super` forwards the defaulted parameter.
      class E < StandardError
        def initialize(m = "def")
          super
        end
      end
      begin; raise E; rescue => e; p e.message; end
      begin; raise E, "x"; rescue => e; p e.message; end
      begin; raise E.new; rescue => e; p e.message; end
      begin; raise E.new("y"); rescue => e; p e.message; end

      # `super("...")` with interpolation, raised argless.
      class F < StandardError
        def initialize(m = "dd")
          super("wrapped: #{m}")
        end
      end
      begin; raise F; rescue => e; p e.message; end
      begin; raise F, "given"; rescue => e; p e.message; end

      # No custom initialize: the message defaults to the class name.
      class G < StandardError; end
      begin; raise G; rescue => e; p e.message; end
      begin; raise G, "explicit"; rescue => e; p e.message; end

      # An inherited user initialize from a user parent.
      class Base < StandardError
        def initialize(m = "base-def")
          super
        end
      end
      class Sub < Base; end
      begin; raise Sub; rescue => e; p e.message; end

      # A custom initialize that also sets an ivar, raised argless.
      class H < StandardError
        def initialize(m = "oops", code = 42)
          @code = code
          super(m)
        end
        attr_reader :code
      end
      begin; raise H; rescue => e; p [e.message, e.code]; end
      begin; raise H.new("boom", 7); rescue => e; p [e.message, e.code]; end

      # Built-in raises are unaffected.
      begin; raise StandardError; rescue => e; p e.message; end
      begin; raise "boom"; rescue => e; p e.message; end
      begin; raise ArgumentError; rescue => e; p e.message; end
      begin; raise ArgumentError, "bad arg"; rescue => e; p e.message; end
      begin; raise RuntimeError.new("built"); rescue => e; p e.message; end

      # to_s and message agree, and inspect/class read correctly.
      begin
        raise E
      rescue => e
        p e.to_s
        p e.message
        p e.class
        p e.class.name
        p e.is_a?(StandardError)
      end

      # An exception with a custom to_s: message follows it (message calls to_s).
      class Custom < StandardError
        def to_s
          "custom-to-s"
        end
      end
      begin; raise Custom; rescue => e; p [e.message, e.to_s]; end

      # A message built from an ivar the constructor set.
      class Detailed < StandardError
        def initialize(field)
          @field = field
          super("invalid #{field}")
        end
        attr_reader :field
      end
      begin
        raise Detailed.new("email")
      rescue Detailed => e
        p [e.message, e.field]
      end

      # Re-raising preserves the same object, message and ivars.
      begin
        begin
          raise Detailed.new("name")
        rescue Detailed
          raise
        end
      rescue => e
        p [e.message, e.field]
      end

      # A rescued exception's message survives being stored and re-inspected.
      saved = nil
      begin; raise E; rescue => e; saved = e; end
      p saved.message
    RUBY

    _(result).must_answer <<~'OUT'
      "def"
      "x"
      "def"
      "y"
      "wrapped: dd"
      "wrapped: given"
      "G"
      "explicit"
      "base-def"
      ["oops", 42]
      ["boom", 7]
      "StandardError"
      "boom"
      "ArgumentError"
      "bad arg"
      "built"
      "def"
      "def"
      E
      "E"
      true
      ["custom-to-s", "custom-to-s"]
      ["invalid email", "email"]
      ["invalid name", "name"]
      "def"
    OUT
  end

  it "exception override message unqueried" do
    result = ze0(<<~'RUBY')
      class Ov7 < StandardError
        def message; "overridden"; end
      end
      begin; raise Ov7; rescue Ov7 => x; end
      p :done
      begin; raise Ov7; rescue => y; p y.message; end
      p(Ov7.new.message)
    RUBY

    _(result).must_answer <<~'OUT'
      :done
      "overridden"
      "overridden"
    OUT
  end

  it "exception reopen" do
    result = ze0(<<~'RUBY')
      # Reopening the native exception hierarchy and the builtin modules (D3).
      # The exception prelude lives natively, yet stays fully open: a reopen
      # ADDS a method reaching every subclass and OVERRIDES an existing one
      # everywhere, and a builtin module reopen reaches every includer.

      # --- add a method to the whole exception tree ---
      class Exception
        def tag
          "[#{self.class.name}]"
        end
      end

      # --- override a native method; it wins for every subclass ---
      class StandardError
        def message
          "handled: " + to_s
        end
      end

      begin
        raise ArgumentError, "bad value"
      rescue => e
        puts e.tag
        puts e.message
        puts e.is_a?(StandardError)
      end

      # CRuby stores the message in a hidden slot, not a @message ivar.
      begin
        raise "plain"
      rescue => e
        p e.instance_variables
        puts e.message
      end

      # --- reopen a builtin MODULE: reaches every includer ---
      module Enumerable
        def second
          first(2).last
        end
      end

      puts [10, 20, 30].second
      puts({ "a" => 1, "b" => 2 }.map { |_k, v| v }.second)

      # --- reopen restating the real superclass ---
      class String < Object
        def shout
          upcase + "!"
        end
      end
      puts "hi".shout
    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError]
      handled: bad value
      true
      []
      handled: plain
      20
      2
      HI!
    OUT
  end

  it "expr retry equal curry methodobj" do
    result = ze0(<<~'RUBY')
      # p(multi) / loop as expressions, retry with ensure, Array/Hash#equal?,
      # curry[a, b] multi-arg application, and &method(:kernel_builtin) procs.
      x = p(1, 2)
      p x
      y = p(5)
      p y
      z = loop { break }
      p z
      w = loop { break 42 }
      p w
      c = true
      begin
        raise "x"
      rescue
        (c = false; retry) if c
      ensure
        puts "ens"
      end
      puts "done"
      i = 0
      begin
        i += 1
        raise "boom" if i < 3
        puts "body done #{i}"
      rescue
        retry
      ensure
        puts "ens #{i}"
      end
      r = begin
        raise "x"
      rescue
        retry_done ||= 0
        retry_done += 1
        retry_done < 2 ? retry : "recovered"
      ensure
        puts "ens2"
      end
      p r
      a = [1, 2]
      b = a
      p a.equal?(b)
      p a.equal?([1, 2])
      s = "x"
      p s.equal?(s)
      h = { a: 1 }
      p h.equal?(h)
      add132 = proc { |a, b, c| a + b + c }
      p(add132.curry[1, 2][3])
      p(add132.curry[1][2][3])
      p(add132.curry[1, 2, 3])
      p([1, 2, 3].map(&method(:Integer)))
      p(["1", "2"].map(&method(:Integer)))
      p([1.7, 2.2].map(&method(:Integer)))
      m = method(:puts)
      m.call("hi")
      def shout(s); puts s; end
      m = method(:shout)
      m.call("hi")
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      [1, 2]
      5
      5
      nil
      42
      ens
      done
      body done 3
      ens 3
      ens2
      "recovered"
      true
      false
      true
      true
      6
      6
      6
      [1, 2, 3]
      [1, 2]
      [1, 2]
      hi
      hi
    OUT
  end

  it "instance eval rescue modifier" do
    result = ze0(<<~'RUBY')
      # An instance_eval/exec splice as the EXPRESSION of a rescue modifier (#2723):
      # the expression arm's own preludes must land inside the protected region, and
      # the splice temp's seeded type must survive the write pass's per-iteration
      # reset (users of the temp precede its synthesized write in node order).
      r = ("abc".instance_eval { upcase } rescue $!.class)
      p r
      r2 = ("ab".instance_exec(3) { |n| self * n } rescue $!.class)
      p r2
      r3 = (5.instance_eval { self + 1 } rescue :nope)
      p r3
      # a raise out of the spliced body reaches the enclosing handler with its
      # message: the splice rides a ParenthesesNode, not a BeginNode, whose own
      # exception region would swallow it
      r4 = ("x".instance_eval { raise "boom" } rescue :rescued)
      p r4
      r5 = ("x".instance_eval { raise "boom" } rescue $!.message)
      p r5
    RUBY

    _(result).must_answer <<~'OUT'
      "ABC"
      "ababab"
      6
      :rescued
      "boom"
    OUT
  end

  it "invalid attribute name is a name error" do
    result = ze0(<<~'RUBY')
      # `attr_accessor`/`attr_reader`/`attr_writer` validate the name ("invalid
      # attribute name '1bad'"); zeo accepts anything and mints :"1bad" rows,
      # which then leak into instance_methods. (Found by the 2026-08-24 probe
      # sweep.)
      c = Class.new
      begin
        c.send(:attr_accessor, "1bad")
      rescue NameError => e
        puts e.message
      end
      p c.instance_methods(false)
    RUBY

    _(result).must_answer <<~'OUT'
      invalid attribute name '1bad'
      []
    OUT
  end

  it "join separator slot" do
    result = ze0(<<~'RUBY')
      # `join`'s separator is a NILABLE String slot: nil is legal and means "" (it
      # is `$,`'s default), false and every other class are a TypeError. The
      # emitters passed the argument into the const char* slot raw, so both spellings
      # reached the join as a NULL and it read that as a string -- a segfault either
      # way, for every array kind (found reviewing PR #4029, whose sweep did not
      # reach this slot).
      def try
        yield
      rescue => e
        p [e.class, e.message]
      end

      p [1, 2].join(nil)
      p ["a", "b"].join(nil)
      p [1.5, 2.5].join(nil)
      p [[1], [2]].join(nil)
      p [1, [2, 3]].join(nil)
      p([:a, :b].join(nil))
      sep = nil
      p [1, 2].join(sep)
      p [1, 2].join
      p [1, 2].join("-")
      p ["a", "b"].join("")

      try { [1, 2].join(false) }
      try { [1, 2].join(true) }
      try { [1, 2].join(1) }
      try { ["a"].join(:x) }

      # through a poly receiver, where the array kind is a run-time question
      def pick(f) = f ? [1, 2] : "s"
      p pick(true).join(nil)
      try { pick(true).join(false) }
    RUBY

    _(result).must_answer <<~'OUT'
      "12"
      "ab"
      "1.52.5"
      "12"
      "123"
      "ab"
      "12"
      "12"
      "1-2"
      "ab"
      [TypeError, "no implicit conversion of false into String"]
      [TypeError, "no implicit conversion of true into String"]
      [TypeError, "no implicit conversion of Integer into String"]
      [TypeError, "no implicit conversion of Symbol into String"]
      "12"
      [TypeError, "no implicit conversion of false into String"]
    OUT
  end

  it "method of an unknown name raises name error at construction" do
    result = ze0(<<~'RUBY')
      begin
        "str".method(:definitely_not_defined)
      rescue NameError => e
        puts e.message
      end
      class WithPrivate
        private
        def secret = "shh"
      end
      p WithPrivate.new.method(:secret).call
    RUBY

    _(result).must_answer <<~'OUT'
      undefined method 'definitely_not_defined' for class 'String'
      "shh"
    OUT
  end

  it "method undefined name error" do
    result = ze0(<<~'RUBY')
      # Object#method / #public_method with an undefined name raise NameError
      # immediately; a defined name still returns a callable Method.
      r = (true.method(:nope) rescue $!.class); p r
      r2 = ("s".method(:zzz) rescue $!.class); p r2
      r3 = ([1].method(:qqq) rescue $!.class); p r3
      r4 = (nil.method(:blah) rescue $!.class); p r4
      m = "abc".method(:upcase)
      p m.class
      p m.call
      class UU; def go; 7; end; end
      r5 = (UU.new.method(:nope2) rescue $!.class); p r5
      p UU.new.method(:go).call
      r6 = (5.public_method(:nope3) rescue $!.class); p r6
    RUBY

    _(result).must_answer <<~'OUT'
      NameError
      NameError
      NameError
      NameError
      Method
      "ABC"
      NameError
      7
      NameError
    OUT
  end

  it "multi line exception message keeps its class tag on line one" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/a_multi_line_exception_message_keeps_its_class_tag_on_line_one.rb")
      # CRuby's uncaught-exception report puts the class tag at the end of the
      # message's FIRST line and lets the rest run underneath, unindented -- the
      # `error_pos`/`print_errinfo` split. zeo appended it after the whole message,
      # which nothing noticed while the only multi-line messages came from
      # constructs that failed to compile.
      #
      # A kind collision is exactly that shape: `X is not a class` on one line and
      # `<file>:<line>: previous definition of X was here` on the next.
      raise ArgumentError, "first\nsecond\nthird"
    RUBY

    _(result).must_answer "", stderr: "lang/exceptions/a_multi_line_exception_message_keeps_its_class_tag_on_line_one.rb:9:in '<main>': first (ArgumentError)\nsecond\nthird\n\nraise ArgumentError, \"first\\nsecond\\nthird\"\n      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n", status: 1
  end

  it "native exception hides its message ivar" do
    result = ze0(<<~'RUBY')
      # A raised native exception exposes NO `@message` ivar (CRuby stores it in a
      # hidden slot): `instance_variables` is empty and `@message` reads nil.

      begin
        raise ArgumentError, "boom"
      rescue => e
        p e.instance_variables
        p e.instance_variable_get(:@message)
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      []
      nil
      boom
    OUT
  end

  it "nested begin ensure runs inner before outer" do
    result = ze0(<<~'RUBY')
      begin
        begin
          puts "inner body"
        ensure
          puts "inner ensure"
        end
      ensure
        puts "outer ensure"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      inner body
      inner ensure
      outer ensure
    OUT
  end

  it "no matching pattern error message" do
    result = ze0(<<~'RUBY')
      # `NoMatchingPatternError` names the value and the test that failed:
      #
      #     1: String === 1 does not return true
      #
      # zeo raises the same class with the message "no matching pattern", which says
      # only that something did not match.
      #
      # The detail is the whole diagnostic. A `case/in` with several branches, each
      # with nested sub-patterns, gives no other clue about WHICH branch got closest
      # or which sub-test rejected the value -- ruby's message points straight at it,
      # and that is why the message was given this shape (Bug #17925) rather than
      # staying generic.
      #
      # `NoMatchingPatternKeyError` carries the same information structurally, in
      # `#key` and `#matchee`, which zeo does answer -- so the data is present and
      # only the `NoMatchingPatternError` message is not built from it.

      begin
        case 1
        in String then :never
        end
      rescue NoMatchingPatternError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        case { a: 1 }
        in { a: String } then :never
        end
      rescue NoMatchingPatternError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        case [1, 2]
        in [Integer, String] then :never
        end
      rescue NoMatchingPatternError => e
        puts "#{e.class}: #{e.message}"
      end

      # The key error already carries its detail.
      begin
        { a: 1 } => { b: }
      rescue NoMatchingPatternKeyError => e
        puts "#{e.class}: key=#{e.key.inspect} matchee=#{e.matchee.inspect}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      NoMatchingPatternError: 1: String === 1 does not return true
      NoMatchingPatternError: {a: 1}: String === 1 does not return true
      NoMatchingPatternError: [1, 2]: String === 2 does not return true
      NoMatchingPatternKeyError: key=:b matchee={a: 1}
    OUT
  end

  it "nomethod raises on every receiver" do
    result = ze0(<<~'RUBY')
      # An undefined method raises a rescuable NoMethodError wherever CRuby does:
      # an Array/Hash/Symbol literal and a user-class instance were refused at
      # compile time, so a program that only reaches the call behind a rescue could
      # not be built at all (#3811).
      p(begin; [1].nope; rescue NoMethodError => e; e.receiver; end)
      p(begin; :s.nope; rescue NoMethodError => e; e.message; end)
      p(begin; ({ a: 1 }).nope; rescue NoMethodError => e; e.name; end)
      class Plain; end
      p(begin; Plain.new.nope; rescue NoMethodError => e; e.message; end)
      xs = [1, 2]
      p(begin; xs.nope; rescue NoMethodError => e; e.message; end)
      p(begin; (1..3).nope; rescue NoMethodError => e; e.message; end)
      p(begin; nil.nope; rescue NoMethodError => e; e.message; end)
      p(begin; "s".nope; rescue NoMethodError => e; e.message; end)
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      "undefined method 'nope' for an instance of Symbol"
      :nope
      "undefined method 'nope' for an instance of Plain"
      "undefined method 'nope' for an instance of Array"
      "undefined method 'nope' for an instance of Range"
      "undefined method 'nope' for nil"
      "undefined method 'nope' for an instance of String"
    OUT
  end

  it "nomethod receiver parens" do
    result = ze0(<<~'RUBY')
      r001 = (begin; ({a: 1}).nope; rescue NoMethodError => e001; e001.receiver; end); p r001

      p(begin; ({}).nope; rescue NoMethodError => e; e.receiver; end)
      # Ruby: {}   Spinel: nil
      p(begin; ({"x" => 1}).nope; rescue NoMethodError => e; e.receiver; end)
      # Ruby: {"x" => 1}   Spinel: nil
      p(begin; ({a: 1}).nope; rescue NoMethodError => e; e.receiver.class; end)
      # Ruby: Hash   Spinel: NilClass

      h = {a: 1}
      p(begin; h.nope; rescue NoMethodError => e; e.receiver; end)      # => {a: 1}
      p(begin; ({a: 1}).nope; rescue NoMethodError => e; e.name; end)   # => :nope
      p(begin; ({a: 1}).nope; rescue NoMethodError => e; e.message; end)
      #   => "undefined method 'nope' for an instance of Hash"
      p(begin; [1].nope; rescue NoMethodError => e; e.receiver; end)    # => [1]
      p(begin; :s.nope; rescue NoMethodError => e; e.receiver; end)     # => :s
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1}
      {}
      {"x" => 1}
      Hash
      {a: 1}
      :nope
      "undefined method 'nope' for an instance of Hash"
      [1]
      :s
    OUT
  end

  it "pattern key error class" do
    result = ze0(<<~'RUBY')
      # A hash pattern that misses a KEY raises `NoMatchingPatternKeyError` in CRuby,
      # carrying the key it wanted and the Hash it was asked of. zeo raised the parent
      # `NoMatchingPatternError` with no detail.
      #
      # A pattern compiles to ONE boolean, so by the time the `expr => pattern` arm
      # raises, the expression tree that knew which key was absent is gone. The miss
      # is recorded where it happens and read back at the raise
      # (`zeo_rt::pattern_match_error`), and the record is cleared at the start of
      # every required match so a `case/in` arm that simply did not apply cannot leak
      # into a later failure.
      #
      # A key that is PRESENT with a non-matching value is a different failure and
      # keeps the parent class, which is why the two are kept apart at the check.

      def t(label)
        yield
        puts "#{label}: no raise"
      rescue NoMatchingPatternError => e
        key = e.respond_to?(:key) ? e.key.inspect : "-"
        matchee = e.respond_to?(:matchee) ? e.matchee.inspect : "-"
        puts "#{label}: #{e.class} key=#{key} matchee=#{matchee}"
      end

      t("missing key") { { a: 1 } => { b: } }
      t("missing, several") { { a: 1 } => { a:, b:, c: } }

      # A NESTED miss names the inner key and the inner hash -- but the message still
      # quotes the outermost subject.
      t("nested missing") { { a: { b: 1 } } => { a: { c: } } }

      # Everything that is not a missing key stays the parent class.
      t("wrong value") { { a: 1 } => { a: 2 } }
      t("array length") { [1] => [1, 2] }
      t("not a hash") { 5 => { a: } }

      # A match that SUCCEEDS leaves nothing behind for the next one to read.
      t("ok") { { a: 1 } => { a: } }
      t("after ok") { { a: 1 } => { z: } }

      # ...and neither does a `case/in` arm that merely did not apply: the array
      # failure below must not report itself as a key error.
      t("case then array fail") do
        case { a: 1 }
        in { q: } then :q
        in { a: } then :a
        end
        [1] => [1, 2]
      end

      # `case/in` itself never raises the key error -- a missing key just means that
      # arm does not match.
      result = case { a: 1 }
               in { b: } then :b
               in { a: } then :a
               end
      p result

      begin
        case { a: 1 }
        in { b: } then :b
        end
      rescue NoMatchingPatternError => e
        p e.class
      end

      p NoMatchingPatternKeyError.ancestors.include?(NoMatchingPatternError)
      p NoMatchingPatternKeyError.new(matchee: { a: 1 }, key: :b).key
    RUBY

    _(result).must_answer <<~'OUT'
      missing key: NoMatchingPatternKeyError key=:b matchee={a: 1}
      missing, several: NoMatchingPatternKeyError key=:b matchee={a: 1}
      nested missing: NoMatchingPatternKeyError key=:c matchee={b: 1}
      wrong value: NoMatchingPatternError key=- matchee=-
      array length: NoMatchingPatternError key=- matchee=-
      not a hash: NoMatchingPatternError key=- matchee=-
      ok: no raise
      after ok: NoMatchingPatternKeyError key=:z matchee={a: 1}
      case then array fail: NoMatchingPatternError key=- matchee=-
      :a
      NoMatchingPatternKeyError
      true
      :b
    OUT
  end

  it "pattern naming an undefined constant raises name error when tried" do
    _(ze0(<<~'RUBY')).must_answer "NameError: uninitialized constant NopeClass\n"
      x = 5
      r = begin
        case x
        in NopeClass then "a"
        else "b"
        end
      rescue => e
        "#{e.class}: #{e.message}"
      end
      puts r
    RUBY
  end

  it "poly length size nomethod" do
    result = ze0(<<~'RUBY')
      # `length` / `size` on a boxed receiver that has neither: the poly length
      # helper answered 0 for nil, a number and a user object, so a nil read out of
      # a hash miss answered 0 where CRuby raises NoMethodError (#3974).
      def probe(v)
        begin
          v.length
        rescue NoMethodError => e
          "raise: #{e.message}"
        end
      end
      p probe(nil)
      p probe("abc")
      p probe([1, 2])
      p probe({ a: 1 })
      p probe(5)
      p probe(:sym)
      def psize(v)
        begin
          v.size
        rescue NoMethodError => e
          "raise: #{e.message}"
        end
      end
      p psize(nil)
      p psize(5)
      p psize("abc")
      p psize([1, 2])
    RUBY

    _(result).must_answer <<~'OUT'
      "raise: undefined method 'length' for nil"
      3
      2
      1
      "raise: undefined method 'length' for an instance of Integer"
      3
      "raise: undefined method 'size' for nil"
      8
      3
      2
    OUT
  end

  it "poly receiver call with unknown keyword raises at runtime" do
    _(ze0(<<~'RUBY')).must_answer "no method, kwargs carried\n"
      # The other old silent-drop site: kwargs on a Poly receiver now ride
      # the G2 convention; an undefined method stays a real NoMethodError.

      begin
        raise "boom"
      rescue => e
        begin
          e.foo(bar: 1)
        rescue NoMethodError
          puts "no method, kwargs carried"
        end
      end
    RUBY
  end

  it "poly recv int iterators" do
    result = ze0(<<~'RUBY')
      # times / upto / downto with a block, on a receiver only known to be an
      # Integer at run time. The arm that unboxes a boxed receiver and re-dispatches
      # through the typed Integer emitters only ever ran for the BLOCKLESS names, so
      # these raised NoMethodError naming Integer, the class that defines them.
      def pick(n) = n > 0 ? 3 : "x"

      v = pick(1)
      acc = []
      v.times { |i| acc << i }
      v.upto(5) { |i| acc << i }
      v.downto(1) { |i| acc << i }
      p acc

      # each answers the receiver, and a break value is still the call's value
      p v.times { |i| i }
      p v.upto(5) { |i| i }
      p v.downto(1) { |i| i }
      p(v.times { |i| break i * 10 if i == 2 })

      # a receiver that is not an Integer answers NoMethodError, as CRuby does --
      # the plain coercion the blockless names use would have run the loop zero
      # times instead
      begin
        pick(0).times { |i| p i }
      rescue NoMethodError => e
        p e.message
      end

      # and nil short-circuits through a safe-nav guard
      def maybe(n) = n > 0 ? 3 : nil
      [1, 0].each do |k|
        w = maybe(k)
        p w&.times { |i| i }
        p w&.upto(5) { |i| i }
        p w&.downto(1) { |i| i }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 2, 3, 4, 5, 3, 2, 1]
      3
      3
      3
      20
      "undefined method 'times' for an instance of String"
      3
      3
      3
      nil
      nil
      nil
    OUT
  end

  it "poly sign predicate user zero" do
    result = ze0(<<~'RUBY')
      # A user class defining zero? claims the name, so every call on a poly receiver
      # goes through the class dispatch. A Float or Integer arriving at that same call
      # site still has to answer its own sign from the runtime tag - the dispatch used
      # to fall through to the empty default and report false for every number.

      class Meter
        def initialize(n) = @n = n
        def zero? = @n == 0
      end

      def zero(v) = v.zero?
      def zero_via(pair) = zero(pair[1])

      puts zero_via([:m, Meter.new(5)])
      puts zero_via([:m, Meter.new(0)])
      puts zero_via([:m, 0.004])
      puts zero_via([:m, 0.0])
      puts zero_via([:m, 3])
      puts zero_via([:m, 0])

      # A tag with no sign raises NoMethodError, the same as CRuby.
      begin
        puts zero_via([:m, "abc"])
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      false
      true
      NoMethodError
    OUT
  end

  it "prepend on builtin exception ignored" do
    result = ze0(<<~'RUBY')
      module Wrap
        def detailed_message(highlight: true, **)
          "[" + super + "]"
        end
      end

      NoMethodError.prepend(Wrap)

      begin
        "abc".lenght
      rescue NoMethodError => e
        p e.detailed_message(highlight: false)
      end
    RUBY

    _(result).must_answer "\"[undefined method 'lenght' for an instance of String (NoMethodError)\\n\\n  \\\"abc\\\".lenght\\n       ^^^^^^^\\nDid you mean?  length]\"\n"
  end

  it "private method called with an explicit receiver raises at runtime" do
    result = ze0(<<~'RUBY')
      # A visibility violation is RUNTIME behavior in Ruby, not a syntax
      # error: it raises NoMethodError when the call actually runs, so it can
      # be rescued and an unreachable one stays silent. Message shape and
      # both behaviors oracle-verified.

      class Box
        def initialize
          @x = 1
        end

        private

        def helper
          2
        end
      end

      b = Box.new
      begin
        b.helper
      rescue NoMethodError => e
        puts e.message
      end

      def never_runs(b)
        b.helper
      end
      puts "still here"
    RUBY

    _(result).must_answer <<~'OUT'
      private method 'helper' called for an instance of Box
      still here
    OUT
  end

  it "protected method called from outside any related class raises at runtime" do
    _(ze0(<<~'RUBY')).must_answer "protected method 'amount' called for an instance of Money\n"
      # Same rule as the private case above -- a runtime NoMethodError.

      class Money
        def initialize(amount)
          @amount = amount
        end

        protected

        def amount
          @amount
        end
      end

      a = Money.new(10)
      begin
        a.amount
      rescue NoMethodError => e
        puts e.message
      end
    RUBY
  end

  it "raise cause and backrefs" do
    result = ze0(<<~'RUBY')
      # Three lowering gaps that CRuby resolves differently than a naive compiler
      # would: an explicit `cause:`, the `$+` backreference, and adjacent
      # interpolated string literals.

      # 1. `raise ..., cause:` is genuinely THREE-state. An omitted cause: chains
      #    automatically from $!; `cause: nil` SUPPRESSES that chaining; a value
      #    installs it. The first two mean opposite things, so they cannot share a
      #    representation.
      def blow(m); raise "top", cause: ArgumentError.new(m); end
      begin
        blow("root")
      rescue => e
        p e.cause
        puts e.message
      end

      begin
        begin
          raise ArgumentError, "inner"
        rescue ArgumentError
          raise "outer"
        end
      rescue => e
        p e.cause          # implicit chaining still applies
      end

      begin
        begin
          raise ArgumentError, "inner2"
        rescue ArgumentError
          raise "outer2", cause: nil
        end
      rescue => e
        p e.cause          # nil -- explicitly suppressed
      end

      begin
        raise "x", cause: 5
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end

      begin
        a = RuntimeError.new("a")
        b = RuntimeError.new("b")
        begin
          raise a, cause: b
        rescue; end
        raise b, cause: a
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end

      # 2. `$+` is the highest-numbered group that actually PARTICIPATED, skipping
      #    declared-but-unmatched ones, and is nil when only group 0 matched.
      "abc123" =~ /([a-z]+)(\d+)/
      puts $1
      puts $2
      puts $+
      "abc" =~ /([a-z]+)(\d+)?/
      puts $1
      puts $+           # steps back to the group that did match
      "xyz" =~ /xyz/
      p $+              # nil -- $+ never reports the whole match
      "b" =~ /(a)|(b)|(c)/
      p $+

      # 3. Backslash-continued adjacent literals parse as an interpolated string
      #    whose own parts are interpolated strings, so parts must flatten.
      def svg(px, inner)
        "<a width='#{px}' " \
        "height='#{px}'>#{inner}</a>"
      end
      def three(a, b)
        "[" \
        "#{a}-#{b}" \
        "]"
      end
      def tail(n)
        "n=#{n}" \
        " done"
      end
      puts svg(16, "x")
      puts three("L", "R")
      puts tail(7)

    RUBY

    _(result).must_answer <<~'OUT'
      #<ArgumentError: root>
      top
      #<ArgumentError: inner>
      nil
      TypeError: exception object expected
      ArgumentError: circular causes
      abc
      123
      123
      abc
      abc
      nil
      "b"
      <a width='16' height='16'>x</a>
      [L-R]
      n=7 done
    OUT
  end

  it "raise computed class" do
    result = ze0(<<~'RUBY')
      # `raise <computed>, message` -- a runtime-computed exception class/instance
      # (not a literal constant) coerces like Kernel#raise (`klass.exception(msg)`).
      def boom(klass) = raise klass, "boom from #{klass}"

      [ArgumentError, TypeError, RuntimeError].each do |k|
        begin
          boom(k)
        rescue => e
          puts "#{e.class}: #{e.message}"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: boom from ArgumentError
      TypeError: boom from TypeError
      RuntimeError: boom from RuntimeError
    OUT
  end

  it "raise forwards its arguments" do
    result = ze0(<<~'RUBY')
      # `raise(...)` -- argument forwarding into raise. The static raise desugar
      # has no shape for `...`, so it must route through the general call
      # lowering, which expands the forwarding into `*rest, **kw, &blk` and
      # reaches the runtime `Kernel#raise` row (sus forwards a matcher's whole
      # failure this way).
      def reraise(...)
        raise(...)
      end

      begin
        reraise(ArgumentError, "forwarded")
      rescue ArgumentError => e
        puts e.message
      end

      begin
        reraise("plain message")
      rescue RuntimeError => e
        puts e.message
      end

      # The splat spelling stays on the same path.
      def splat_raise(*exc)
        raise(*exc)
      end

      begin
        splat_raise(TypeError, "splatted")
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      forwarded
      plain message
      splatted
    OUT
  end

  it "raise names its own cause" do
    result = ze0(<<~'RUBY')
      # `raise ..., cause: c` names the cause outright, so the automatic `$!`
      # chaining is skipped and the named one stands -- `cause: nil` suppresses
      # chaining entirely, and a non-exception cause is a TypeError.
      class Wrapped < StandardError; end
      begin
        begin
          raise "inner"
        rescue => e
          raise Wrapped, "outer", cause: e
        end
      rescue Wrapped => w
        p w.message
        p w.cause.message
      end

      begin
        raise "a", cause: nil
      rescue => e
        p e.cause
      end

      begin
        begin
          raise "x"
        rescue
          raise ArgumentError.new("y"), cause: $!
        end
      rescue ArgumentError => e
        p [e.message, e.cause.message]
      end

      begin
        raise "z", cause: 5
      rescue TypeError => e
        p e.message
      end

      err = RuntimeError.new("self")
      begin
        raise err, cause: err
      rescue => e
        p e.cause
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "outer"
      "inner"
      nil
      ["y", "x"]
      "exception object expected"
      nil
    OUT
  end

  it "raise shortform default args" do
    result = ze0(<<~'RUBY')
      # A short-form `raise Cls, "msg"` of an exception whose initialize has
      # defaulted parameters (positional or keyword) must fill those defaults at
      # the generated constructor call site: sp_Cls_new keeps the full signature,
      # so a message-only emission is a cc arity error.
      class Boom < StandardError
        attr_reader :level, :code
        def initialize(message, level = 7, code: 3)
          super(message)
          @level = level
          @code = code
        end
      end

      begin
        raise Boom, "one-arg raise"
      rescue Boom => e
        puts "#{e.message} level=#{e.level} code=#{e.code}"
      end

      begin
        raise Boom.new("explicit", 8, code: 9)
      rescue Boom => e
        puts "#{e.message} level=#{e.level} code=#{e.code}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      one-arg raise level=7 code=3
      explicit level=8 code=9
    OUT
  end

  it "raise takes one keyword and collapses the rest" do
    result = ze0(<<~'RUBY')
      # `cause:` is the only keyword `raise` reads. Anything else written that way is
      # not a keyword at all: ruby collapses the rest into ONE Hash and passes it as
      # an ordinary positional argument, so it lands in the MESSAGE slot and reaches
      # `TheError.exception(hash)`.
      #
      # pundit writes `raise NotAuthorizedError, query: query, record: record,
      # policy: policy`, and its error class takes a positional options hash. Reading
      # those as keywords zeo had to accept made the whole gem a compile error.

      class Denied < StandardError
        def initialize(options = {})
          @options = options
          super("denied #{options[:query]}")
        end

        attr_reader :options
      end

      begin
        raise Denied, query: :show?, record: 7
      rescue Denied => e
        p e.message
        p e.options
      end

      # An error class that takes a real message gets the HASH as its message, which
      # is exactly what ruby does -- no keyword is special here either.
      begin
        raise ArgumentError, message: "params must be a Hash"
      rescue ArgumentError => e
        p e.message
      end

      prior = RuntimeError.new("prior")

      # `cause:` is taken OUT of the collapsed hash, and the rest still collapses.
      begin
        raise Denied, query: :edit?, cause: prior
      rescue Denied => e
        p e.options
        p e.cause.message
      end

      # With nothing left after `cause:` comes out, no extra positional is passed at
      # all -- `Denied.new` runs on its default.
      begin
        raise Denied, cause: prior
      rescue Denied => e
        p e.options
        p e.cause.message
      end

      # `**h` is part of the collapsed hash like any pair.
      h = { query: :splatted, record: 1 }

      begin
        raise Denied, **h
      rescue Denied => e
        p e.options
      end

      # A `cause:` beside a real message positional leaves the message alone: the
      # keyword never reaches the exception at all.
      class Simple < StandardError; end

      begin
        raise Simple, "explicit", cause: prior
      rescue Simple => e
        p e.message
        p e.cause.message
      end

      # `fail` is the same method under its other name.
      begin
        fail Denied, query: :destroy?
      rescue Denied => e
        p e.options
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "denied show?"
      {query: :show?, record: 7}
      "{message: \"params must be a Hash\"}"
      {query: :edit?}
      "prior"
      {}
      "prior"
      {query: :splatted, record: 1}
      "explicit"
      "prior"
      {query: :destroy?}
    OUT
  end

  it "raise uses exception hook" do
    _(ze0(<<~'RUBY')).must_answer "\"custom: x\"\n"
      class CustomE < StandardError
        def self.exception(msg = nil) = new("custom: #{msg}")
      end

      begin
        raise CustomE, "x"
      rescue => e
        p e.message
      end
    RUBY
  end

  it "raise with a bare class defaults the message to the class name" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/raise_with_a_bare_class_defaults_the_message_to_the_class_name.rb")
      # Assert the UNCAUGHT path here (see the `rescue` tests below for the
      # caught path): an unhandled `raise MyError` (no explicit message) exits 1 with the
      # class's own name as the message (no runtime `self.class` reflection
      # needed).

      class MyError < StandardError
      end
      class Box
        def check
          raise MyError
        end
      end
      Box.new.check
    RUBY

    _(result).must_answer "", stderr: "lang/exceptions/raise_with_a_bare_class_defaults_the_message_to_the_class_name.rb:10:in 'Box#check': MyError (MyError)\n\tfrom lang/exceptions/raise_with_a_bare_class_defaults_the_message_to_the_class_name.rb:13:in '<main>'\n", status: 1
  end

  it "raise with an exception hook" do
    _(ze0(<<~'RUBY')).must_answer "custom exception hook: hi\ncustom exception hook: \n"
      # `raise obj, "msg"` where obj's class overrides #exception does not even
      # BUILD: codegen hands the constructed object to the raise-argument
      # coercion unboxed, where a boxed value is wanted, and the generated program
      # is rejected. Any program using this shape fails to compile, so this gap
      # "diverges" by failing to produce a binary at all.
      class WithHook
        def exception(msg = nil)
          RuntimeError.new("custom exception hook: #{msg}")
        end
      end

      begin
        raise WithHook.new, "hi"
      rescue => e
        puts e.message
      end

      begin
        raise WithHook.new
      rescue => e
        puts e.message
      end
    RUBY
  end

  it "raising a non exception is a type error" do
    result = ze0(<<~'RUBY')
      # `raise <non-exception>` coerces at runtime -- a String becomes a
      # RuntimeError, everything else is CRuby's TypeError -- instead of
      # panicking when the raise machinery unwraps a non-Object.

      def try
        yield
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      try { raise 42 }
      try { raise nil }
      try { raise :sym }
      begin
        raise "boom"
      rescue RuntimeError => e
        puts "RuntimeError: #{e.message}"
      end
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
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      RuntimeError: boom
      poly string: msg
      poly object: exception class/object expected
    OUT
  end

  it "rescue binding rebinds whatever the name held" do
    result = ze0(<<~'RUBY')
      # `rescue => e` assigns `e`, and ruby does not care what `e` was before. The
      # name simply holds the exception inside the handler, and keeps holding it
      # afterwards -- a rescue binding is an ordinary local assignment, not a scoped
      # one.
      #
      # A compiler that infers a type per local has to widen the slot at that
      # assignment. Keeping the type the name had BEFORE emitted the handler's
      # `e.message` as a call on that earlier type while the value was an exception.

      class Box
        def initialize(v)
          @v = v
        end

        def message = "box(#{@v})"
      end

      # A user-class local, then the same name as a rescue binding.
      e = Box.new(1)
      p e.message

      begin
        raise ArgumentError, "boom"
      rescue ArgumentError => e
        p e.message
        p e.class
      end

      # ... and it is STILL the exception after the begin.
      p e.class
      p e.message

      # The other order: bound by a rescue first, then assigned an ordinary object.
      begin
        raise "first"
      rescue => x
        p x.message
      end

      x = Box.new(2)
      p x.message

      # An Integer local, and a String one -- the same widening, no user class in it.
      n = 42
      begin
        Integer("nope")
      rescue ArgumentError => n
        p n.class
      end
      p n.is_a?(Exception)

      s = "plain"
      p s.upcase
      begin
        raise TypeError, "typed"
      rescue TypeError => s
        p s.message
      end
      p s.class

      # One name across two clauses of the same begin, each raising a different class.
      def attempt(which)
        raise ArgumentError, "arg" if which == :arg
        raise TypeError, "type"
      end

      [:arg, :type].each do |which|
        outcome = Box.new(which)
        begin
          attempt(which)
        rescue ArgumentError => outcome
          p [:arg, outcome.message]
        rescue TypeError => outcome
          p [:type, outcome.message]
        end
        p outcome.class
      end

      # A nested begin reusing the outer handler's name.
      begin
        raise "outer"
      rescue => err
        p err.message
        begin
          raise KeyError, "inner"
        rescue KeyError => err
          p err.message
        end
        p err.message
      end

      # The binding survives a handler that never ran, too: `rescue` did not fire, so
      # the name keeps what it already had.
      untouched = Box.new(:kept)
      begin
        :fine
      rescue => untouched
        p :never
      end
      p untouched.message
    RUBY

    _(result).must_answer <<~'OUT'
      "box(1)"
      "boom"
      ArgumentError
      ArgumentError
      "boom"
      "first"
      "box(2)"
      ArgumentError
      true
      "PLAIN"
      "typed"
      TypeError
      [:arg, "arg"]
      ArgumentError
      [:type, "type"]
      TypeError
      "outer"
      "inner"
      "inner"
      "box(kept)"
    OUT
  end

  it "rescue honors custom case eq" do
    result = ze0(<<~'RUBY')
      # `rescue M => e` matches via `===` (CRuby's rule) -- a matcher module that
      # OVERRIDES `self.===` decides for itself. rspec-support's
      # AllExceptionsExceptOnesWeMustNotRescue catches everything except
      # NoMemoryError/SignalException this way; an ancestry-only match let real
      # expectation failures escape Example#run.
      module CatchesRuntime
        def self.===(exception)
          RuntimeError === exception
        end
      end

      begin
        raise "boom"
      rescue CatchesRuntime => e
        puts "caught: #{e.message}"
      end

      begin
        raise TypeError, "nope"
      rescue CatchesRuntime => e
        puts "wrong: #{e.message}"
      rescue TypeError => e
        puts "type: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      caught: boom
      type: nope
    OUT
  end

  it "rescue modifier assign" do
    result = ze0(<<~'RUBY')
      # `expr rescue fallback` as an rvalue — verifies that
      # RescueModifierNode is wired into infer_type so the receiving
      # variable gets the unified type rather than the default int.
      #
      # Note: Ruby's `=` has higher precedence than the rescue modifier,
      # so `a = "x" rescue "y"` parses as `(a = "x") rescue "y"` — the
      # RescueModifierNode wraps the assignment, not the rvalue. To
      # actually exercise the RescueModifierNode-as-rvalue path through
      # infer_type, the rescue must be parenthesized as a sub-expression.

      # Same-type branches: string=string. Trivial baseline.
      a = ("ok" rescue "fallback")
      puts a

      # Mismatched branches: main is `raise` (returns int 0 from
      # compile_expr but never actually returns), fallback is string.
      # The fallback wins type inference; result type is string.
      b = (raise "boom" rescue "default")
      puts b

      # Same-type int. Endless method shape stays unchanged.
      def parse_int(s) = Integer(s) rescue 0
      puts parse_int("42")
      puts parse_int("abc")
    RUBY

    _(result).must_answer <<~'OUT'
      ok
      default
      42
      0
    OUT
  end

  it "rescue module bare reader" do
    result = ze0(<<~'RUBY')
      # rescue-by-module matching (an exception matches a rescue arm naming a
      # module its class includes) and user readers on a bare-rescued exception.

      module Alertable; end
      module Ignorable; end

      class AppError < StandardError
        include Alertable
      end
      class SubAppError < AppError; end
      class PlainError < StandardError; end

      # direct include matches
      begin
        raise AppError, "direct"
      rescue Alertable => e
        puts "alertable: #{e.message}"
      end

      # subclass of an including class matches (module arrives via an ancestor)
      begin
        raise SubAppError, "inherited"
      rescue Alertable => e
        puts "alertable: #{e.message}"
      end

      # a class NOT including the module falls through to the next arm
      begin
        raise PlainError, "plain"
      rescue Ignorable
        puts "wrong arm"
      rescue StandardError => e
        puts "fell through: #{e.message}"
      end

      # module arm chained before a class arm picks the right one
      def classify(make_app)
        begin
          if make_app
            raise AppError, "app"
          else
            raise PlainError, "other"
          end
        rescue Alertable
          "matched module"
        rescue PlainError
          "matched class"
        end
      end
      puts classify(true)
      puts classify(false)

      # user reader on a bare-rescued exception
      class CodedError < StandardError
        attr_reader :code
        def initialize(c); @code = c; super("coded"); end
      end

      begin
        raise CodedError.new(42)
      rescue => err
        p err.code
        puts err.message
      end

      # bare rescue in a method body
      def risky(n)
        raise CodedError.new(n * 2)
      rescue => e
        e.code
      end
      p risky(21)
    RUBY

    _(result).must_answer <<~'OUT'
      alertable: direct
      alertable: inherited
      fell through: plain
      matched module
      matched class
      42
      coded
      42
    OUT
  end

  it "rescue namespaced exception" do
    result = ze0(<<~'RUBY')
      # A user exception raised under its qualified Ruby name ("App::Error") must be
      # matched by every arm shape: a namespaced arm (`rescue App::Error`, whose AST
      # name is the leaf), a leaf-referenced arm inside the module, a parent-class
      # arm catching a namespaced subclass (the hierarchy callback registers
      # qualified parents), and a builtin StandardError arm. Covers both the
      # class-fallback raise (sp_raise_cls) and the constructed-object raise.
      module App
        class Error < StandardError
        end

        class SubError < Error
        end

        def self.leafy
          raise Error, "leaf ref"
        rescue Error => e
          puts "leaf caught: #{e.message}"
        end
      end

      begin
        raise App::SubError, "sub raise"
      rescue App::Error => e
        puts "parent arm caught: #{e.message}"
      end

      App.leafy

      begin
        raise App::Error.new("explicit new")
      rescue StandardError => e
        puts "std caught: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      parent arm caught: sub raise
      leaf caught: leaf ref
      std caught: explicit new
    OUT
  end

  it "rescue splat follows the splat rule" do
    result = ze0(<<~'RUBY')
      # `rescue A, *list => e` splats `list` by the SAME rule an argument list does.
      #
      # zeo tested the splat's value as if it were always one class, so `*nil` --
      # which splices nothing -- was tested as a nil class and raised
      # `TypeError: class or module required for rescue clause` INSTEAD of whatever
      # the body raised. It only showed when no earlier entry matched, which is why
      # it hid: the common path short-circuits before the splat is ever read.
      #
      # rubygems writes exactly that:
      #
      #     rescue Gem::Timeout::Error, IOError, SocketError, SystemCallError,
      #            *(OpenSSL::SSL::SSLError if Gem::HAVE_OPENSSL) => e
      #
      # so every failed download reported a TypeError from a rescue clause instead
      # of the error it was rescuing.

      class Splattable
        def to_a = [ArgumentError, TypeError]
      end

      def catch_with(list)
        raise KeyError, "k"
      rescue IOError, *list => e
        "caught #{e.class}"
      end

      [nil, [], [KeyError], KeyError, Splattable.new, false].each do |list|
        result = begin
          catch_with(list)
        rescue StandardError => e
          "#{e.class}: #{e.message}"
        end
        puts "#{list.class}\t#{result}"
      end

      # The splat entry really is consulted, not just tolerated.
      def only_via_splat
        raise ArgumentError, "a"
      rescue *[ArgumentError] => e
        "splat matched #{e.class}"
      end
      puts only_via_splat

      # A guarded splat that evaluates to a class still matches through it.
      HAVE = true
      def guarded
        raise ArgumentError, "a"
      rescue IOError, *(ArgumentError if HAVE) => e
        "guard matched #{e.class}"
      end
      puts guarded

      # And the same clause with the guard false lets the exception past.
      NONE = nil
      def unguarded
        raise ArgumentError, "a"
      rescue IOError, *(ArgumentError if NONE) => e
        "guard matched #{e.class}"
      end
      begin
        unguarded
      rescue ArgumentError => e
        puts "guard absent, propagated #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      NilClass	KeyError: k
      Array	KeyError: k
      Array	caught KeyError
      Class	caught KeyError
      Splattable	KeyError: k
      FalseClass	TypeError: class or module required for rescue clause
      splat matched ArgumentError
      guard matched ArgumentError
      guard absent, propagated ArgumentError
    OUT
  end

  it "runtime raise not compile error" do
    result = ze0(<<~'RUBY')
      # Cases where a compiler is tempted to reject at build time but real Ruby
      # raises at RUNTIME -- so the program must compile, run, and let a `rescue`
      # see the error. Codegen lowers every branch eagerly, so rejecting any of
      # these statically would kill an otherwise-correct program.

      def err
        yield
      rescue => e
        "#{e.class}: #{e.message}"
      end

      # 1. public_send is stricter than an explicit-receiver call: it rejects BOTH
      #    private and protected, with no self-relatedness relaxation.
      class Acct
        def balance = 100
        def peer_check(other) = other.guarded

        protected

        def guarded = "prot"

        private

        def secret = 42
      end

      a = Acct.new
      p a.public_send(:balance)
      puts err { a.public_send(:secret) }
      puts err { a.public_send(:guarded) }

      # send / __send__ stay visibility-blind
      p a.send(:secret)
      p a.__send__(:secret)

      # ...while a protected method IS callable when the caller's self is related.
      p a.peer_check(Acct.new)

      # A runtime-computed method name is checked per resolved arm.
      def dyn(o, m) = o.public_send(m)
      p dyn(a, :balance)
      puts err { dyn(a, :secret) }

      # 2. A blockless Thread.new / Fiber.new raises rather than failing to compile.
      puts err { Thread.new }
      puts err { Fiber.new }

      # 3. A non-finite float literal is a perfectly good value, not a codegen
      #    failure -- it just cannot be spelled as a float literal.
      big = 1e400
      p big
      p(-1e400)
      p big.infinite?
      p (big - big).nan?

      # 4. `for` performs no type dispatch in Ruby: it is just `each` with a block,
      #    so any object answering #each iterates.
      class Nums
        include Enumerable
        def initialize(*xs) = @xs = xs
        def each; @xs.each { |x| yield x }; end
      end

      total = 0
      for x in Nums.new(1, 2, 3, 4)
        total += x
      end
      p total

      # multi-assignment `for` over a pair-yielding each
      class Pairs
        include Enumerable
        def each; yield [1, :a]; yield [2, :b]; end
      end

      pairs = []
      for k, v in Pairs.new
        pairs << "#{k}:#{v}"
      end
      p pairs

      # `for` does NOT introduce a new scope: the variable survives the loop.
      for survivor in [10, 20, 30]
      end
      p survivor

      # an object with no #each fails at runtime, not at compile time
      puts err { for z in 5; end }

      # 5. Guards against loops that would otherwise never terminate.
      #
      # NOTE: `"x" * (1 << 60)` is deliberately NOT exercised here. CRuby's guard
      # only covers the length multiplication, so a 1-byte string times 2^60 reaches
      # the allocator and raises NoMemoryError -- which, not being a StandardError,
      # escapes `rescue => e` and kills the program. zeo caps the total size and
      # raises a catchable ArgumentError instead, so the two cannot share a golden
      # file; the corpus `string_multiply_overflow` pins that behavior separately.
      puts err { "x" * -1 }
      p "ab" * 3
      puts err { 1.step(10, 0) { } }
      puts err { Rational(1, 2).step(Rational(5, 2), 0) { } }
      puts err { (1..).to_a }
      p (1..4).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      100
      NoMethodError: private method 'secret' called for an instance of Acct
      NoMethodError: protected method 'guarded' called for an instance of Acct
      42
      42
      "prot"
      100
      NoMethodError: private method 'secret' called for an instance of Acct
      ThreadError: must be called with a block
      ArgumentError: tried to create Proc object without a block
      Infinity
      -Infinity
      1
      true
      10
      ["1:a", "2:b"]
      30
      NoMethodError: undefined method 'each' for an instance of Integer
      ArgumentError: negative argument
      "ababab"
      ArgumentError: step can't be 0
      ArgumentError: step can't be 0
      RangeError: cannot convert endless range to an array
      [1, 2, 3, 4]
    OUT
  end

  it "scoped const write to an undefined scope raises before the rhs runs" do
    _(ze0(<<~'RUBY')).must_answer "NameError: uninitialized constant Nope\n"
      # CRuby resolves the scope BEFORE evaluating the value, so the RHS side
      # effect never runs.

      r = begin
        Nope::X = (puts "rhs-ran"; 5)
        "assigned"
      rescue => e
        "#{e.class}: #{e.message}"
      end
      puts r
    RUBY
  end

  it "top level def recursion and mutual calls" do
    _(ze0(<<~'RUBY')).must_answer "fib(10) = 55\n"
      def fib(n)
        n < 2 ? n : fib(n - 1) + fib(n - 2)
      end
      def announce(n)
        puts "fib(#{n}) = #{fib(n)}"
      end
      announce(10)
    RUBY
  end

  it "transform keys combined cmp wave10" do
    result = ze0(<<~'RUBY')
      # transform_keys with a mapping AND a fallback block, and Comparable
      # operators over a nil-capable user <=> (incomparable raises).
      h = { a: 1, b: 2, c: 3 }
      p h.transform_keys({ a: :x })
      p h.transform_keys({ a: :x }) { |k| k.to_s }
      g = { a: 1 }
      p g.transform_keys { |k| k.to_s }
      class V124
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o)
          return nil unless o.is_a?(V124)
          n <=> o.n
        end
      end
      a = V124.new(1); b = V124.new(2)
      p(a < b)
      p(a > b)
      p(a.between?(a, b))
      r = (begin; a < 5; rescue ArgumentError; "AE"; end); p r
      p(a.clamp(a, b).n)
    RUBY

    _(result).must_answer <<~'OUT'
      {x: 1, b: 2, c: 3}
      {x: 1, "b" => 2, "c" => 3}
      {"a" => 1}
      true
      false
      true
      "AE"
      1
    OUT
  end

  it "uncaught error reports its causes" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/an_uncaught_error_reports_its_causes.rb")
      # The report of an uncaught exception names each cause after it, each
      # once, as full_message does.
      class Outer < StandardError; end

      def a = raise("a")

      def b
        a
      rescue
        raise Outer, "b"
      end

      b

    RUBY

    _(result).must_answer "", stderr: "lang/exceptions/an_uncaught_error_reports_its_causes.rb:10:in 'Object#b': b (Outer)\n\tfrom lang/exceptions/an_uncaught_error_reports_its_causes.rb:13:in '<main>'\nlang/exceptions/an_uncaught_error_reports_its_causes.rb:5:in 'Object#a': a (RuntimeError)\n\tfrom lang/exceptions/an_uncaught_error_reports_its_causes.rb:8:in 'Object#b'\n\tfrom lang/exceptions/an_uncaught_error_reports_its_causes.rb:13:in '<main>'\n", status: 1
  end

  it "uncaught exception report matches cruby shape" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/uncaught_exception_report_matches_cruby_shape.rb")
      # The top-level report: innermost frame heads the message line, outer
      # frames follow tab-indented -- verbatim ruby 4.0.6 (as `-e`).

      def inner; raise "boom"; end
      def outer; inner; end
      outer
    RUBY

    _(result).must_answer "", stderr: "lang/exceptions/uncaught_exception_report_matches_cruby_shape.rb:4:in 'Object#inner': boom (RuntimeError)\n\tfrom lang/exceptions/uncaught_exception_report_matches_cruby_shape.rb:5:in 'Object#outer'\n\tfrom lang/exceptions/uncaught_exception_report_matches_cruby_shape.rb:6:in '<main>'\n", status: 1
  end

  it "unshareable message is deep copied across the boundary" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/an_unshareable_message_is_deep_copied_across_the_boundary.rb")
      # Mutating the original AFTER send must not affect the ractor's copy --
      # the whole point of the isolation discipline.
      # Asserted via `puts` on the round-tripped copy (collection methods on
      # the Poly-typed receive result are the pre-existing Poly-dispatch
      # gap, nothing Ractor-specific).

      echo = Ractor.new do
        Ractor.receive
      end
      payload = [100, 200]
      echo.send(payload)
      payload[0] = 999
      puts echo.value
    RUBY

    _(result).must_answer <<~'OUT', stderr: "lang/exceptions/an_unshareable_message_is_deep_copied_across_the_boundary.rb:7: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      100
      200
    OUT
  end
end
