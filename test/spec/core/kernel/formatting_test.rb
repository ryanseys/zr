# frozen_string_literal: true

require "spec_helper"

describe "Kernel: formatting and inspection" do
  it "caller locations objects" do
    result = zr(<<~'RUBY')
      # `caller_locations` answers `Thread::Backtrace::Location` objects, not strings:
      # forwardable reads `caller_locations(2, 1).first.path` to build its deprecation
      # message.
      def show
        loc, = caller_locations(1, 1)
        [loc.class.to_s, loc.path.end_with?("formatting_test.rb"), loc.lineno,
         loc.label, loc.base_label]
      end

      def outer = show

      class Holder
        def self.klass_method = show
        def inst = show
      end

      p outer
      p Holder.klass_method
      p Holder.new.inst

      # A `start` past the top answers nil, matching `caller`.
      p caller_locations(99)
      p caller_locations.class

      # `to_s` is exactly the string `caller` would have given for the same frame.
      loc = caller_locations(0, 1).first
      p loc.to_s == "#{loc.path}:#{loc.lineno}:in '#{loc.label}'"
      p loc.inspect == loc.to_s.inspect
      # (`path` is the script as invoked, `absolute_path` the resolved one; zr's
      # frames only ever carry the resolved form, so this holds either way.)
      p loc.absolute_path.end_with?(loc.path)
      p caller_locations(0, 2).size
    RUBY

    _(result).must_answer <<~'OUT'
      ["Thread::Backtrace::Location", true, 10, "Object#outer", "outer"]
      ["Thread::Backtrace::Location", true, 13, "Holder.klass_method", "klass_method"]
      ["Thread::Backtrace::Location", true, 14, "Holder#inst", "inst"]
      nil
      Array
      true
      true
      true
      1
    OUT
  end

  it "class member beats kernel" do
    result = zr(<<~'RUBY')
      class K
        def puts(v) = "class-puts:#{v}"
        def print(v) = "class-print:#{v}"
        def p(v) = "class-p:#{v}"
        def caller(v) = "class-caller:#{v}"
        def raise(v) = "class-raise:#{v}"
        def system(v) = "class-system:#{v}"
        def exit(v) = "class-exit:#{v}"
        def loop(v) = "class-loop:#{v}"
        def throw(v) = "class-throw:#{v}"
        def abort(v) = "class-abort:#{v}"
        def warn(v) = "class-warn:#{v}"

        def run
          say(puts(1))
          say(print(2))
          say(p(3))
          say(caller(4))
          say(raise(5))
          say(system(6))
          say(exit(7))
          say(loop(8))
          say(throw(9))
          say(abort(10))
          say(warn(11))
        end

        def say(s)
          STDOUT.write(s)
          STDOUT.write("\n")
        end
      end

      K.new.run

      class R
        attr_reader :format

        def initialize
          @format = "reader-format"
        end

        def run = format
      end

      STDOUT.write(R.new.run)
      STDOUT.write("\n")

      def puts(v) = "top-puts:#{v}"

      class Three
        def puts(v) = "class-puts:#{v}"
        def own = puts(30)
        def notMine = caller(31)
      end

      def caller(v) = "top-caller:#{v}"

      t = Three.new
      STDOUT.write(t.own)
      STDOUT.write("\n")
      STDOUT.write(t.notMine)
      STDOUT.write("\n")
      STDOUT.write(puts(32))
      STDOUT.write("\n")
    RUBY

    _(result).must_answer <<~'OUT'
      class-puts:1
      class-print:2
      class-p:3
      class-caller:4
      class-raise:5
      class-system:6
      class-exit:7
      class-loop:8
      class-throw:9
      class-abort:10
      class-warn:11
      reader-format
      class-puts:30
      top-caller:31
      top-puts:32
    OUT
  end

  it "cmeth name collision with kernel" do
    result = zr(<<~'RUBY')
      # Issue #407 case 1: a class/module class method whose name
      # collides with a Kernel/Object inferred-type default (e.g.
      # `hash`, `to_s` is exempt because it actually works the right
      # way already; `inspect`, `methods`, ...) used to lose the
      # user-defined return type. `infer_method_name_type`'s arms have
      # shape `if mname == "hash"; return "int"; end` regardless of
      # receiver, so a `def self.hash(plain) -> String` on a class
      # resolved to "int" through the Kernel-side hash hardcode and
      # downstream locals widened to mrb_int -- the C compile then
      # tripped at the next site that fed the supposed-integer to a
      # `const char *` parameter.
      #
      # Fix: at the top of `infer_method_name_type`, return "" when
      # recv is a constant-class-or-module reference whose target
      # defines a class method named mname. This defers to the
      # receiver-aware resolution that `infer_constant_recv_type` runs
      # later (cls_cmethod_return_inherited / `<Mod>_cls_<m>` synth
      # lookup), so user-defined cmeths win over the Kernel-name
      # defaults exactly when the receiver pins them.
      #
      # Coverage:
      #   - module class method named `hash` returning String,
      #   - real-class class method named `methods` returning String,
      #   - real-class class method named `to_s` already had the right
      #     answer through other paths; `inspect` here exercises the
      #     same shape with a fresh name to lock the receiver-aware
      #     gate independently.

      module Auth
        class Password
          def self.hash(plain)
            "pbkdf2$" + plain
          end
        end
      end

      stored = Auth::Password.hash("hunter2")
      puts stored                               # pbkdf2$hunter2
      puts stored.length.to_s                   # 14

      class Registry
        def self.methods(prefix)
          "[" + prefix + ":methods]"
        end

        def self.inspect_kind(kind)
          "<Registry inspect: " + kind + ">"
        end
      end

      names = Registry.methods("public")
      puts names                                # [public:methods]
      puts names.length.to_s                    # 16

      shape = Registry.inspect_kind("module")
      puts shape                                # <Registry inspect: module>
    RUBY

    _(result).must_answer <<~'OUT'
      pbkdf2$hunter2
      14
      [public:methods]
      16
      <Registry inspect: module>
    OUT
  end

  it "format f writes an exact number exactly" do
    result = zr(<<~'RUBY')
      # %f of an Integer or a Rational writes its exact digits, the magnitude
      # rounded half up, as CRuby's sprintf does; %e goes through a Float.
      def t = yield rescue [$!.class, $!.message]

      p t { format("%.20f", 1/3r) }, t { format("%f", 1/3r) }, t { format("%.3f", 2/3r) }
      p t { format("%.0f", 5/2r) }, t { format("%.0f", 7/2r) }, t { format("%.0f", -5/2r) }, t { format("%.1f", -1/20r) }
      p t { format("%10.3f|", 1/3r) }, t { format("%-10.3f|", 1/3r) }, t { format("%+.2f", 1/3r) }, t { format("% .2f", 1/3r) }, t { format("%010.3f", -1/3r) }
      p t { format("%.2e", 1/3r) }, t { format("%f", 10**30) }, t { format("%.3f", 10**30 + 1/3r) }, t { format("%.2f", 0r) }, t { format("%#.0f", 1/3r) }
      p t { format("%.0f", -1/3r) }, t { format("%f", -3) }, t { format("%+08.2f", 7) }, t { format("%-8.1f|", -7) }

    RUBY

    _(result).must_answer <<~'OUT'
      "0.33333333333333333333"
      "0.333333"
      "0.667"
      "3"
      "4"
      "-3"
      "-0.1"
      "     0.333|"
      "0.333     |"
      "+0.33"
      " 0.33"
      "-00000.333"
      "3.33e-01"
      "1000000000000000000000000000000.000000"
      "1000000000000000000000000000000.333"
      "0.00"
      "0"
      "-0"
      "-3.000000"
      "+0007.00"
      "-7.0    |"
    OUT
  end

  it "a user object converts through to_str, to_int and to_ary at a builtin's slot" do
    result = zr(<<~'RUBY')
      # CRuby's implicit conversion protocol at builtin argument boundaries: a user
      # object defining #to_str / #to_int converts where a String / Integer is
      # wanted; one that defines neither raises CRuby's TypeError. The raw object
      # pointer previously went into the typed C slot and stopped the generated-C
      # build.
      class Stringish
        def to_str
          "conv-target.txt"
        end
      end

      class Mode
        def to_str
          "w"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      class Inert
      end

      path = "conv-target.txt"
      begin
        # to_str at File path and mode slots (with and without a block)
        File.open(Stringish.new, Mode.new) { |f| f.write("hello\n") }
        p File.read(Stringish.new)
        p File.readlines(Stringish.new)
        p File.exist?(Stringish.new)
        p File.file?(Stringish.new)

        # to_int at index and count slots
        p [10, 20, 30][Idx.new]
        p [10, 20, 30].take(Idx.new)
        p [10, 20, 30].first(Idx.new)
        p "abc".getbyte(Idx.new)

        # to_str at string-method argument slots
        p "hello world".include?(Mode.new.to_str)
        p "wow".delete(Mode.new)
        p "hello=world".partition(Mode.new.to_str + "orl")

        # A class defining neither conversion is CRuby's TypeError. Where the
        # object's class is STATIC spinel reports it at compile time instead (the
        # call could only ever raise -- see test/rbs-seed/implicit_conv_no_method.rb);
        # reached through a poly slot the class is a run-time question, so the
        # TypeError is a run-time one, worded as CRuby words it.
        inert = [1, Inert.new][1]
        begin
          File.read(inert)
        rescue TypeError => e
          p [e.class, e.message]
        end
        begin
          [10, 20, 30].take(inert)
        rescue TypeError => e
          p [e.class, e.message]
        end
      ensure
        File.delete(path) if File.exist?(path)
      end

    RUBY

    _(result).must_answer <<~'OUT'
      "hello\n"
      ["hello\n"]
      true
      true
      20
      [10]
      [10]
      98
      true
      "o"
      ["hello=", "worl", "d"]
      [TypeError, "no implicit conversion of Inert into String"]
      [TypeError, "no implicit conversion of Inert into Integer"]
    OUT
  end

  it "a boxed user object converts inside a generic runtime call too" do
    result = zr(<<~'RUBY')
      # CRuby's implicit conversion protocol at builtin argument boundaries: a user
      # object defining #to_str / #to_int converts where a String / Integer is
      # wanted; one that defines neither raises CRuby's TypeError. The raw object
      # pointer previously went into the typed C slot and stopped the generated-C
      # build.
      class Stringish
        def to_str
          "conv-target.txt"
        end
      end

      class Mode
        def to_str
          "w"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      class Inert
      end

      # the runtime bridge: a BOXED user object converts inside a generic runtime
      # walk (pack), including a conversion method that arrives through a mixin
      module IntLike
        def to_int
          7
        end
      end

      class Mixed
        include IntLike
      end

      p [Idx.new].pack("C").bytes
      p [Mixed.new, Idx.new].pack("C2").bytes
      begin
        [Inert.new].pack("C")
      rescue TypeError => e
        p [e.class, e.message]
      end
      begin
        [nil].pack("C")
      rescue TypeError => e
        p [e.class, e.message]
      end
      p [2**64 + 65].pack("Q")[0]

    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [7, 1]
      [TypeError, "no implicit conversion of Inert into Integer"]
      [TypeError, "no implicit conversion of nil into Integer"]
      "A"
    OUT
  end

  it "the same protocol runs through a poly slot, where the class is not known" do
    result = zr(<<~'RUBY')
      # CRuby's implicit conversion protocol at builtin argument boundaries: a user
      # object defining #to_str / #to_int converts where a String / Integer is
      # wanted; one that defines neither raises CRuby's TypeError. The raw object
      # pointer previously went into the typed C slot and stopped the generated-C
      # build.
      class Stringish
        def to_str
          "conv-target.txt"
        end
      end

      class Mode
        def to_str
          "w"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      class Inert
      end

      # The same protocol reached through a POLY slot, where the class is not known
      # until run time: the container read hands the builtin a boxed object, which
      # converts through the bridge. These answered a wrong result in SILENCE before
      # -- #to_s's "#<Idx>" rendering for a String slot, 0 for an Integer one -- so
      # the point of each line is that it now matches CRuby rather than raising.
      boxed_str = [1, Stringish.new][1]
      boxed_int = [1, Idx.new][1]
      p "a conv-target.txt b".index(boxed_str)
      p "a conv-target.txt b".include?(boxed_str)
      p [10, 20, 30].first(boxed_int)
      p [10, 20, 30][boxed_int]
      p "abc".getbyte(boxed_int)
      p "wow".delete([1, Mode.new][1])
      p [boxed_int].pack("C").bytes

    RUBY

    _(result).must_answer <<~'OUT'
      2
      true
      [10]
      20
      98
      "o"
      [1]
    OUT
  end

  it "a native binding's declared :string argument converts as well" do
    result = zr(<<~'RUBY')
      # CRuby's implicit conversion protocol at builtin argument boundaries: a user
      # object defining #to_str / #to_int converts where a String / Integer is
      # wanted; one that defines neither raises CRuby's TypeError. The raw object
      # pointer previously went into the typed C slot and stopped the generated-C
      # build.
      class Stringish
        def to_str
          "conv-target.txt"
        end
      end

      class Mode
        def to_str
          "w"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      class Inert
      end

      # native package bindings: a declared :string argument converts too
      require "stringio"
      p StringIO.new(Stringish.new).read
    RUBY

    _(result).must_answer <<~'OUT'
      "conv-target.txt"
    OUT
  end

  it "inspect that answers no string is made one" do
    result = zr(<<~'RUBY')
      # An inspect that answers something other than a String is made one by
      # rb_obj_as_string's rule: its to_s, else the #<Class:0x...> form. So is
      # a to_s that answers no String, where puts or interpolation needs one.
      def hide(s) = s.gsub(/0x\h+/, "0xXX")

      num = Object.new
      def num.inspect = 42
      nothing = Object.new
      def nothing.inspect = nil
      odd = Object.new
      def odd.inspect = Object.new

      p [num]
      p({num => num})
      puts [nothing].inspect
      puts hide([odd].inspect)
      holder = Object.new
      holder.instance_variable_set(:@x, num)
      puts hide(holder.inspect)
      begin
        {a: 1}.fetch(num)
      rescue KeyError => e
        puts e.message
      end

      bad = Object.new
      def bad.to_s = 7
      puts hide("#{bad}")
      puts hide(bad.to_s.to_s)
      $stdout.puts hide([bad].join(",")) rescue puts "join: #{$!.class}"
    RUBY

    _(result).must_answer <<~'OUT'
      [42]
      {42 => 42}
      []
      [#<Object:0xXX>]
      #<Object:0xXX @x=42>
      key not found: 42
      #<Object:0xXX>
      7
      #<Object:0xXX>
    OUT
  end

  it "puts, p, print, format and printf all write and answer what the oracle writes and answers" do
    result = zr(<<~'RUBY')
      puts [1, [2, nil]], "x"
      puts
      r = p 1, "two"
      p r
      r2 = p 5
      p r2
      print "a", 1, "\n"
      puts format("%s scored %05.1f%%", "Bob", 92.5)
      printf("%d-%x\n", 255, 255)
      srand(42)
      v = rand(10)
      puts v.between?(0, 9)
      puts rand.between?(0.0, 1.0)
      puts rand(10).class
      old = srand(7)
      puts old
      caught = catch(:done) do
        [1, 2, 3].each { |i| throw :done, i * 10 if i == 2 }
        :never
      end
      p caught
      p(catch(:t) { 5 })
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2

      x

      1
      "two"
      [1, "two"]
      5
      5
      a1
      Bob scored 092.5%
      255-ff
      true
      true
      Integer
      42
      20
      5
    OUT
  end

  it "caller answers an Array and honours its start and length window" do
    result = zr(<<~'RUBY')
      # Kernel#caller resolves to an Array (the call stack); frame *content* is
      # method-granularity and only populated in --debug builds (release returns
      # []), so this checks the dispatch shape that's release-stable: caller is an
      # Array, and the (start, length) window is honored.
      def helper
        c = caller
        puts c.class            # Array
        puts c.is_a?(Array)     # true
        puts caller(1, 0).length.to_s   # 0  (zero-length window, both runtimes)
      end

      helper
    RUBY

    _(result).must_answer <<~'OUT'
      Array
      true
      0
    OUT
  end

  it "the Kernel conversions do not consult to_int, to_str or to_ary" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Kernel conversions do not consult the to_int/to_str/to_ary protocol
      # methods.
      #
      class ToStr001; def to_str; "c2str"; end; end
      p(String(ToStr001.new) == "c2str")

      class ToA002; def to_a; [1, 2]; end; end
      p(Array(ToA002.new) == [1, 2])
      p(Array(ToA002.new).size)

      class ToAry003; def to_ary; [3, 4]; end; end
      p(Array(ToAry003.new) == [3, 4])

      class ToHash004; def to_hash; { z: 9 }; end; end
      r004 = (Hash(ToHash004.new) rescue $!.class); p r004

      class ToS005; def to_s; "c1"; end; end
      p(String(ToS005.new))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      2
      true
      {z: 9}
      "c1"
    OUT
  end

  it "Kernel as an explicit receiver means what the bare call means, the frame-sensitive rows included" do
    result = zr(<<~'RUBY')
      # Kernel's module functions answer to the module as an explicit receiver, and
      # mean exactly what the bare call means. `Kernel.exit` is how a CLI library
      # makes its exit path injectable (`lambda { |s| Kernel.exit(s) }`), and
      # `Kernel.puts` is how one prints from a class that defines its own `puts`.
      #
      # The frame-sensitive ones are the interesting half: Ruby's module-function
      # copy reads the CALLER's frame, so `Kernel.block_given?` and `Kernel.binding`
      # ask about the enclosing method exactly as the bare spellings do.

      Kernel.puts "puts ok"
      Kernel.print "print ok\n"
      p Kernel.format("%05.2f", 3.5)
      p Kernel.sprintf("%s-%s", "a", "b")
      p Kernel.Integer("42")
      p Kernel.Integer("ff", 16)
      p Kernel.Float("1.5")
      p Kernel.String(9)
      p Kernel.Array([1, 2])
      p Kernel.rand(1)
      p Kernel.srand(7).class
      p Kernel.lambda { |x| x }.lambda?
      p Kernel.proc { |x| x }.lambda?
      p Kernel.catch(:done) { Kernel.throw(:done, 5) }
      p Kernel.binding.class
      p Kernel.caller.class

      begin
        Kernel.raise ArgumentError, "boom"
      rescue ArgumentError => e
        p e.message
      end

      # --- the frame-sensitive ones ask about the ENCLOSING method ----------------
      def probe
        [block_given?, Kernel.block_given?, Kernel.iterator?]
      end
      p probe
      p probe { }

      def named
        [__method__, Kernel.__method__, Kernel.__callee__]
      end
      p named

      def locals
        apple = 1
        banana = 2
        [apple, banana] # keep both live
        Kernel.local_variables.sort
      end
      p locals

      # --- file tests -------------------------------------------------------------
      p Kernel.test(?e, "/")
      p Kernel.test(?d, "/")
      p Kernel.test(?f, "/")
      p Kernel.test(?e, "/no/such/path/at/all")
      begin
        Kernel.test(??, "/")
      rescue ArgumentError => e
        p e.class
      end

      # --- globals ----------------------------------------------------------------
      $zr_probe_global = 1
      p Kernel.global_variables.include?(:$zr_probe_global)
      p global_variables.include?(:$zr_probe_global)
      p Kernel.global_variables.include?(:$no_such_global_anywhere)

      # --- exit, through a lambda, which is how it shows up in real code ----------
      bye = lambda { |status| Kernel.exit(status) }
      p bye.class.to_s
      begin
        bye.call(3)
      rescue SystemExit => e
        p e.status
      end

      p Kernel.select([], [], [], 0)
      Kernel.exit(0)
      Kernel.puts "not reached"
    RUBY

    _(result).must_answer <<~'OUT'
      puts ok
      print ok
      "03.50"
      "a-b"
      42
      255
      1.5
      "9"
      [1, 2]
      0
      Integer
      true
      false
      5
      Binding
      Array
      "boom"
      [false, false, false]
      [true, true, true]
      [:named, :named, :named]
      [:apple, :banana]
      true
      true
      false
      false
      ArgumentError
      true
      true
      false
      "Proc"
      3
      nil
    OUT
  end

  it "block_given?, binding and local_variables answer through send with a literal symbol" do
    result = zr(<<~'RUBY')
      # Four `Kernel` functions cannot be reached through `send`, `method` or
      # `respond_to?` -- but every probe here uses a LITERAL symbol, so all of them
      # are mechanically fixable: a literal `send(:block_given?)` can fold into the
      # caller exactly like the direct spelling (the `is_sent_eval` precedent in
      # `codegen::captures`), `respond_to?`/`method` need only a raising row to
      # exist. Called DIRECTLY they all work already; the folds just don't
      # recognize the reflective spellings.
      #
      # The genuinely hard shape -- `send(name)` with a name COMPUTED at runtime,
      # where no fold can see the caller's block or scope -- is split out into
      # `kernel_scope_intrinsics_dynamic_send.rb`.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      def with_block = block_given?
      def sent_block = send(:block_given?)

      show("direct block_given?") { with_block { } }
      show("send block_given?") { sent_block { } }
      show("send iterator?") { send(:iterator?) }
      show("send binding") { send(:binding).class }
      show("send local_variables") { x = 1; send(:local_variables).include?(:x) }
      show("respond_to? block_given?") { respond_to?(:block_given?, true) }
      show("method(:binding)") { method(:binding).class }

      # Direct calls are unaffected, which is what makes this a `send`-shape gap.
      show("direct binding") { binding.class }
      show("direct local_variables") { y = 2; local_variables.include?(:y) }
    RUBY

    _(result).must_answer <<~'OUT'
      direct block_given?: true
      send block_given?: true
      send iterator?: false
      send binding: Binding
      send local_variables: true
      respond_to? block_given?: true
      method(:binding): Method
      direct binding: Binding
      direct local_variables: true
    OUT
  end

  it "random inspect" do
    result = zr(<<~'RUBY')
      p(Random.new(5).inspect.start_with?("#<Random:0x"))
      r = Random.new(5)
      p(r.inspect.start_with?("#<Random:0x"))
      p(r.to_s.start_with?("#<Random:0x"))
      p r.inspect.length
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      28
    OUT
  end

  it "toplevel def beats kernel" do
    result = zr(<<~'RUBY')
      def raise(v) = "raise:#{v}"
      def system(v) = "system:#{v}"
      def caller(v) = "caller:#{v}"
      def puts(v) = "puts:#{v}"
      def print(v) = "print:#{v}"
      def p(v) = "p:#{v}"
      def require(v) = "require:#{v}"
      def loop(v) = "loop:#{v}"
      def sleep(v) = "sleep:#{v}"
      def exit(v) = "exit:#{v}"
      def gets(v) = "gets:#{v}"
      def sprintf(v) = "sprintf:#{v}"
      def format(v) = "format:#{v}"
      def rand(v) = "rand:#{v}"

      out = []
      out << raise(1)
      out << system(2)
      out << caller(3)
      out << puts(4)
      out << print(5)
      out << p(6)
      out << require(7)
      out << loop(8)
      out << sleep(9)
      out << exit(10)
      out << gets(11)
      out << sprintf(12)
      out << format(13)
      out << rand(14)
      STDOUT.write(out.join("\n") + "\n")

      class K
        def viaTop = caller(21)
      end

      STDOUT.write(K.new.viaTop)
      STDOUT.write("\n")
    RUBY

    _(result).must_answer <<~'OUT'
      raise:1
      system:2
      caller:3
      puts:4
      print:5
      p:6
      require:7
      loop:8
      sleep:9
      exit:10
      gets:11
      sprintf:12
      format:13
      rand:14
      caller:21
    OUT
  end
end
