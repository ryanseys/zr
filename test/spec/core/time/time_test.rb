# frozen_string_literal: true

require "spec_helper"

describe "Time programs" do
  it "allocated time is uninitialized" do
    result = ze0(<<~'RUBY')
      # `Time.allocate` answers a Time whose instant was never set, and every row
      # that reads the instant refuses it -- CRuby's `uninitialized Time`.
      #
      # zeo used to raise `allocator undefined for Time` at the `allocate` itself,
      # so the refusal came one step early and under the wrong message. The marker
      # costs no field: `RTime::den` is a rational denominator and is positive for
      # every real instant, so zero is free.
      #
      # Only the rows that READ the instant refuse. `class` and `frozen?` answer,
      # and `instance_variables` is empty -- an allocated Time is an ordinary object
      # until something asks it what time it is.
      t = Time.allocate
      %w[to_i to_f year month day hour min sec inspect to_s hash usec nsec].each do |m|
        begin
          p [m, t.send(m)]
        rescue => e
          p [m, e.class, e.message]
        end
      end
      p ["frozen?", t.frozen?]
      p ["class", t.class]
      p ["ivars", t.instance_variables]

      # Two different blank Times cannot even be compared: `==` reads both instants.
      a = Time.allocate
      b = Time.allocate
      p ["a==b", (a == b rescue [$!.class, $!.message])]
      p ["a<=>b", (a <=> b rescue [$!.class, $!.message])]
      p ["eql?", (a.eql?(b) rescue [$!.class, $!.message])]
      p ["dup", (a.dup.class rescue [$!.class, $!.message])]

      # An initialized Time is unaffected.
      real = Time.at(0).utc
      p [real.to_i, real.year, real.utc?]
    RUBY

    _(result).must_answer <<~'OUT'
      ["to_i", TypeError, "uninitialized Time"]
      ["to_f", TypeError, "uninitialized Time"]
      ["year", TypeError, "uninitialized Time"]
      ["month", TypeError, "uninitialized Time"]
      ["day", TypeError, "uninitialized Time"]
      ["hour", TypeError, "uninitialized Time"]
      ["min", TypeError, "uninitialized Time"]
      ["sec", TypeError, "uninitialized Time"]
      ["inspect", TypeError, "uninitialized Time"]
      ["to_s", TypeError, "uninitialized Time"]
      ["hash", TypeError, "uninitialized Time"]
      ["usec", TypeError, "uninitialized Time"]
      ["nsec", TypeError, "uninitialized Time"]
      ["frozen?", false]
      ["class", Time]
      ["ivars", []]
      ["a==b", [TypeError, "uninitialized Time"]]
      ["a<=>b", [TypeError, "uninitialized Time"]]
      ["eql?", [TypeError, "uninitialized Time"]]
      ["dup", [TypeError, "uninitialized Time"]]
      [0, 1970, true]
    OUT
  end

  it "compile time define method direct" do
    result = ze0(<<~'RUBY')
      class CompileTimeDirectDefineMethod
        define_method(:answer) { 42 }
        define_method("greeting") { "hello" }
      end

      obj = CompileTimeDirectDefineMethod.new
      puts obj.answer
      puts obj.greeting
    RUBY

    _(result).must_answer "42\nhello\n"
  end

  it "compile time define method int" do
    result = ze0(<<~'RUBY')
      class CompileTimeIntMethods
        [1, 2].each do |n|
          define_method("value_#{n}") { n }
        end
      end

      obj = CompileTimeIntMethods.new
      puts obj.value_1
      puts obj.value_2
    RUBY

    _(result).must_answer "1\n2\n"
  end

  it "compile time define method strings" do
    result = ze0(<<~'RUBY')
      class CompileTimeStringMethods
        ["red", "blue"].each do |name|
          define_method("label_#{name}") { name }
        end
      end

      obj = CompileTimeStringMethods.new
      puts obj.label_red
      puts obj.label_blue
    RUBY

    _(result).must_answer "red\nblue\n"
  end

  it "cond poly truthy" do
    result = ze0(<<~'RUBY')
      # a Range value is always truthy in condition position
      def range_truthy(r) = r ? "yes" : "no"
      puts range_truthy(1..3)

      c = (1..5)
      puts "range kept" if c

      # a Class value is always truthy
      def class_truthy(k) = k ? "has class" : "no class"
      puts class_truthy(String)

      # guard pattern: collect when the (truthy) value is present
      out = []
      val = (1..2)
      out << "kept" if val
      p out

      # other always-truthy concrete types in condition position. Each value flows
      # through a monomorphic helper param so it keeps its concrete static type (and
      # is not constant-folded), exercising the per-type truthiness branches.
      def time_truthy(t) = t ? "yes" : "no"
      puts time_truthy(Time.at(0))            # value type (sp_Time)

      def regex_truthy(re) = re ? "yes" : "no"
      puts regex_truthy(/x/)                  # pointer type (mrb_regexp_pattern *)

      def method_truthy(m) = m ? "yes" : "no"
      puts method_truthy(method(:range_truthy))  # pointer type (sp_BoundMethod *)

      def random_truthy(r) = r ? "yes" : "no"
      puts random_truthy(Random.new(42))      # pointer type (sp_Random *)

      def curry_truthy(p) = p ? "yes" : "no"
      puts curry_truthy(->(a, b) { a + b }.curry)  # pointer type (sp_Curry *)
    RUBY

    _(result).must_answer <<~'OUT'
      yes
      range kept
      has class
      ["kept"]
      yes
      yes
      yes
      yes
      yes
    OUT
  end

  it "every eval is a run time one" do
    result = ze0(<<~'RUBY')
      # A literal `eval("...")` was once SPLICED: parsed at compile time and run
      # as ordinary code in the enclosing scope. That was an optimization with a
      # price, and every part of the price is visible from Ruby -- `__FILE__` and
      # every backtrace row named the ENCLOSING file where CRuby names
      # `(eval at f.rb:2)`, a magic comment written in the string was ignored,
      # and the snippet shared the caller's storage outright where CRuby shares
      # a Binding. The splice is gone: every `eval` is a run-time one, compiled
      # by the same front end and cached by source.

      def here(text)
        text.sub(__FILE__, "F")
      end

      def where
        eval("[__FILE__, __LINE__]")
      end
      p here(where.first)
      p where.last

      def raiser
        eval("raise 'boom'")
      end
      begin
        raiser
      rescue => e
        puts e.backtrace.first(2).map { |l| here(l) }
      end

      p eval("# frozen_string_literal: true\n'abc'.frozen?")
      p eval("'abc'.frozen?")

      # A `BEGIN` block belongs to the snippet, not to the program's head.
      eval("BEGIN { puts 'begin ran' }")
      puts "after"

      # The caller's locals are still shared -- through the Binding the site
      # materializes, which is CRuby's own model.
      x = 1
      eval("x = x + 41")
      p x
      p eval("eval('x + 1', binding)")
    RUBY

    _(result).must_answer <<~'OUT'
      "(eval at F:15)"
      1
      (eval at F:21):1:in 'Object#raiser'
      F:21:in 'Kernel#eval'
      true
      false
      begin ran
      after
      42
      43
    OUT
  end

  it "file the compiler never saw loads at run time" do
    files = beside("a_file_the_compiler_never_saw_loads_at_run_time/boom.rb",
                "a_file_the_compiler_never_saw_loads_at_run_time/cycle_a.rb",
                "a_file_the_compiler_never_saw_loads_at_run_time/cycle_b.rb",
                "a_file_the_compiler_never_saw_loads_at_run_time/deep/inner.rb",
                "a_file_the_compiler_never_saw_loads_at_run_time/top.rb")

    result = ze0(<<~'RUBY', files: files)
      # A file the compiler never saw is compiled and run where it is FOUND.
      #
      # Whole-program AOT resolves an ordinary `require` at compile time and
      # splices it, and a COMPUTED one under a compile-time `-I` root reaches a
      # unit the eager sweep compiled in. What neither covers is a target under
      # no compile-time root at all: `$LOAD_PATH.unshift(dir); require "x"`, or
      # an absolute path. Those used to be a flat `LoadError`.
      #
      # They reach the same compiler an `eval` does now
      # (`features::UnitCompiler`, installed by the same `zeo_eval_install`), so
      # a program that can reach one carries exactly the machinery a program
      # that can `eval` carries -- and one that cannot still links neither.
      #
      # The file is a top-level scope like any other: its `def`s land on
      # `Object`, its classes mint, `__FILE__` is its own path, a backtrace row
      # inside it says where the code really is, and its own `require`s come
      # straight back to the load path -- including `require_relative`, which
      # resolves against the CALLING file the frame carries, since a snippet has
      # no compile-time directory to resolve against.
      root = File.join(__dir__, "a_file_the_compiler_never_saw_loads_at_run_time")
      $LOAD_PATH.unshift(root)

      # Once only, and the answer says which time it was.
      p require("top")
      p require("top")
      p [$top_runs, $inner_runs]
      p RuntimeTop.hi
      p LOADED_TOP_FILE.end_with?("top.rb")
      p $LOADED_FEATURES.count { |f| f.end_with?("top.rb") }

      # A require CYCLE terminates, exactly as CRuby's loading table makes it.
      p require("cycle_a")
      p [CYCLE_A, CYCLE_B]

      # A file that RAISED is not loaded, so a later require retries it.
      2.times do
        begin
          require "boom"
        rescue ArgumentError => e
          p [:raised, e.message]
        end
      end

      # A target that resolves to nothing is still CRuby's LoadError.
      begin
        require "no_such_feature_at_all"
      rescue LoadError => e
        p [:missing, e.message]
      end

      # `load` names an exact file and RE-EXECUTES it.
      p load(File.join(root, "deep", "inner.rb"))
      p $inner_runs

      # A backtrace names the file, the line and the scope the code was written
      # in -- through two levels of run-time load.
      begin
        Raiser.new.boom
      rescue RuntimeError => e
        puts e.message
        puts e.backtrace.first(3).map { |l| l.sub(__dir__ + "/", "") }
      end

    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      [1, 1]
      "top 7"
      true
      1
      true
      [1, 2]
      [:raised, "boom from the file"]
      [:raised, "boom from the file"]
      [:missing, "cannot load such file -- no_such_feature_at_all"]
      true
      2
      from inner
      a_file_the_compiler_never_saw_loads_at_run_time/deep/inner.rb:6:in 'RuntimeInner.boom'
      a_file_the_compiler_never_saw_loads_at_run_time/top.rb:10:in 'Raiser#boom'
      core/time/time_test.rb:58:in '<main>'
    OUT
  end

  it "have i got this library constant is decided at compile time" do
    result = ze0(<<~'RUBY')
      # `CONST = begin; require "x"; true; rescue LoadError; end` reads like a
      # runtime value and is not one: a whole-program compiler already knows which
      # requires it can satisfy. hexapdf gates a whole file on `HARFBUZZ_AVAILABLE`
      # spelled exactly this way.
      MISSING = begin
                  require 'definitely_not_a_real_gem_xyz'
                  true
                rescue LoadError
                end
      p MISSING
      if MISSING
        class ShimA
          def tag = "a"
        end
      end
      p defined?(ShimA)

      PRESENT = begin
                  require 'set'
                  true
                rescue LoadError
                end
      p PRESENT
      if PRESENT
        class ShimB
          def tag = "b"
        end
      end
      p ShimB.new.tag

      # `defined?(Scope::NAME)` asks a SCOPED question, so an unrelated `VERSION`
      # elsewhere in the program is not an answer to it.
      module Other
        VERSION = "9.9"
      end
      if defined?(NotHere) && defined?(NotHere::VERSION)
        module Adapter
          NOPE = 1
        end
      end
      p defined?(Adapter)

      module Present
        VERSION = "1.0"
      end
      if defined?(Present::VERSION)
        module Wired
          YES = Present::VERSION
        end
      end
      p Wired::YES
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      true
      "b"
      nil
      "1.0"
    OUT
  end

  it "keeps a float epoch exactly" do
    result = ze0(<<~'RUBY')
      # A Float epoch is stored EXACTLY (Ruby keeps the double's true rational,
      # denominator a power of two), and `nsec` is a TRUNCATED VIEW of it. This is
      # observable: `Time.at(10.8) - 0.9` is nsec 900000000, which a `(sec, nsec)`
      # representation gets wrong (899999999) by dropping 10.8's sub-nanosecond
      # tail before subtracting. All oracle-read.

      p Time.at(0.5).subsec
      p Time.at(10.8).subsec
      p Time.at(10.8).nsec
      p (Time.at(10.8) - 0.9).nsec
      p (Time.at(10.8) - 0.9).subsec
      p Time.at(1.25).to_f
      p Time.at(1700000000).getutc.subsec
      p (Time.at(100) + -1.3).usec
      p (Time.at(100) - 1.3).usec
    RUBY

    _(result).must_answer <<~'OUT'
      (1/2)
      (225179981368525/281474976710656)
      800000000
      900000000
      (8106479329266899/9007199254740992)
      1.25
      0
      699999
      699999
    OUT
  end

  it "kernel callee putc and public method" do
    result = ze0(<<~'RUBY')
      def who = [__method__, __callee__]
      p who
      putc 72
      putc "i"
      putc "\n"
      p putc(321).class
      puts
      p putc("BC")
      puts
      class Widget
        def render = "drawn"
        private
        def secret = 42
      end
      w = Widget.new
      p w.public_method(:render).call
      begin
        w.public_method(:secret)
      rescue NameError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:who, :who]
      Hi
      AInteger

      B"BC"

      "drawn"
      method 'secret' for class 'Widget' is private
    OUT
  end

  it "numeric and time fractional and rounding coercions" do
    result = ze0(<<~'RUBY')
      # Correctness fixes: Time.utc/local accept a fractional-microsecond 7th
      # argument (Float/Rational) and keep the sub-microsecond nanoseconds;
      # Rational#round honors the `half:` keyword (:up/:even/:down); Float
      # round/truncate with an extreme ndigits stays finite instead of NaN; and
      # Enumerator.new(callable).size invokes the callable lazily. Byte-verified
      # against ruby 4.0.6.

      p Time.utc(2001, 2, 3, 4, 5, 6, 500.5).nsec
      p Time.utc(2020, 1, 1, 0, 0, 0, Rational(1, 2)).nsec
      p Rational(5, 2).round(half: :even)
      p Rational(5, 2).round(half: :down)
      p Rational(5, 2).round(half: :up)
      p Rational(-5, 2).round(half: :even)
      p 1.23.round(400)
      p 1.23.round(-400)
      p 2.5.truncate(1000)
      p Enumerator.new(lambda { 42 }) { |y| y << 1 }.size
      p Enumerator.new(5) { |y| y << 1 }.size
      p Enumerator.new { |y| y << 1 }.size
    RUBY

    _(result).must_answer <<~'OUT'
      500500
      500
      2
      2
      3
      -2
      1.23
      0
      2.5
      42
      5
      nil
    OUT
  end

  it "poly hash with time" do
    result = ze0(<<~'RUBY')
      # Same heap-box pattern as Range applied to Time. sp_Time is wider
      # than sp_RbVal's union (8 bytes), so a Time value in a poly slot
      # (heterogeneous hash / array) used to fall through
      # `box_non_nullable_value_to_poly`'s default and emit
      # `sp_box_int(sp_time_at_int(...))` — which C rejected.
      #
      # The fix introduces SP_BUILTIN_TIME and `sp_box_time` (heap copies
      # the stack Time and boxes through SP_TAG_OBJ). The companion
      # `sp_Time_inspect` is timezone-dependent in the runtime (UTC) so
      # we don't compare the printed Time bodies here — the regression
      # is about the boxing path compiling and the int sibling values
      # round-tripping cleanly.

      H = {
        start: Time.at(0),
        middle: Time.at(1234567890),
        count: 42,
        limit: 100,
      }

      puts H[:count]                # 42
      puts H[:limit]                # 100
      puts H.length                 # 4
      puts H.has_key?(:start)       # true
      puts H.has_key?(:missing)     # false

      # Mixed poly array: Time + Int — verify the int slots still
      # round-trip and the Time slots don't break the array shape.
      arr = [Time.at(0), 100, Time.at(1234567890), 200]
      puts arr.length               # 4
      puts arr[1]                   # 100
      puts arr[3]                   # 200
    RUBY

    _(result).must_answer <<~'OUT'
      42
      100
      4
      true
      false
      4
      100
      200
    OUT
  end

  it "proc range time return" do
    result = ze0(<<~'RUBY')
      # A proc/lambda returning a Range or Time (by-value structs that don't fit the
      # mrb_int proc-ABI carrier) boxes through the poly return slot; the call site
      # dereferences the boxed heap copy back to the value. Step-ranges (downto)
      # carry their direction through the box.
      f = ->(n) { (1..n) }
      r = f.call(3)
      p r
      p r.to_a
      p f.call(5).sum
      g = proc { |a, b| (a...b) }
      p g.call(2, 6).to_a
      h = ->() { Time.at(0) }
      t = h.call
      p t.class
      p t.to_i
      make = ->(n) { n.downto(1) }
      p make.call(3).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      1..3
      [1, 2, 3]
      15
      [2, 3, 4, 5]
      Time
      0
      [3, 2, 1]
    OUT
  end

  it "putc writes one byte of an integer and one character of a string" do
    result = ze0(<<~'RUBY')
      # `0x1B4` truncates to its low byte; a BINARY string contributes its
      # first BYTE (never a UTF-8 promotion of it).

      path = "/tmp/zeo_e2e_binputc_#{Process.pid}"
      File.open(path, "wb") { |f| f.putc 0x1b4; f.putc 180.chr + "xx" }
      p File.binread(path).bytes
      File.delete(path)
    RUBY

    _(result).must_answer "[180, 180]\n"
  end

  it "regexp introspection linear time and class backrefs" do
    result = ze0(<<~'RUBY')
      # linear_time? is false only for a real (non-class) backreference. A
      # `\1`/`\k` INSIDE a character class is octal/literal, not a backref, and
      # must compile; a forward backref (`/[\]]\1(a)/`) constructs (never matches).

      p Regexp.linear_time?(/abc/)
      p Regexp.linear_time?(/(a)\1/)
      p Regexp.linear_time?(/[\1]/)
      p Regexp.linear_time?(/[a-z\k<x>]/)
      p Regexp.linear_time?(/[\1](a)\1/)
      p Regexp.linear_time?(/[\]]\1(a)/)
      p(/[\1]/.match?("\x01"))
      p(/[\]]\1(a)/.match("]a").nil?)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      false
      false
      true
      true
    OUT
  end

  it "regexp linear time value" do
    result = ze0(<<~'RUBY')
      p(Regexp.linear_time?(/(a)\1/))
      a001 = /(a)\1/; p(Regexp.linear_time?(a001))
      p(Regexp.linear_time?("(a)\\1"))
      p(Regexp.linear_time?(/abc/))
      b1 = /abc/; p(Regexp.linear_time?(b1))
      p(Regexp.linear_time?("abc"))
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      true
      true
      true
    OUT
  end

  it "reports its dst flag" do
    result = ze0(<<~'RUBY')
      # `Time#isdst`/`#dst?` report the broken-down time's DST flag; a UTC time is
      # never in DST.

      t = Time.at(0).utc
      p t.isdst
      p t.dst?
    RUBY

    _(result).must_answer "false\nfalse\n"
  end

  it "require of a boot preloaded feature is false even the first time" do
    result = ze0(<<~'RUBY')
      # `set` and `monitor` are already loaded before a CRuby program's first
      # line, so even their FIRST require answers false.

      p(require "set")
      p(require "monitor")
    RUBY

    _(result).must_answer "false\nfalse\n"
  end

  it "the argument's type picks: plus a number is a Time, minus a Time is a Float" do
    result = ze0(<<~'RUBY')
      # `t + n` answers a Time; `t - other_time` answers a Float of seconds; `t -
      # n` answers a Time. The argument's type picks.

      t = Time.at(1700000000).getutc
      p (t + 60).to_i
      p (t - 60).to_i
      p (Time.at(100) - Time.at(40))
      p (Time.at(100) - Time.at(40)).class
      p (t + 60).class
    RUBY

    _(result).must_answer <<~'OUT'
      1700000060
      1699999940
      60.0
      Float
      Time
    OUT
  end

  it "asctime and ctime print the same fixed-width form" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30)
      p t.asctime
      p t.ctime
    RUBY

    _(result).must_answer <<~'OUT'
      "Thu Jul 16 13:45:30 2026"
      "Thu Jul 16 13:45:30 2026"
    OUT
  end

  it "asctime, to_a, to_r, round, xmlschema and deconstruct_keys over one instant" do
    result = ze0(<<~'RUBY')
      t = Time.at(1_700_000_000.5).utc
      puts t.asctime
      p t.to_a
      p Time.at(100).to_r
      p Time.at(1_700_000_000.7654321).round(3).subsec
      puts t.xmlschema(3)
      p t.deconstruct_keys([:year, :month])
    RUBY

    _(result).must_answer <<~'OUT'
      Tue Nov 14 22:13:20 2023
      [20, 13, 22, 14, 11, 2023, 2, 318, false, "UTC"]
      (100/1)
      (153/200)
      2023-11-14T22:13:20.500Z
      {year: 2023, month: 11}
    OUT
  end

  it "Time.at refuses a Hash" do
    result = ze0(<<~'RUBY')
      begin
        Time.at({})
      rescue TypeError => e
        p e.class
      end
    RUBY

    _(result).must_answer "TypeError\n"
  end

  it "Time.at takes in: as the display offset without shifting the instant" do
    result = ze0(<<~'RUBY')
      # `Time.at(epoch, in: offset)` attaches a display utc_offset to the
      # absolute instant (no shift, unlike Time.new's local components).

      p Time.at(0, in: "+09:00").utc_offset
      p Time.at(0, in: "-05:00").utc_offset
      p Time.at(0, in: 3600).utc_offset
    RUBY

    _(result).must_answer <<~'OUT'
      32400
      -18000
      3600
    OUT
  end

  it "Time.at with in: shows the same instant at the named offset" do
    result = ze0(<<~'RUBY')
      p Time.at(0, in: "+09:00").utc_offset
      p Time.at(0, in: "-05:00").utc_offset
      p Time.at(1_600_000_000, in: "+09:00").hour
    RUBY

    _(result).must_answer <<~'OUT'
      32400
      -18000
      21
    OUT
  end

  it "Time.at takes the unit of its fractional argument" do
    result = ze0(<<~'RUBY')
      # Time.at with a unit-scaled fractional second (:millisecond/:microsecond/
      # :nanosecond); the default unit is microseconds.
      p Time.at(0, 500, :millisecond).to_f
      p Time.at(0, 500, :microsecond).to_f
      p Time.at(0, 500, :nanosecond).to_f
      p Time.at(1, 250).to_f

      # MatchData#[] slices the group array with (start, length) or a range.
      md = "2024-01-31".match(/(\d+)-(\d+)-(\d+)/)
      p md[1, 2]
      p md[0, 2]
      p md[1..]
      p md == "2024-01-31".match(/(\d+)-(\d+)-(\d+)/)

      # Float scientific notation zero-pads the exponent to two digits.
      p 5.0e-7
      p 1.0e20
    RUBY

    _(result).must_answer <<~'OUT'
      0.5
      0.0005
      5.0e-07
      1.00025
      ["2024", "01"]
      ["2024-01-31", "2024"]
      ["2024", "01", "31"]
      true
      5.0e-07
      1.0e+20
    OUT
  end

  it "Time.at takes the sub-second part as microseconds" do
    result = ze0(<<~'RUBY')
      p Time.at(1_600_000_000, 500_000).usec
      p Time.at(0, 500_000).subsec
      p Time.at(100, 250_000).nsec
    RUBY

    _(result).must_answer <<~'OUT'
      500000
      (1/2)
      250000000
    OUT
  end

  it "between? and clamp order Times" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 1, 1); a = Time.utc(2000, 1, 1); b = Time.utc(2030, 1, 1)
      p t.between?(a, b)
      p t.clamp(a, b).year
    RUBY

    _(result).must_answer "true\n2026\n"
  end

  it "a civil field outside its range raises, and one that overflows rolls forward" do
    result = ze0(<<~'RUBY')
      # Out-of-range civil fields raise ArgumentError; in-range values that
      # overflow (Feb 30, the 23:59:60 leap second) roll forward instead.

      def c; begin; yield; rescue ArgumentError; "ArgumentError"; end; end
      p c { Time.utc(2020, 13, 1) }
      p c { Time.utc(2020, 1, 32) }
      p c { Time.utc(2020, 1, 1, 25) }
      p c { Time.utc(2020, 1, 1, 23, 60) }
      p Time.utc(2020, 2, 30).month
      p Time.utc(2020, 12, 31, 23, 59, 60).year
    RUBY

    _(result).must_answer <<~'OUT'
      "ArgumentError"
      "ArgumentError"
      "ArgumentError"
      "ArgumentError"
      3
      2021
    OUT
  end

  it "comparing a Time with anything else answers nil rather than raising" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30)
      p(t == 5); p(t != 5); p(t <=> 5); p(t == "x")
      a = Time.utc(2000,1,1); b = Time.utc(2030,1,1)
      p(a < b); p(a <=> b); p(a == a); p(a <=> "z")
      begin; a < 5; rescue ArgumentError; puts "argerr"; end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      nil
      false
      true
      -1
      true
      nil
      argerr
    OUT
  end

  it "deconstruct_keys answers the fields it is asked for" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30)
      p t.deconstruct_keys([:year, :month, :day])
      p t.deconstruct_keys([:hour, :min, :sec])
    RUBY

    _(result).must_answer "{year: 2026, month: 7, day: 16}\n{hour: 13, min: 45, sec: 30}\n"
  end

  it "Comparable falls out of <=>, and equality and hash go by instant" do
    result = ze0(<<~'RUBY')
      # Time includes Comparable, so the whole ordering surface falls out of
      # `<=>`. Equality is by INSTANT, so a Time equals its own UTC copy and they
      # hash alike (which is what makes a Time usable as a Hash key).

      p Time.at(5) < Time.at(6)
      p Time.at(6) > Time.at(5)
      p Time.at(5).between?(Time.at(1), Time.at(9))
      p Time.at(1).clamp(Time.at(2), Time.at(5)).to_i
      p [Time.at(3), Time.at(1), Time.at(2)].sort.map(&:to_i)
      p Time.at(5) == Time.at(5)
      p Time.at(5).getutc == Time.at(5)
      p Time.at(1.5).hash == Time.at(1.5).hash
      p({ Time.at(99) => "found" }[Time.at(99)])
      p (Time.at(5) <=> Time.at(6))
      p (Time.at(5) <=> 5)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      2
      [1, 2, 3]
      true
      true
      true
      "found"
      -1
      nil
    OUT
  end

  it "an out-of-range component names the field it was, and Time plus Time says so" do
    result = ze0(<<~'RUBY')
      # Time's argument errors carry CRuby's exact texts: an out-of-range
      # component names the FIELD ("mon out of range", "mday out of range"), and
      # `Time + Time` says "time + time?". zeo answers generic messages. (Found
      # by the 2026-08-24 probe sweep; matches the TODO(plan P-B) markers in
      # builtins/time.rs.)
      def show
        yield
      rescue StandardError => e
        puts "#{e.class}: #{e.message}"
      end
      show { Time.utc(2001, 13, 1) }
      show { Time.utc(2001, 1, 0) }
      show { t = Time.at(0); t + t }
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: mon out of range
      ArgumentError: mday out of range
      TypeError: time + time?
    OUT
  end

  it "a fixed-offset Time has an offset but no zone name" do
    result = ze0(<<~'RUBY')
      # A fixed-offset Time has no zone NAME: CRuby answers nil where the empty
      # string the broken-down form leaves behind came back.
      p Time.utc(2020, 6, 15, 12, 0, 0).getlocal("+05:30").zone
      p Time.utc(2020, 6, 15, 12, 0, 0).getlocal(19800).zone
      p Time.at(0, in: "+09:00").zone
      p Time.new(2020, 1, 1, 0, 0, 0, "+09:00").zone
      p Time.utc(2020, 1, 1).zone
      p Time.utc(2020, 1, 1).utc?
      p Time.at(0, in: "+09:00").utc_offset
      p Time.new(2020, 1, 1, 0, 0, 0, "+09:00").utc_offset
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      "UTC"
      true
      32400
      32400
    OUT
  end

  it "the civil constructors take a Rational number of seconds" do
    result = ze0(<<~'RUBY')
      p Time.utc(2020, 1, 1, 0, 0, Rational(3, 2)).subsec
      p Time.utc(2020, 1, 1, 0, 0, Rational(3, 2)).sec
      p Time.local(2020, 1, 1, 0, 0, Rational(5, 4)).subsec
    RUBY

    _(result).must_answer <<~'OUT'
      (1/2)
      1
      (1/4)
    OUT
  end

  it "a hash pattern matches a Time through deconstruct_keys" do
    result = ze0(<<~'RUBY')
      t001 = Time.utc(2024, 2, 29, 12, 0, 0)
      p t001.deconstruct_keys([:year])
      case t001
      in { year: 2024 }
        p :matched
      else
        p :no_match
      end
      case t001
      in { year: 1999 } then p :y
      else p :n
      end
      r = (t001 in { year: 2024 }); p r
      r2 = (t001 in { year: 1999 }); p r2
    RUBY

    _(result).must_answer <<~'OUT'
      {year: 2024}
      :matched
      :n
      true
      false
    OUT
  end

  it "a Time read out of a container answers to_i, to_f and ==" do
    result = ze0(<<~'RUBY')
      # A Time read back out of a container is a boxed value, and the poly readers
      # had no arm for it: to_i and to_f answered 0 and equality compared boxes.
      a = [Time.utc(2020, 1, 2)]
      t = a[0]
      p t.year
      p t.to_i
      p t.to_f
      p t == Time.utc(2020, 1, 2)
      p t.eql?(Time.utc(2020, 1, 2))
      p t == Time.utc(2021, 1, 2)

      h = { k: Time.utc(2020, 1, 2) }
      p h[:k].to_i
      p h[:k].to_f
      p h[:k] == Time.utc(2020, 1, 2)

      # a Time with a fractional part keeps it through to_f
      b = [Time.at(1, 500_000)]
      p b[0].to_f
      p b[0].to_i

      # the unboxed forms are unchanged
      u = Time.utc(2020, 1, 2)
      p u.to_i
      p u.to_f
      p u == Time.utc(2020, 1, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      2020
      1577923200
      1577923200.0
      true
      true
      false
      1577923200
      1577923200.0
      true
      1.5
      1
      1577923200
      1577923200.0
      true
    OUT
  end

  it "interpolating a Time calls the Time's own to_s" do
    result = ze0(<<~'RUBY')
      # A Time interpolates via its own `to_s` -- it is an Object with a runtime
      # table, not a registry class, so `call_user_method` has to find the row.

      t = Time.at(1700000000).getutc
      puts "at #{t}"
      puts "#{t.year}-#{t.month}"
      p t.to_s.class
    RUBY

    _(result).must_answer <<~'OUT'
      at 2023-11-14 22:13:20 UTC
      2023-11
      String
    OUT
  end

  it "interpolation prints a Time the way to_s does" do
    result = ze0(<<~'RUBY')
      # Time value in string interpolation calls #to_s (KieranP #2358)
      t = Time.at(0).utc
      puts "at '#{t}'"
      t2 = Time.at(3661).utc
      puts "T=#{t2} end"
      puts "#{Time.at(0).utc}"
    RUBY

    _(result).must_answer <<~'OUT'
      at '1970-01-01 00:00:00 UTC'
      T=1970-01-01 01:01:01 UTC end
      1970-01-01 00:00:00 UTC
    OUT
  end

  it "Time.local reads the offset the named zone had at that instant" do
    result = ze0(<<~'RUBY')
      ENV["TZ"] = "America/Los_Angeles"
      p Time.local(0).utc_offset
      p Time.local(2024, 1, 1).utc_offset
    RUBY

    _(result).must_answer "-28800\n-28800\n"
  end

  it "mktime, local and utc are the three names of the civil constructors" do
    result = ze0(<<~'RUBY')
      # Time.mktime / Time.local / Time.utc — all three name the local
      # (and gm/utc) constructor. Time.now and Time.new were already
      # wired; this test covers the aliases plus the UTC variant that
      # uses a timezone-independent days-from-civil epoch.
      t = Time.now
      puts t.class

      t2 = Time.mktime(2025, 1, 15, 10, 30, 0)
      puts t2.year
      puts t2.month
      puts t2.day
      puts t2.hour
      puts t2.min

      t3 = Time.local(2026, 3, 5)
      puts t3.year
      puts t3.month
      puts t3.day

      t4 = Time.utc(2025, 6, 15, 12, 0, 0)
      puts t4.year
      puts t4.month
      puts t4.day
      puts t4.hour
    RUBY

    _(result).must_answer <<~'OUT'
      Time
      2025
      1
      15
      10
      30
      2026
      3
      5
      2025
      6
      15
      12
    OUT
  end

  it "the month may be a three-letter English abbreviation" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Time.utc does not accept a month NAME ("feb") in the month position.
      #
      # The month argument of the civil constructors takes an English month
      # abbreviation as well as a number. A plain strtoll read those as zero and the
      # constructor rejected them.
      p Time.utc(2020, "feb", 4).mon
      p Time.utc(2020, "FEB", 4).mon
      p Time.utc(2020, "Feb", 4).mon
      p Time.utc(2020, "jan", 1).mon
      p Time.utc(2020, "dec", 31).mon
      p Time.utc(2020, "feb", 4).year
      p Time.utc(2020, "feb", 4).day

      # only the three-letter form is a name; anything else is read as an Integer
      r = (Time.utc(2020, "December", 4).mon rescue $!.class); p r
      p Time.utc(2020, "3", 4).mon
      p Time.utc(2020, 5, 4).mon
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      2
      1
      12
      2020
      4
      ArgumentError
      3
      5
    OUT
  end

  it "Time.new takes in: as the offset, the same as the seventh positional" do
    result = ze0(<<~'RUBY')
      # Time.new(..., in: <off>): the keyword is the utc_offset, like the 7th
      # positional (#2718). Literal "+HH:MM" resolves at compile time; an Integer
      # expression passes through; missing civil fields default.
      p Time.new(2020, 1, 1, 0, 0, 0, in: "+05:00").utc_offset
      p Time.new(2020, 1, 1, 0, 0, 0, in: "-08:00").utc_offset
      p Time.new(2020, in: "+05:00").utc_offset
      p Time.new(2020, 6, 15, 12, 0, 0, in: "+05:30").strftime("%:z")
      p Time.new(2020, 1, 1, 0, 0, 0, in: 3600).utc_offset
    RUBY

    _(result).must_answer <<~'OUT'
      18000
      -28800
      18000
      "+05:30"
      3600
    OUT
  end

  it "Time.new takes a zone as a name, an offset string or a number of seconds" do
    result = ze0(<<~'RUBY')
      p Time.new(2020, 1, 1, 0, 0, 0, "UTC").utc?
      p Time.new(2020, 1, 1, 0, 0, 0, "Z").utc?
      p Time.new(2020, 1, 1, 0, 0, 0, "+0900").utc_offset
      p Time.new(2020, 1, 1, 0, 0, 0, "+09:00:30").utc_offset
      z = "+09:00"
      p Time.new(2020, 1, 1, 0, 0, 0, z).utc_offset
      r = (Time.new(2020, 1, 1, 0, 0, 0, "nope") rescue $!.class); p r
      p Time.new(2020, 1, 1, 0, 0, 0, 3600).utc_offset
      p Time.new(2020, 1, 1, in: "+02:00").utc_offset
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      32400
      32430
      32400
      ArgumentError
      3600
      7200
    OUT
  end

  it "a negative Float epoch floors, so the sub-second part stays positive" do
    result = ze0(<<~'RUBY')
      # A negative epoch floors: second -1 plus a POSITIVE sub-second remainder,
      # never second 0 minus half.

      p Time.at(-0.5).to_i
      p Time.at(-0.5).nsec
      p Time.at(-1).to_i
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      500000000
      -1
    OUT
  end

  it "the civil constructors read a numeric string as a number" do
    result = ze0(<<~'RUBY')
      p Time.utc("2020", "3", "4").year
      p Time.utc("2020", "3", "4").month
      p Time.local("2021", "5").year
    RUBY

    _(result).must_answer <<~'OUT'
      2020
      3
      2021
    OUT
  end

  it "adding a Rational moves the sub-second part" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30)
      p (t + Rational(1, 2)).subsec
      p (t - Rational(1, 2)).subsec
      p (t + Rational(1, 4)).subsec
    RUBY

    _(result).must_answer <<~'OUT'
      (1/2)
      (1/2)
      (1/4)
    OUT
  end

  it "the weekday predicates, eql? and getgm" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30)   # Thursday
      p t.sunday?; p t.thursday?; p t.saturday?
      p t.eql?(t); p t.eql?(Time.utc(2020,1,1)); p t.eql?(5)
      x = t.getgm; p x.year
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      false
      false
      2026
    OUT
  end

  it "respond_to? knows Time's own readers and no others" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30)
      p t.respond_to?(:no_such_method)
      p t.respond_to?(:succ)
      p t.respond_to?(:year)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
    OUT
  end

  it "round, floor and ceil with no argument answer whole seconds" do
    result = ze0(<<~'RUBY')
      p Time.at(1.5).round.to_i
      p Time.at(1.9).floor.to_i
      p Time.at(1.1).ceil.to_i
      p Time.at(1.4).round.to_i
    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      2
      1
    OUT
  end

  it "round, floor and ceil refuse a negative digit count" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Time#round with negative digits rounds where ruby raises ArgumentError.
      #
      # Time#round/#floor/#ceil with a negative digit count is CRuby's
      # ArgumentError; the count was clamped to zero and the call answered a Time.
      t001 = Time.utc(2020, 1, 1, 0, 0, 1, 123456)
      r001 = (t001.round(-1) rescue $!.class); p r001
      r002 = (t001.floor(-1) rescue $!.class); p r002
      r003 = (t001.ceil(-1) rescue $!.class); p r003
      p Time.utc(2020, 1, 1, 0, 0, 1, 123456).round(3).usec
      p Time.utc(2020, 1, 1, 0, 0, 1, 123456).floor(3).usec
      p Time.utc(2020, 1, 1, 0, 0, 1, 123456).ceil(3).usec
      p Time.utc(2020, 1, 1, 0, 0, 1, 500000).round.sec
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      123000
      123000
      124000
      2
    OUT
  end

  it "shifting a Time by anything but a number raises TypeError" do
    result = ze0(<<~'RUBY')
      # Time shifts by a number of seconds. Anything else is CRuby's TypeError; it
      # was read as an integer instead, so a String shifted the clock by zero and a
      # nil by whatever the slot held.
      t = Time.utc(2020,1,2)
      p((t + "x" rescue $!.class))
      p((t - "x" rescue $!.class))
      p((t + nil rescue $!.class))
      p((t + [1] rescue $!.class))
      p((t + "x" rescue $!.message))
      p((t + 60).min)
      p((t - 60).min)
      p((t + 1.5).usec)
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      TypeError
      TypeError
      TypeError
      "can't convert String into an exact number"
      1
      59
      500000
    OUT
  end

  it "Time.new reads each part of a time string in base ten" do
    result = ze0(<<~'RUBY')
      # Time.new reads each part of a time string in base ten, so 08 and 09
      # are the eighth and ninth, and its helpers leave no backtrace row and
      # no private method a program can list.

      p Time.new("2024-08-09 08:09:09", in: "+00:00")
      p Time.new("2024-09-08 09:08:07 +09:00")
      p Time.new("0999-01-01 00:00:00.09", in: "UTC").subsec
      p Time.new("2024-01-01 00:00:00.0800", in: "UTC").subsec
      p Time.private_methods(false).sort
      begin
        Time.new("2024-08-9 08:09:09")
      rescue ArgumentError => e
        p e
        puts e.backtrace
      end

    RUBY

    _(result).must_answer <<~'OUT'
      2024-08-09 08:09:09 +0000
      2024-09-08 09:08:07 +0900
      (9/100)
      (2/25)
      [:_load, :inherited, :initialize]
      #<ArgumentError: two digits mday is expected after '-': -9 08:09:09>
      core/time/time_test.rb:11:in 'Time#initialize'
      core/time/time_test.rb:11:in '<main>'
    OUT
  end

  it "xmlschema prints the instant as an ISO 8601 UTC stamp" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30)
      p t.xmlschema
    RUBY

    _(result).must_answer "\"2026-07-16T13:45:30Z\"\n"
  end

  it "utc, gmtime and localtime write back to the receiver where the get forms do not" do
    result = ze0(<<~'RUBY')
      # Time#utc / #gmtime / #localtime mutate the receiver (#2637): sp_Time is a
      # value struct, so an lvalue receiver (local, ivar) takes a write-back
      # assignment. The get* flavors stay non-destructive. (Aliasing two variables to
      # one Time and observing the mutation through the other is a value-type limit:
      # assignment copies.)
      v = Time.at(0)
      v.utc
      p v.utc?
      w = Time.at(0)
      w.gmtime
      p w.utc?
      x = Time.utc(2020, 1, 1)
      x.localtime
      p x.utc?
      y = Time.at(0)
      p y.utc.utc?
      z = Time.at(0)
      z.getutc
      p z.utc?
      class Holder
        def initialize; @t = Time.at(0); end
        def flip; @t.utc; end
        def utc?; @t.utc?; end
      end
      h = Holder.new
      h.flip
      p h.utc?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
      true
    OUT
  end
end
