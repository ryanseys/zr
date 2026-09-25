# frozen_string_literal: true

require "spec_helper"

describe "TracePoint programs" do
  it "attr reader call backtrace line" do
    result = zr(<<~'RUBY')
      # CRuby compiles an `attr_*` accessor iseq-less, so it appears in no
      # backtrace. zr's is frameless too -- but it still stamped its own line, and
      # a stamp with no frame of its own lands in the CALLER's and is never
      # restored: every later raise in `boom` reported the `attr_reader` line.
      class Holder
        attr_reader :a
        attr_writer :w
        attr_accessor :b

        def initialize
          @a = 1
          @b = 2
        end

        def boom
          a.nope
        end

        def wboom
          self.w = 1
          freeze
          self.w = 2
        end

        def bboom
          b
          self.b = 3
          b.nope
        end

        # A HAND-WRITTEN reader keeps its frame -- only the generated shape is
        # iseq-less.
        def hand
          hand_reader.nope
        end

        def hand_reader = @a
      end

      begin; Holder.new.boom; rescue NoMethodError => e; p e.backtrace.first(2); end
      begin; Holder.new.wboom; rescue FrozenError => e; p e.backtrace.first(2); end
      begin; Holder.new.bboom; rescue NoMethodError => e; p e.backtrace.first(2); end
      begin; Holder.new.hand; rescue NoMethodError => e; p e.backtrace.first(2); end
      begin; Holder.new.a(1); rescue ArgumentError => e; p [e.message, e.backtrace.first]; end
      frozen = Holder.new.freeze
      begin; frozen.b = 9; rescue FrozenError => e; p e.backtrace.first(2); end
    RUBY

    _(result).must_answer <<~'OUT'
      ["core/tracepoint/tracepoint_test.rb:16:in 'Holder#boom'", "core/tracepoint/tracepoint_test.rb:40:in '<main>'"]
      ["core/tracepoint/tracepoint_test.rb:22:in 'Holder#wboom'", "core/tracepoint/tracepoint_test.rb:41:in '<main>'"]
      ["core/tracepoint/tracepoint_test.rb:28:in 'Holder#bboom'", "core/tracepoint/tracepoint_test.rb:42:in '<main>'"]
      ["core/tracepoint/tracepoint_test.rb:34:in 'Holder#hand'", "core/tracepoint/tracepoint_test.rb:43:in '<main>'"]
      ["wrong number of arguments (given 1, expected 0)", "core/tracepoint/tracepoint_test.rb:44:in '<main>'"]
      ["core/tracepoint/tracepoint_test.rb:46:in '<main>'"]
    OUT
  end

  it "backtrace frames match cruby across definition kinds" do
    result = zr(<<~'RUBY')
      # The comprehensive frame battery, all verbatim ruby 4.0.6 (invoked as
      # `-e`, the same label this harness compiles under): method labels
      # (Object#m / Foo#m / Foo.cm / M.modfun / M#mixed), lexical block
      # frames (`block in ...`), caller windows (0-start, past-the-top nil,
      # (start, length)), re-raise preserving the original stack, custom
      # backtraces (`raise cls, msg, array`, set_backtrace, nil clears,
      # never-raised nil), proc frames through Proc#call, send transparency,
      # and full_message's report shape. Known divergences excluded and
      # catalogued: no C-method frames (`Array#each` rows), arity errors
      # attribute to the call site rather than the callee's def line.

      def plain; raise "x"; rescue => e; puts e.backtrace.first; end
      plain
      class Foo
        def m; raise "x"; rescue => e; puts e.backtrace.first; end
        def self.cm; raise "x"; rescue => e; puts e.backtrace.first; end
      end
      Foo.new.m
      Foo.cm
      module M
        def self.modfun; raise "x"; rescue => e; puts e.backtrace.first; end
        def mixed; raise "x"; rescue => e; puts e.backtrace.first; end
      end
      M.modfun
      class Bar; include M; end
      Bar.new.mixed
      def with_block
        [1].each { raise "x" }
      rescue => e
        puts e.backtrace[0]
      end
      with_block
      def nested_blocks
        [1].each do
          [2].each do
            raise "x"
          end
        end
      rescue => e
        puts e.backtrace[0]
      end
      nested_blocks
      def c_inner
        puts caller.inspect
        puts caller(0).first
        puts caller(2).inspect
        puts caller(1, 1).inspect
        puts caller(9).inspect
      end
      def c_mid; c_inner; end
      c_mid
      def rr_inner; raise "orig"; end
      def rr_outer
        rr_inner
      rescue => e
        raise
      end
      begin
        rr_outer
      rescue => e
        puts e.backtrace.first(3).inspect
      end
      begin
        raise RuntimeError, "custom", ["fake.rb:1:in 'x'", "fake.rb:2:in 'y'"]
      rescue => e
        puts e.backtrace.inspect
      end
      e2 = RuntimeError.new("sb")
      e2.set_backtrace("one_line")
      puts e2.backtrace.inspect
      e2.set_backtrace(nil)
      puts e2.backtrace.inspect
      puts RuntimeError.new("never").backtrace.inspect
      def proc_caller(p) = p.call
      pr = proc { raise "in proc" }
      begin
        proc_caller(pr)
      rescue => e
        puts e.backtrace.first(3).inspect
      end
      def sent; raise "via send"; end
      begin
        send(:sent)
      rescue => e
        puts e.backtrace.first(2).inspect
      end
      begin
        raise ArgumentError, "fm"
      rescue => e
        puts e.full_message(highlight: false)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      core/tracepoint/tracepoint_test.rb:12:in 'Object#plain'
      core/tracepoint/tracepoint_test.rb:15:in 'Foo#m'
      core/tracepoint/tracepoint_test.rb:16:in 'Foo.cm'
      core/tracepoint/tracepoint_test.rb:21:in 'M.modfun'
      core/tracepoint/tracepoint_test.rb:22:in 'M#mixed'
      core/tracepoint/tracepoint_test.rb:28:in 'block in Object#with_block'
      core/tracepoint/tracepoint_test.rb:36:in 'block (2 levels) in Object#nested_blocks'
      ["core/tracepoint/tracepoint_test.rb:50:in 'Object#c_mid'", "core/tracepoint/tracepoint_test.rb:51:in '<main>'"]
      core/tracepoint/tracepoint_test.rb:45:in 'Object#c_inner'
      ["core/tracepoint/tracepoint_test.rb:51:in '<main>'"]
      ["core/tracepoint/tracepoint_test.rb:50:in 'Object#c_mid'"]
      nil
      ["core/tracepoint/tracepoint_test.rb:52:in 'Object#rr_inner'", "core/tracepoint/tracepoint_test.rb:54:in 'Object#rr_outer'", "core/tracepoint/tracepoint_test.rb:59:in '<main>'"]
      ["fake.rb:1:in 'x'", "fake.rb:2:in 'y'"]
      ["one_line"]
      nil
      nil
      ["core/tracepoint/tracepoint_test.rb:75:in 'block in <main>'", "core/tracepoint/tracepoint_test.rb:74:in 'Object#proc_caller'", "core/tracepoint/tracepoint_test.rb:77:in '<main>'"]
      ["core/tracepoint/tracepoint_test.rb:81:in 'Object#sent'", "core/tracepoint/tracepoint_test.rb:83:in '<main>'"]
      core/tracepoint/tracepoint_test.rb:88:in '<main>': fm (ArgumentError)
      
        raise ArgumentError, "fm"
              ^^^^^^^^^^^^^^^^^^^
    OUT
  end

  it "backtrace names the scope and the call line" do
    result = zr(<<~'RUBY', files: beside("lib/backtrace_scopes.rb"))
      # Two questions a backtrace answers, both about WHERE a frame is rather
      # than what it does. zr gives the same answers as ruby.
      #
      # (1) The scope a block hangs off. A `require` zr splices into its
      #     requiring file still has a scope of its own: ruby names a required
      #     file's top level `<top (required)>`, never the requiring file's
      #     `<main>`. It is not cosmetic -- a library filters its own frames out
      #     of a backtrace by path and by name.
      #
      # (2) The line a CALL is reported at. Ruby reports the line the method
      #     NAME sits on, which for a chained or block-receiver call is not the
      #     line the expression starts on. Coverage still counts the first line;
      #     the two are different questions and are answered separately.
      require_relative "lib/backtrace_scopes"

      def show(label)
        yield
      rescue => e
        puts "#{label}:"
        puts e.backtrace.map { |f| "  #{f.sub(__dir__ + "/", "")}" }
      end

      show("blocks at a required file's top level") { NESTED_BLOCKS.call }
      show("a method in a required file") { a_method_here }

      show("a chained call") do
        Chained
          .boom
      end

      show("a call on a block's value") do
        [1].map do |i|
          i
        end.frozen_method_that_is_missing
      end

      # The receiver and the arguments keep their OWN lines: a raise while they
      # are being evaluated is reported where it was written, not at the name.
      def raises_while_evaluating = raise("raised building the receiver")
      show("a raise in the receiver of a chained call") do
        raises_while_evaluating
          .to_s
      end

    RUBY

    _(result).must_answer <<~'OUT'
      blocks at a required file's top level:
        lib/backtrace_scopes.rb:6:in 'block (2 levels) in <top (required)>'
        lib/backtrace_scopes.rb:5:in 'Array#each'
        lib/backtrace_scopes.rb:5:in 'block in <top (required)>'
        core/tracepoint/tracepoint_test.rb:23:in 'block in <main>'
        core/tracepoint/tracepoint_test.rb:17:in 'Object#show'
        core/tracepoint/tracepoint_test.rb:23:in '<main>'
      a method in a required file:
        lib/backtrace_scopes.rb:11:in 'Object#a_method_here'
        core/tracepoint/tracepoint_test.rb:24:in 'block in <main>'
        core/tracepoint/tracepoint_test.rb:17:in 'Object#show'
        core/tracepoint/tracepoint_test.rb:24:in '<main>'
      a chained call:
        lib/backtrace_scopes.rb:15:in 'Chained.boom'
        core/tracepoint/tracepoint_test.rb:28:in 'block in <main>'
        core/tracepoint/tracepoint_test.rb:17:in 'Object#show'
        core/tracepoint/tracepoint_test.rb:26:in '<main>'
      a call on a block's value:
        core/tracepoint/tracepoint_test.rb:34:in 'block in <main>'
        core/tracepoint/tracepoint_test.rb:17:in 'Object#show'
        core/tracepoint/tracepoint_test.rb:31:in '<main>'
      a raise in the receiver of a chained call:
        core/tracepoint/tracepoint_test.rb:39:in 'Object#raises_while_evaluating'
        core/tracepoint/tracepoint_test.rb:41:in 'block in <main>'
        core/tracepoint/tracepoint_test.rb:17:in 'Object#show'
        core/tracepoint/tracepoint_test.rb:40:in '<main>'
    OUT
  end

  it "builtin ruby method fires call and return" do
    result = zr(<<~'RUBY')
      # A :call and a :return fire around the methods CRuby writes in Ruby of its
      # own, at the place each one stands in CRuby's builtin sources; a method
      # whose Ruby definition stands only under a JIT stays C's.
      ev = []
      tp = TracePoint.new(:call, :return) { |t| ev << [t.event, t.method_id, t.path, t.lineno, t.defined_class] }
      tp.enable
      [1].each {}
      3.times {}
      1.tap {}
      [1].map {}
      Integer("3")
      [3, 1].sort
      tp.disable
      ev.each { |e| p e }

    RUBY

    _(result).must_answer <<~'OUT'
      [:call, :times, "<internal:numeric>", 255, Integer]
      [:return, :times, "<internal:numeric>", 266, Integer]
      [:call, :tap, "<internal:kernel>", 89, Kernel]
      [:return, :tap, "<internal:kernel>", 93, Kernel]
      [:call, :Integer, "<internal:kernel>", 288, Kernel]
      [:return, :Integer, "<internal:kernel>", 293, Kernel]
      [:call, :disable, "<internal:trace_point>", 297, TracePoint]
    OUT
  end

  it "c call and set trace func fire around c methods" do
    result = zr(<<~'RUBY')
      # TracePoint's :c_call and :c_return fire around each method CRuby
      # writes in C, where the program calls it: an operator, an accessor, a
      # method called with a block and the block's own calls.
      class Point
        attr_reader :x

        def initialize = @x = 1
        def moved = x + 1
      end

      seen = []
      point = Point.new
      trace = TracePoint.new(:c_call, :c_return) do |tp|
        seen << [tp.event, tp.method_id, tp.defined_class, tp.self.class, tp.lineno, (tp.return_value if tp.event == :c_return)]
      end
      trace.enable
      sum = 1 + 2
      doubled = [1, 2].map { |v| v * 2 }
      upper = "a".upcase
      point.moved
      sorted = [3, 1].sort
      found = { a: 1 }[:a]
      trace.disable
      seen.each { |row| p row }
      p [sum, doubled, upper, sorted, found]

      # set_trace_func takes the same events and more, by their old names; a
      # singleton method's class is its object, and a C method has no binding.
      class Point
        def self.origin = new
      end
      hooked = []
      set_trace_func proc { |event, file, line, id, binding, klass| hooked << [event, File.basename(file), line, id, binding.class, klass] }
      Point.origin.moved
      set_trace_func(nil)
      # The hook's own set_trace_func calls are left out.
      hooked.reject { |row| row[3] == :set_trace_func }.each { |row| p row }

    RUBY

    _(result).must_answer <<~'OUT'
      [:c_call, :+, Integer, Integer, 17, nil]
      [:c_return, :+, Integer, Integer, 17, 3]
      [:c_call, :map, Array, Array, 18, nil]
      [:c_call, :*, Integer, Integer, 18, nil]
      [:c_return, :*, Integer, Integer, 18, 2]
      [:c_call, :*, Integer, Integer, 18, nil]
      [:c_return, :*, Integer, Integer, 18, 4]
      [:c_return, :map, Array, Array, 18, [2, 4]]
      [:c_call, :upcase, String, String, 19, nil]
      [:c_return, :upcase, String, String, 19, "A"]
      [:c_call, :x, Point, Point, 8, nil]
      [:c_return, :x, Point, Point, 8, 1]
      [:c_call, :+, Integer, Integer, 8, nil]
      [:c_return, :+, Integer, Integer, 8, 2]
      [:c_call, :sort, Array, Array, 21, nil]
      [:c_return, :sort, Array, Array, 21, [1, 3]]
      [:c_call, :[], Hash, Hash, 22, nil]
      [:c_return, :[], Hash, Hash, 22, 1]
      [3, [2, 4], "A", [1, 3], 1]
      ["line", "tracepoint_test.rb", 34, nil, Binding, nil]
      ["call", "tracepoint_test.rb", 30, :origin, Binding, Point]
      ["call", "tracepoint_test.rb", 7, :initialize, Binding, Point]
      ["return", "tracepoint_test.rb", 7, :initialize, Binding, Point]
      ["return", "tracepoint_test.rb", 30, :origin, Binding, Point]
      ["call", "tracepoint_test.rb", 8, :moved, Binding, Point]
      ["c-call", "tracepoint_test.rb", 8, :x, NilClass, Point]
      ["c-return", "tracepoint_test.rb", 8, :x, NilClass, Point]
      ["c-call", "tracepoint_test.rb", 8, :+, NilClass, Integer]
      ["c-return", "tracepoint_test.rb", 8, :+, NilClass, Integer]
      ["return", "tracepoint_test.rb", 8, :moved, Binding, Point]
      ["line", "tracepoint_test.rb", 35, nil, Binding, nil]
    OUT
  end

  it "exception backtrace empty" do
    result = zr(<<~'RUBY')
      # Exception#backtrace carries the real stamped frames (frame tracking):
      # non-empty after a raise, innermost line first. The path prefix is the
      # compile-time input path, so assertions stay path-portable.
      begin
        raise ArgumentError, "bad arg"
      rescue => e
        puts e.class
        puts e.message
        puts e.backtrace.empty?
        puts e.backtrace.first.end_with?(":5:in '<main>'")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      bad arg
      false
      true
    OUT
  end

  it "exception backtrace full message and inspect" do
    result = zr(<<~'RUBY')
      # backtrace carries the real stamped frames; full_message renders the
      # uncaught-report shape from them; inspect renders "#<Class: msg>" (or
      # the bare class name when the message is empty). Expected output is
      # verbatim ruby 4.0.6 (the harness compiles as `-e`, same as the
      # oracle's own `-e` labeling).

      begin
        raise ArgumentError, "bad"
      rescue => e
        p e.backtrace
        p e.inspect
        puts e.full_message
      end
      p StandardError.new("").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ["core/tracepoint/tracepoint_test.rb:8:in '<main>'"]
      "#<ArgumentError: bad>"
      core/tracepoint/tracepoint_test.rb:8:in '<main>': bad (ArgumentError)
      
        raise ArgumentError, "bad"
              ^^^^^^^^^^^^^^^^^^^^
      "StandardError"
    OUT
  end

  it "exception backtrace wired" do
    result = zr(<<~'RUBY')
      # Exception#backtrace returns an Array of frame strings (method-granularity,
      # populated only in --debug builds; release returns []). This guards the
      # dispatch shape that's release-stable -- backtrace is an Array, not a
      # hardcoded empty literal swallowing the receiver.
      begin
        raise "boom"
      rescue => e
        bt = e.backtrace
        puts bt.class           # Array
        puts bt.is_a?(Array)    # true
        puts e.message          # boom
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Array
      true
      boom
    OUT
  end

  it "frozen error backtrace extra frame" do
    result = zr(<<~'RUBY')
      # CRuby answers `<<` and `[]=` on a String/Array/Hash with a SPECIALIZED VM
      # instruction (`opt_ltlt`, `opt_aset`), which pushes no control frame -- so a
      # raise from inside one names only the caller. The general fallback does frame,
      # and that is per RECEIVER TYPE: `opt_ltlt` covers String and Array and nothing
      # else, so `IO#<<` still reports itself.
      begin
        "x".freeze << "y"
      rescue FrozenError => e
        p e.backtrace
      end

      begin
        [].freeze << 1
      rescue FrozenError => e
        p e.backtrace
      end

      begin
        [].freeze[0] = 1
      rescue FrozenError => e
        p e.backtrace
      end

      begin
        {}.freeze[:a] = 1
      rescue FrozenError => e
        p e.backtrace
      end

      # A row with no specialized instruction keeps its frame.
      begin
        "s".freeze[0] = "z"
      rescue FrozenError => e
        p e.backtrace.first
      end

      begin
        "abc".freeze.concat("d")
      rescue FrozenError => e
        p e.backtrace.first
      end

      begin
        [1, 2].freeze.sort!
      rescue FrozenError => e
        p e.backtrace.first
      end

      # A HAND-WRITTEN `<<` is an ordinary method and frames like one.
      class Sink
        def <<(_v) = raise("no")
      end
      begin
        Sink.new << 1
      rescue RuntimeError => e
        p e.backtrace.first
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["core/tracepoint/tracepoint_test.rb:7:in '<main>'"]
      ["core/tracepoint/tracepoint_test.rb:13:in '<main>'"]
      ["core/tracepoint/tracepoint_test.rb:19:in '<main>'"]
      ["core/tracepoint/tracepoint_test.rb:25:in '<main>'"]
      "core/tracepoint/tracepoint_test.rb:32:in 'String#[]='"
      "core/tracepoint/tracepoint_test.rb:38:in 'String#concat'"
      "core/tracepoint/tracepoint_test.rb:44:in 'Array#sort!'"
      "core/tracepoint/tracepoint_test.rb:51:in 'Sink#<<'"
    OUT
  end

  it "kernel conversion backtrace frame" do
    result = zr(<<~'RUBY')
      # `Kernel#Integer` and its family are ordinary cfuncs in CRuby, so they push a
      # control frame and a raise from inside one names them. zr's codegen calls
      # them through a fast path that never reaches the dispatch boundary where a
      # builtin's frame is otherwise pushed, so the frame is pushed in the row.
      begin
        Integer("zz")
      rescue ArgumentError => e
        p e.backtrace
      end

      begin
        Hash([[1, 2]])
      rescue TypeError => e
        p e.backtrace
      end

      begin
        Float("zz")
      rescue ArgumentError => e
        p e.backtrace.first
      end

      begin
        Rational("x")
      rescue ArgumentError => e
        p e.backtrace.first
      end

      begin
        Integer(nil)
      rescue TypeError => e
        p e.backtrace.first
      end

      # The DYNAMIC route reaches the dispatch boundary as well as the row, and must
      # still show ONE frame -- `synthetic_c_frame` drops an exact repeat.
      begin
        send(:Integer, "zz")
      rescue ArgumentError => e
        p e.backtrace
      end

      begin
        method(:Integer).call("zz")
      rescue ArgumentError => e
        p e.backtrace.first
      end

      def wrapped(s) = Integer(s)
      begin
        wrapped("zz")
      rescue ArgumentError => e
        p e.backtrace.first(2)
      end

      # `exception: false` answers nil rather than raising, so nothing is framed.
      p [Integer("zz", exception: false), Float("zz", exception: false)]
    RUBY

    _(result).must_answer <<~'OUT'
      ["core/tracepoint/tracepoint_test.rb:6:in 'Kernel#Integer'", "core/tracepoint/tracepoint_test.rb:6:in '<main>'"]
      ["core/tracepoint/tracepoint_test.rb:12:in 'Kernel#Hash'", "core/tracepoint/tracepoint_test.rb:12:in '<main>'"]
      "core/tracepoint/tracepoint_test.rb:18:in 'Kernel#Float'"
      "core/tracepoint/tracepoint_test.rb:24:in 'Kernel#Rational'"
      "core/tracepoint/tracepoint_test.rb:30:in 'Kernel#Integer'"
      ["core/tracepoint/tracepoint_test.rb:38:in 'Kernel#Integer'", "core/tracepoint/tracepoint_test.rb:38:in '<main>'"]
      "core/tracepoint/tracepoint_test.rb:44:in 'Kernel#Integer'"
      ["core/tracepoint/tracepoint_test.rb:49:in 'Kernel#Integer'", "core/tracepoint/tracepoint_test.rb:49:in 'Object#wrapped'"]
      [nil, nil]
    OUT
  end

  it "line binding sees a blocks locals" do
    result = zr(<<~'RUBY')
      # A :line hook reads the Binding of the frame the line runs in, which
      # holds the locals of a block and of the method around it, even where
      # nothing in the block asks for a binding itself.
      def outer(a, b = 2)
        [1].map { |x| x + a + b }
      end

      seen = []
      trace = TracePoint.new(:line) { |tp| seen << [tp.lineno, tp.binding.local_variables.sort] }
      trace.enable { outer(1) }
      seen.each { |row| p row }

    RUBY

    _(result).must_answer <<~'OUT'
      [10, [:seen, :trace]]
      [5, [:a, :b]]
      [5, [:a, :b, :x]]
    OUT
  end

  it "parameters and a targeted enable" do
    result = zr(<<~'RUBY')
      # TracePoint#parameters answers the parameters of the code an event is
      # for, and enable(target:) sees only the events of the target's code and
      # of the blocks written inside it, never a C event.
      def foo(a, b = 1, *r, k:, &blk) = [1].each { |x, y| x }

      seen = []
      tp = TracePoint.new(:call, :b_call, :c_call, :return) { |t| seen << [t.event, t.method_id, t.parameters] }
      tp.enable { foo(1, k: 2) }
      seen.each { |row| p row }

      def bar = [1].map { |v| v + 1 }
      def baz = bar

      seen.clear
      targeted = TracePoint.new(:call, :line, :b_call, :return, :c_call) { |t| seen << [t.event, t.lineno, t.method_id] }
      targeted.enable(target: method(:bar)) { baz; bar }
      seen.each { |row| p row }
      p targeted.enabled?

      def lines
        a = 1
        b = 2
        a + b
      end
      seen.clear
      TracePoint.new(:line) { |t| seen << t.lineno }.enable(target: method(:lines), target_line: 22) { lines }
      p seen

      p((TracePoint.new(:line) {}.enable(target_line: 3) rescue $!))
      p((TracePoint.new(:line) {}.enable(target: 1) rescue $!))
      p((TracePoint.new(:call) {}.enable(target: method(:puts)) rescue $!))
      p((TracePoint.new(:call) {}.enable(target: method(:bar), target_line: 3) rescue $!))
      p((TracePoint.new(:c_call) {}.enable(target: method(:bar)) rescue $!))

    RUBY

    _(result).must_answer <<~'OUT'
      [:b_call, nil, []]
      [:call, :foo, [[:req, :a], [:opt, :b], [:rest, :r], [:keyreq, :k], [:block, :blk]]]
      [:c_call, :each, []]
      [:b_call, :foo, [[:opt, :x], [:opt, :y]]]
      [:return, :foo, [[:req, :a], [:opt, :b], [:rest, :r], [:keyreq, :k], [:block, :blk]]]
      [:call, 11, :bar]
      [:b_call, 11, :bar]
      [:line, 11, :bar]
      [:return, 11, :bar]
      [:call, 11, :bar]
      [:b_call, 11, :bar]
      [:line, 11, :bar]
      [:return, 11, :bar]
      false
      [22]
      #<ArgumentError: only target_line is specified>
      #<ArgumentError: specified target is not supported>
      #<ArgumentError: specified target is not supported>
      #<ArgumentError: target_line is specified, but line event is not specified>
      false
    OUT
  end

  it "set trace func installs a hook" do
    result = zr(<<~'RUBY')
      # `set_trace_func` is a real row: `defined?`, `private_method_defined?`
      # and clearing with nil answer as ruby does, and a Proc it takes is
      # called with each event as `(event, file, line, id, binding, klass)`.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("defined?") { defined?(set_trace_func) }
      show("private_method_defined?") { Kernel.private_method_defined?(:set_trace_func) }
      show("clearing with nil") { set_trace_func(nil) }

      events = []
      show("installing a Proc") do
        set_trace_func(proc { |ev, _file, _line, id, _binding, _klass| events << [ev, id] })
        :installed
      end
      def traced = 1
      traced
      set_trace_func(nil) rescue nil
      show("the hook fired") { events.any? { |ev, id| ev == "call" && id == :traced } }

    RUBY

    _(result).must_answer <<~'OUT'
      defined?: "method"
      private_method_defined?: true
      clearing with nil: nil
      installing a Proc: :installed
      the hook fired: true
    OUT
  end

  it "trace var" do
    result = zr(<<~'RUBY')
      # `trace_var` runs something on every assignment RUBY makes to a global.
      # (`set_trace_func`, the other half of Kernel's tracing surface, is not here:
      # it hands its hook a Binding at each event, which this runtime has no way to
      # build from a trace point.)
      $seen = []
      trace_var(:$watched) { |v| $seen << v }
      $watched = 1
      $watched = 2
      p $seen

      # `untrace_var` answers what it dropped, and the hook stops.
      p untrace_var(:$watched).size
      $watched = 3
      p $seen

      # Several hooks on one name run NEWEST FIRST, and either form registers one:
      # a block, or a command object.
      $out = []
      command = proc { |v| $out << [:command, v] }
      trace_var(:$several, command)
      trace_var(:$several) { |v| $out << [:block, v] }
      $several = :first
      p $out

      # Naming the command drops just that one.
      p untrace_var(:$several, command).size
      $out.clear
      $several = :second
      p $out

      # A hook may assign the variable it watches without re-entering itself.
      $clamped = 0
      trace_var(:$clamped) { |v| $clamped = 10 if v > 10 }
      $clamped = 5
      p $clamped
      $clamped = 99
      p $clamped

      # A String names the same variable a Symbol does.
      $out.clear
      trace_var("$by_string") { |v| $out << v }
      $by_string = :ok
      p $out

      # `trace_var` answers nil; a name nothing ever assigns simply never fires.
      p(trace_var(:$never_assigned) { |v| raise "unreachable" })
      p untrace_var(:$never_assigned).size

      # Without a command and without a block there is nothing to register.
      begin
        trace_var(:$no_command)
      rescue ArgumentError => e
        p [:no_command, e.message]
      end

      # `untrace_var` on a name that was neither assigned nor traced is a NameError.
      begin
        untrace_var(:$unknown_entirely)
      rescue NameError => e
        p [:unknown, e.message]
      end

      # The runtime's own seeding is not an assignment, so tracing a predefined
      # global sees only what the PROGRAM writes to it.
      $out.clear
      trace_var(:$;) { |v| $out << v }
      $; = ","
      p $out
      untrace_var(:$;)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      1
      [1, 2]
      [[:block, :first], [:command, :first]]
      1
      [[:block, :second]]
      5
      10
      [:ok]
      nil
      1
      [:no_command, "tried to create Proc object without a block"]
      [:unknown, "undefined global variable $unknown_entirely"]
      [","]
    OUT
  end

  it "the lifecycle and error shapes answer, and the event streams match the oracle line for line" do
    result = zr(<<~'RUBY', path: "core/tracepoint/tracepoint.rb")
      # TracePoint: lifecycle and error shapes, then oracle-matched event streams
      # over methods, class bodies, blocks, raises, and an unwinding return. Every
      # handler filters to this file's own path: CRuby implements enable/disable
      # in Ruby, so they inject <internal:trace_point> events zr's native ones
      # never fire. Line numbers ARE the expectation -- re-bless after any edit.
      def hum(n)
        t = n * 2
        t + 1
      end

      def unwind
        raise IndexError, "deep"
      end

      class Melody
        def notes
          %w[c e g]
        end
        def self.tempo
          120
        end
      end

      def mine?(t)
        File.basename(t.path) == "tracepoint.rb"
      end

      # -- lifecycle and error shapes (nothing enabled yet) --
      begin
        TracePoint.new(:line)
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      begin
        TracePoint.new(:bogus) { }
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      tp = TracePoint.new(:line) { }
      p tp.enabled?
      p tp
      begin
        tp.lineno
      rescue RuntimeError => e
        p [e.class, e.message]
      end
      p(tp.enable { 42 })
      p tp.enabled?
      p tp.enable
      p tp.enable
      p tp.disable
      p tp.disable

      # -- methods and a class method: call/line/return with attributes --
      ev = []
      t1 = TracePoint.new(:call, :return, :line) do |t|
        ev << [t.event, t.lineno, t.method_id, t.callee_id, t.defined_class.to_s] if mine?(t)
      end
      t1.enable
      hum(3)
      Melody.tempo
      t1.disable
      ev.each { |e| p e }

      # -- inspect inside a handler (path-normalized) and outside --
      ins = nil
      t2 = TracePoint.new(:call) { |t| ins = t.inspect if mine?(t) }
      t2.enable
      hum(1)
      t2.disable
      p ins.sub(/\S*tracepoint\.rb/, "tracepoint.rb")
      p t2

      # -- a class body: class/end events around its body lines --
      ev2 = []
      t3 = TracePoint.new(:class, :end, :line) do |t|
        ev2 << [t.event, t.lineno, t.method_id, t.defined_class.to_s] if mine?(t)
      end
      t3.enable
      class Chord
        ROOT = "c"
      end
      t3.disable
      ev2.each { |e| p e }

      # -- block iterations refire the block's line --
      ev3 = []
      t4 = TracePoint.new(:line) { |t| ev3 << [t.lineno, t.method_id] if mine?(t) }
      t4.enable
      doubled = [10, 20].map { |v| v + 1 }
      t4.disable
      p doubled
      ev3.each { |e| p e }

      # -- raise inside a method, unwinding return --
      ev4 = []
      t5 = TracePoint.new(:call, :return, :raise) do |t|
        if mine?(t)
          rec = t.event == :return ? [t.event, t.method_id] : [t.event, t.lineno, t.method_id]
          rec << [t.raised_exception.class, t.raised_exception.message] if t.event == :raise
          ev4 << rec
        end
      end
      t5.enable
      begin
        unwind
      rescue IndexError
      end
      t5.disable
      ev4.each { |e| p e }

      # -- raised_exception is only readable during :raise --
      err = nil
      t6 = TracePoint.new(:call) do |t|
        next unless mine?(t)
        begin
          t.raised_exception
        rescue RuntimeError => e
          err = [e.class, e.message]
        end
      end
      t6.enable
      hum(2)
      t6.disable
      p err

      # -- several tracepoints fire in enable order; trace enables at birth --
      order = []
      ta = TracePoint.new(:call) { |t| order << [:a, t.method_id] if mine?(t) }
      tb = TracePoint.new(:call) { |t| order << [:b, t.method_id] if mine?(t) }
      ta.enable
      tb.enable
      hum(5)
      ta.disable
      tb.disable
      p order
      tt = TracePoint.trace(:call) { }
      p [tt.class, tt.enabled?]
      tt.disable
      p tt.enabled?

      # -- accessors still fire :call/:return --
      # A method whose whole body is one ivar access is normally devirtualized: the
      # dispatch table reaches the field with no callee and no frame, so it produces
      # no :call and no :return. THIS file names `TracePoint`, which is exactly what
      # turns that off (`Hir::uses_call_tracing`), so the events below are the proof
      # the gate holds. Appended last on purpose -- every line number above is part
      # of the expectation.
      class Tune
        attr_accessor :beat

        def initialize
          @beat = 1
        end
      end

      ev5 = []
      t7 = TracePoint.new(:call, :return) do |t|
        ev5 << [t.event, t.method_id, t.defined_class.to_s] if mine?(t)
      end
      song = Tune.new
      t7.enable
      song.beat
      song.beat = 4
      t7.disable
      ev5.each { |e| p e }
      p song.beat
    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "must be called with a block"]
      [ArgumentError, "unknown event: bogus"]
      false
      #<TracePoint:disabled>
      [RuntimeError, "access from outside"]
      42
      false
      false
      true
      true
      false
      [:line, 60, nil, nil, ""]
      [:call, 6, :hum, :hum, "Object"]
      [:line, 7, :hum, :hum, "Object"]
      [:line, 8, :hum, :hum, "Object"]
      [:return, 9, :hum, :hum, "Object"]
      [:line, 61, nil, nil, ""]
      [:call, 19, :tempo, :tempo, "#<Class:Melody>"]
      [:line, 20, :tempo, :tempo, "#<Class:Melody>"]
      [:return, 21, :tempo, :tempo, "#<Class:Melody>"]
      [:line, 62, nil, nil, ""]
      "#<TracePoint:call 'hum' tracepoint.rb:6>"
      #<TracePoint:disabled>
      [:line, 80, nil, ""]
      [:class, 80, nil, ""]
      [:line, 81, nil, ""]
      [:end, 82, nil, ""]
      [:line, 83, nil, ""]
      [11, 21]
      [90, nil]
      [90, nil]
      [90, nil]
      [91, nil]
      [:call, 11, :unwind]
      [:raise, 12, :unwind, [IndexError, "deep"]]
      [:return, :unwind]
      [RuntimeError, "not supported by this event"]
      [[:b, :hum], [:a, :hum]]
      [TracePoint, true]
      false
      4
    OUT
  end

  it "TracePoint's own methods fire a call and return pair, and disable reports one last event" do
    result = zr(<<~'RUBY')
      # CRuby implements TracePoint's own surface in Ruby (<internal:trace_point>),
      # so calling one of those methods while a trace is live fires an ordinary
      # :call/:return pair -- `tp.disable` reports one last :disable on its way out.
      # Line numbers below are trace_point.rb's, ruby 4.0.6.
      events = []
      tp = TracePoint.new(:call) { |t| events << t.method_id }

      def traced_a = 1
      def traced_b = traced_a

      tp.enable
      traced_b
      tp.disable
      p events

      # The pair's two halves land where the gate is open: the `enable` that STARTS
      # a trace fires neither half, the `disable` that ends one fires only :call.
      seen = []
      outer = TracePoint.new(:call, :return) { |t| seen << [t.event, t.method_id, t.path, t.lineno] }
      inner = TracePoint.new(:line) { }
      outer.enable
      inner.enable
      inner.enabled?
      inner.enable
      inner.inspect
      TracePoint.stat
      inner.disable
      outer.disable
      seen.each { |e| p e }

      # defined_class and self, over both receiver shapes.
      who = []
      w = TracePoint.new(:call) { |t| who << [t.method_id, t.defined_class.to_s, t.self.class.to_s] }
      w.enable
      w.enabled?
      TracePoint.stat
      w.disable
      p who

      # `to_s` is Object's cfunc in CRuby, not the Ruby `inspect` -- it traces
      # nothing and prints the address shape.
      t2 = TracePoint.new(:line) { }
      p t2.inspect
      p(t2.to_s.sub(/0x\h+/, "0xADDR"))
    RUBY

    _(result).must_answer <<~'OUT'
      [:traced_b, :traced_a, :disable]
      [:return, :enable, "<internal:trace_point>", 264]
      [:call, :enable, "<internal:trace_point>", 261]
      [:return, :enable, "<internal:trace_point>", 264]
      [:call, :enabled?, "<internal:trace_point>", 306]
      [:return, :enabled?, "<internal:trace_point>", 308]
      [:call, :enable, "<internal:trace_point>", 261]
      [:return, :enable, "<internal:trace_point>", 264]
      [:call, :inspect, "<internal:trace_point>", 106]
      [:return, :inspect, "<internal:trace_point>", 108]
      [:call, :stat, "<internal:trace_point>", 119]
      [:return, :stat, "<internal:trace_point>", 121]
      [:call, :disable, "<internal:trace_point>", 297]
      [:return, :disable, "<internal:trace_point>", 300]
      [:call, :disable, "<internal:trace_point>", 297]
      [[:enabled?, "TracePoint", "TracePoint"], [:stat, "#<Class:TracePoint>", "Class"], [:disable, "TracePoint", "TracePoint"]]
      "#<TracePoint:disabled>"
      "#<TracePoint:0xADDR>"
    OUT
  end

  it "a :line event answers the object the line ran under and a binding on that scope" do
    result = zr(<<~'RUBY')
      # `TracePoint#self` and `#binding` answer for a `:line` event, as CRuby's do:
      # `self` is the object the line ran under and `binding` is that scope.
      #
      # This was a gap. zr's `Frame` carries a file, a line and a label and nothing
      # else -- no receiver, no cell storage -- which is what makes tracing cost one
      # relaxed atomic load when no tracepoint is enabled. The receiver slot is
      # filled only while a tracepoint is armed, and the binding reuses the capture
      # `Kernel#binding` already has, so the cost stays pay-per-use.
      #
      # The other four readers (`#return_value`, `#parameters`, `#eval_script`,
      # `#instruction_sequence`) still refuse on a `:line` event -- so does CRuby.

      seen = []
      tp = TracePoint.new(:line) do |t|
        seen << t.self.class
        seen << t.binding.class
        t.disable
      end

      tp.enable
      x = 1
      tp.disable

      puts seen.inspect
    RUBY

    _(result).must_answer "[Object, Binding]\n"
  end
  it "a rescue clause fires :rescue where it caught, and a bare TracePoint asks for everything" do
    result = zr(<<~'RUBY')
      # `:rescue` fires where the exception is caught, not where it was raised:
      # in the frame that holds the matching clause, at that clause's line, with
      # the exception still in `raised_exception`. A clause that does not match
      # fires nothing, so the line names the one that did.
      #
      # `TracePoint.new` with no events asks for all of them, which is the form
      # anyone writes first.
      seen = []
      tp = TracePoint.new(:raise, :rescue) { |t| seen << [t.event, t.raised_exception.class.to_s, t.lineno] }

      def inner = raise(ArgumentError, "x")

      def outer
        inner
      rescue ArgumentError
        :caught
      end

      tp.enable do
        outer
        begin
          [1].each { raise TypeError }
        rescue TypeError
          nil
        end
        begin
          raise KeyError
        rescue ArgumentError
          nil
        rescue KeyError
          nil
        end
      end

      seen.each { |row| p row }
      p TracePoint.new { |t| }.class
    RUBY

    _(result).must_answer <<~'OUT'
      [:raise, "ArgumentError", 11]
      [:rescue, "ArgumentError", 16]
      [:raise, "TypeError", 22]
      [:rescue, "TypeError", 24]
      [:raise, "KeyError", 27]
      [:rescue, "KeyError", 31]
      TracePoint
    OUT
  end

  it "fires thread_begin and thread_end around a threads body, from nowhere" do
    result = zr(<<~'RUBY')
      # thread_start_func_2 fires these from the VM and not from a frame,
      # so the row names no file, no line and no method; `self` is the
      # thread the events are for, which is the thread that runs the
      # handler. A point enabled with no target_thread watches every
      # thread, and one enabled without that watches only its own -- so
      # the events of a thread it started would reach it otherwise.
      seen = Queue.new
      tp = TracePoint.new(:thread_begin, :thread_end) do |t|
        seen << [t.event, t.self.class.to_s, t.self.equal?(Thread.current), t.path, t.lineno,
                 t.method_id, t.defined_class, t.binding, t.parameters]
      end
      tp.enable(target_thread: nil)
      Thread.new { 1 }.join
      tp.disable
      p seen.pop until seen.empty?
    RUBY

    _(result).must_answer <<~'OUT'
      [:thread_begin, "Thread", true, nil, 0, nil, nil, nil, nil]
      [:thread_end, "Thread", true, nil, 0, nil, nil, nil, nil]
    OUT
  end

  it "fires fiber_switch where control arrives, naming the call that sent it" do
    result = zr(<<~'RUBY')
      # cont.c fires this in the fiber control reached, so the row stands
      # where that fiber stands: a fresh one has run no line and names
      # nothing. `self` is the thread, which is what th->self is there,
      # and the name and the class come from the frame the switch is in,
      # as fill_id_and_klass takes them.
      rows = []
      fs = TracePoint.new(:fiber_switch) do |t|
        rows << [t.self.class.to_s, t.lineno, t.method_id, t.callee_id, t.defined_class.inspect,
                 (t.binding ? "Binding" : nil), t.parameters]
      end
      fs.enable do
        f = Fiber.new { Fiber.yield 1; 2 }
        f.resume
        f.resume
        root = Fiber.current
        g = Fiber.new { root.transfer }
        g.transfer
      end
      rows.each { |row| p row }
    RUBY

    _(result).must_answer <<~'OUT'
      ["Thread", 0, nil, nil, "nil", nil, nil]
      ["Thread", 13, :resume, :resume, "Fiber", "Binding", nil]
      ["Thread", 12, :yield, :yield, "#<Class:Fiber>", "Binding", nil]
      ["Thread", 14, :resume, :resume, "Fiber", "Binding", nil]
      ["Thread", 0, nil, nil, "nil", nil, nil]
      ["Thread", 17, :transfer, :transfer, "Fiber", "Binding", nil]
    OUT
  end

  it "counts no fiber switch where a thread hands the turn on" do
    result = zr(<<~'RUBY')
      # A thread here runs on a fiber of its own, and the scheduler hands
      # the turn on with the switch a fiber uses. CRuby's threads are the
      # operating system's and fire nothing as they take turns, and
      # neither does this: the fiber that heads a thread is that thread,
      # not a fiber of the program's.
      count = 0
      tp = TracePoint.new(:fiber_switch) { count += 1 }
      tp.enable(target_thread: nil)
      3.times.map { Thread.new { 10.times { Thread.pass } } }.each(&:join)
      tp.disable
      p count
    RUBY

    _(result).must_answer "0\n"
  end

  it "fires script_compiled for each string a program evaluates" do
    result = zr(<<~'RUBY')
      # `:script_compiled` fires once a string of Ruby has compiled and before
      # it runs. `eval_script` is the string; `instruction_sequence` carries
      # what the code answers to -- the name, the label and the first line
      # `rb_iseqw_new` would give it.
      #
      # The event stands where the program called the eval form, because
      # CRuby's form is a C frame with no place of its own and
      # rb_tracearg_path walks out to the nearest Ruby one. The name, the
      # owner and `self` come from the form itself, so `1.instance_eval`
      # answers 1 and BasicObject, and `module_eval` answers the name it was
      # called by rather than the one `class_eval` was defined under.
      seen = []
      tp = TracePoint.new(:script_compiled) do |t|
        i = t.instruction_sequence
        seen << [t.lineno, t.method_id, t.defined_class.to_s, t.self.inspect,
                 t.eval_script, i.path, i.label, i.first_lineno]
      end

      tp.enable do
        eval("1 + 1")
        1.instance_eval("2")
        String.class_eval("3")
        String.module_eval("4")
        eval("6", nil, "given.rb", 40)
      end

      seen.each { |row| p row }
    RUBY

    _(result).must_answer <<~'OUT'
      [20, :eval, "Kernel", "main", "1 + 1", "(eval at core/tracepoint/tracepoint_test.rb:20)", "<compiled>", 1]
      [21, :instance_eval, "BasicObject", "1", "2", "(eval at core/tracepoint/tracepoint_test.rb:21)", "<compiled>", 1]
      [22, :class_eval, "Module", "String", "3", "(eval at core/tracepoint/tracepoint_test.rb:22)", "<compiled>", 1]
      [23, :module_eval, "Module", "String", "4", "(eval at core/tracepoint/tracepoint_test.rb:23)", "<compiled>", 1]
      [24, :eval, "Kernel", "main", "6", "given.rb", "<compiled>", 40]
    OUT
  end

  it "fires script_compiled where a required file is about to run" do
    result = zr(<<~'RUBY', files: beside("script_compiled/loaded.rb"))
      # A file a require reached fires the same event: `eval_script` is nil,
      # because no string was compiled, and the sequence answers to the file
      # and carries `<top (required)>`. ruby fires it where the file compiles;
      # this runtime compiled it before the program began, so it fires at the
      # one moment the program can see, which is the file's first run.
      seen = []
      tp = TracePoint.new(:script_compiled) do |t|
        i = t.instruction_sequence
        seen << [t.lineno, t.method_id, t.defined_class.to_s, t.self.inspect,
                 t.eval_script, File.basename(i.path), i.label, i.first_lineno]
      end

      def load_it
        require_relative "script_compiled/loaded"
      end

      tp.enable { load_it }
      p LOADED_HERE
      seen.each { |row| p row }
    RUBY

    _(result).must_answer <<~'OUT'
      :loaded
      [14, :require_relative, "Kernel", "main", nil, "loaded.rb", "<top (required)>", 0]
    OUT
  end
end
