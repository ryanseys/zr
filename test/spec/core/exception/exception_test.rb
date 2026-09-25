# frozen_string_literal: true

require "spec_helper"

describe "Exception programs" do
  it "backtrace locations are the raise rows" do
    result = zr(<<~'RUBY')
      # The rows the raise saw, as Location objects: nil before a raise, and
      # unchanged when set_backtrace replaces the strings.
      def inner = raise("x")
      def outer = inner

      begin
        outer
      rescue => e
        l = e.backtrace_locations
        p l.class, l.size, l.map(&:class).uniq
        f = l.first
        p f.lineno, f.label, f.base_label, f.path, f.to_s, f.inspect
        p f.absolute_path == File.expand_path(__FILE__)
        p l.map(&:to_s) == e.backtrace
      end

      p RuntimeError.new("y").backtrace_locations
      e = RuntimeError.new("z")
      e.set_backtrace(["a.rb:1:in 'm'"])
      p e.backtrace_locations, e.backtrace

      begin
        raise "w"
      rescue => e2
        e2.set_backtrace(["b.rb:2"])
        p e2.backtrace_locations.size, e2.backtrace
      end

    RUBY

    _(result).must_answer <<~'OUT'
      Array
      3
      [Thread::Backtrace::Location]
      3
      "Object#inner"
      "inner"
      "core/exception/exception_test.rb"
      "core/exception/exception_test.rb:3:in 'Object#inner'"
      "\"core/exception/exception_test.rb:3:in 'Object#inner'\""
      true
      true
      nil
      nil
      ["a.rb:1:in 'm'"]
      1
      ["b.rb:2"]
    OUT
  end

  it "errno and signal tables are rubys" do
    result = zr(<<~'RUBY')
      # Every Errno name ruby defines, with its errno; a name this platform
      # lacks is another name for NOERROR.
      p Errno.constants.size
      p Errno::EWOULDBLOCK.equal?(Errno::EAGAIN), Errno::ENOKEY.name, Errno::ENOKEY::Errno
      p Errno::EADV.new.message, Errno::ENOTBLK.new.message

      # A rescue catches by errno.
      p SystemCallError === Errno::ENOENT.new, Errno::ENOENT === SystemCallError.new(nil, 2)
      p Errno::ENOENT === Errno::EPERM.new, Errno::ENOENT === "not an error"
      p SystemCallError.new("m", 2).class, SystemCallError.new("m", 99999).class

      # Signal.list is ruby's, aliases and all.
      p Signal.list.size, Signal.list["IOT"], Signal.list["CLD"], Signal.list.keys.first(3)
      p SignalException.new("WINCH").message, SignalException.new(6).message, SignalException.new("SIGCLD").signo
      p SignalException.new("IOT").message, SignalException.new(0).message
      p((Process.kill(:EXIT, 0) rescue $!.message))

    RUBY

    _(result).must_answer <<~'OUT'
      158
      true
      "Errno::NOERROR"
      0
      "Undefined error: 0"
      "Block device required"
      true
      true
      false
      false
      Errno::ENOENT
      SystemCallError
      34
      6
      20
      ["EXIT", "HUP", "INT"]
      "SIGWINCH"
      "SIGABRT"
      20
      "SIGIOT"
      "SIGEXIT"
      "unsupported signal 'SIGEXIT'"
    OUT
  end

  it "set backtrace takes locations" do
    result = zr(<<~'RUBY')
      # set_backtrace with an Array of Locations sets backtrace_locations as
      # well as the strings, and a raise keeps them; an eval SyntaxError holds
      # the locations of the eval.
      e = RuntimeError.new("x"); l = caller_locations(0); r = e.set_backtrace(l); p r.equal?(l), e.backtrace_locations.equal?(l), e.backtrace_locations.map(&:to_s), e.backtrace, (e.set_backtrace([l[0], "s"]) rescue $!)
      e2 = RuntimeError.new; p e2.set_backtrace(["a"]), e2.backtrace_locations, RuntimeError.new.set_backtrace("x"), RuntimeError.new.set_backtrace(nil)
      begin; raise e; rescue => x; p x.backtrace_locations.map(&:to_s); end
      begin
        eval("1 +")
      rescue SyntaxError => e
        p e.backtrace_locations.map(&:label)
      end

    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      ["core/exception/exception_test.rb:4:in '<main>'"]
      ["core/exception/exception_test.rb:4:in '<main>'"]
      #<TypeError: backtrace must be an Array of String or an Array of Thread::Backtrace::Location>
      ["a"]
      nil
      ["x"]
      nil
      ["core/exception/exception_test.rb:4:in '<main>'"]
      ["Kernel#eval", "<main>"]
    OUT
  end

  it "takes an instance variable on an exception the runtime raised" do
    result = zr(<<~'RUBY')
      # An exception the runtime raised already holds what the runtime put
      # in it -- a NoMethodError keeps its name, its receiver and its
      # arguments -- so a program's own instance variable is one more than
      # the cell was made to hold, and the rows move to the heap.
      e = (nil.no_such_method rescue $!)
      e.instance_variable_set(:@seen, 1)
      p e.instance_variables, e.instance_variable_get(:@seen)

      r = (raise "boom" rescue $!)
      10.times { |i| r.instance_variable_set(:"@a#{i}", i) }
      p r.instance_variables.size, r.instance_variable_get(:@a9), r.message

      k = ({}.fetch(:nope) rescue $!)
      k.instance_variable_set(:@seen, :yes)
      p k.instance_variables, k.key, k.class
    RUBY

    _(result).must_answer <<~'OUT'
      [:@seen]
      1
      10
      9
      "boom"
      [:@seen]
      :nope
      KeyError
    OUT
  end

  it "DEBUG reports each raise on stderr" do
    result = zr(<<~'RUBY')
      $DEBUG = true
      def m = raise(IOError, "io")
      begin; m; rescue IOError; end
      begin; raise RuntimeError, "set", ["elsewhere:9"]; rescue; end
      begin; [].fetch(3); rescue IndexError; end
      begin; throw :zz; rescue UncaughtThrowError; end
      begin; exit 3; rescue SystemExit; end
      catch(:a) { throw :a }
      $DEBUG = false
      begin; raise "quiet"; rescue; end
      puts "done"
    RUBY

    _(result).must_answer "done\n", stderr: "Exception 'IOError' at core/exception/exception_test.rb:2 - io\nException 'RuntimeError' at core/exception/exception_test.rb:4 - set\nException 'IndexError' at core/exception/exception_test.rb:5 - index 3 outside of array bounds: 0...0\nException 'UncaughtThrowError' at core/exception/exception_test.rb:6 - uncaught throw :zz\n"
  end

  it "full_message passes its keywords on and follows rb_error_write" do
    result = zr(<<~'RUBY')
      class E < StandardError
        def detailed_message(highlight: false, **opt) = "#{message} #{opt.inspect} #{highlight}"
      end
      e = E.new("m")
      p e.full_message(foo: 1)
      p e.full_message(highlight: false, order: :top, bar: 2)
      p RuntimeError.new("").full_message(highlight: false)
      p ArgumentError.new("").full_message(highlight: true)
      e = RuntimeError.new("r")
      e.set_backtrace(["a:1", "b:2", "c:3"])
      p e.full_message(highlight: false, order: :bottom)
      class B < StandardError
        def backtrace = ["over:1", "over:2"]
      end
      p B.new("b").full_message(highlight: false)
      class D < StandardError
        def detailed_message(**) = raise("inner")
      end
      raise D, "x"
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/exception/exception_test.rb:19:in '<main>': D\n", status: 1
      "core/exception/exception_test.rb:5:in 'full_message': m {foo: 1} false\n"
      "core/exception/exception_test.rb:6:in 'full_message': m {order: :top, bar: 2} false\n"
      "core/exception/exception_test.rb:7:in 'full_message': unhandled exception\n"
      "core/exception/exception_test.rb:8:in 'full_message': \e[1;4mArgumentError\e[m\n"
      "Traceback (most recent call last):\n\t2: from c:3\n\t1: from b:2\na:1: r (RuntimeError)\n"
      "over:1: b (B)\n\tfrom over:2\n"
    OUT
  end

  it "an uncaught error heads with a backtrace set by hand" do
    result = zr(<<~'RUBY')
      e = RuntimeError.new("boom")
      e.set_backtrace(["a.rb:1:in `x'", "b.rb:2"])
      raise e
    RUBY

    _(result).must_answer "", stderr: "a.rb:1:in `x': boom (RuntimeError)\n\tfrom b.rb:2\n", status: 1
  end

  it "a frozen exception raises as it is, with no backtrace" do
    result = zr(<<~'RUBY')
      e = RuntimeError.new("frozen one").freeze
      raise e
    RUBY

    _(result).must_answer "", stderr: "core/exception/exception_test.rb: frozen one (RuntimeError)\n", status: 1
  end

  it "a frozen exception with a backtrace raises a copy" do
    result = zr(<<~'RUBY')
      e = RuntimeError.new("f").freeze
      begin; raise e; rescue => x; p x.equal?(e), x.backtrace; end
      e2 = RuntimeError.new("g")
      e2.set_backtrace(["q:1"])
      e2.freeze
      begin; raise e2; rescue => x; p x.equal?(e2), x.backtrace, x.frozen?; end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      false
      ["q:1"]
      false
    OUT
  end

  it "a SyntaxError raised by hand keeps its message" do
    result = zr(<<~'RUBY')
      begin
        raise SyntaxError, "m2"
      rescue SyntaxError => e
        p e.message, e.full_message(highlight: false)
      end
      raise SyntaxError, "msg"
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/exception/exception_test.rb:6:in '<main>': msg (SyntaxError)\n", status: 1
      "m2"
      "core/exception/exception_test.rb:2:in '<main>': m2 (SyntaxError)\n"
    OUT
  end

  it "full_message of a detailed_message that is nil and a cause never raised" do
    result = zr(<<~'RUBY')
      e = RuntimeError.new("outer")
      c = ArgumentError.new("inner")
      e2 = begin; raise c; rescue; RuntimeError.new("w"); end
      x = RuntimeError.new("top")
      begin; raise x, cause: ArgumentError.new("never raised"); rescue => e; p e.full_message(highlight: false); p e.cause.backtrace; end
    RUBY

    _(result).must_answer <<~'OUT'
      "core/exception/exception_test.rb:5:in '<main>': top (RuntimeError)\ncore/exception/exception_test.rb:5:in 'full_message': never raised (ArgumentError)\n"
      nil
    OUT
  end

  it "an uncaught error whose detailed_message is nil prints the class" do
    result = zr(<<~'RUBY')
      class E < StandardError
        def detailed_message(**) = nil
      end
      begin; raise E, "x"; rescue => e; p e.full_message(highlight: false); end
      raise E, "y"
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/exception/exception_test.rb:5:in '<main>': E\n", status: 1
      "core/exception/exception_test.rb:4:in '<main>': E\n"
    OUT
  end
end
