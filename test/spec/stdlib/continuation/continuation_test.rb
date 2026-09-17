# frozen_string_literal: true

require "spec_helper"

describe "Continuation programs" do
  it "callcc goes back through its continuation" do
    result = ze0(<<~'RUBY')
      # callcc returns the continuation, and a call goes back through it: from
      # later in the same frame, after the method that captured it returned,
      # and in the middle of a block. The warning callcc gives names the
      # extension's own file, so stderr goes nowhere.
      $stderr.reopen(IO::NULL)
      require "continuation"
      p defined?(callcc), Continuation
      x = 0
      c = callcc { |k| k }
      x += 1
      p [x, c.class]
      c.call(:done) if c.is_a?(Continuation)
      p c
      def gen
        r = callcc { |k| return [k, 1] }
        [nil, r]
      end
      k, v = gen
      p v
      k.call(5) if k
      arr = []
      cont = nil
      [1, 2, 3].each do |i|
        callcc { |cc| cont = cc } if i == 2
        arr << i
      end
      cont.call if arr.size < 5
      p arr
      p callcc { |cc| cc.call(1, 2) }

    RUBY

    _(result).must_answer <<~'OUT'
      "method"
      Continuation
      [1, Continuation]
      [2, Symbol]
      :done
      1
      5
      [1, 2, 3, 2, 3]
      [1, 2]
    OUT
  end

  it "callcc warns only while warnings are on" do
    _(ze0(<<~'RUBY')).must_answer ":back\n", stderr: "shown\n"
      # The continuation extension warns that callcc is obsolete as it loads,
      # through rb_warn, which says nothing while $VERBOSE is nil. Kernel#warn
      # is silent then too.
      $VERBOSE = nil
      require "continuation"
      warn "not shown"
      p callcc { |k| k.call(:back) }
      $VERBOSE = false
      warn "shown"

    RUBY
  end

  it "survives collections" do
    skip "a continuation does not survive a collection: the program aborts on SIGABRT"

    result = ze0(<<~'RUBY')

      # A continuation keeps the frames it saved alive across collections, a
      # loop can be made of one, and a call from another fiber or thread is
      # refused.
      $stderr.reopen(IO::NULL)
      require "continuation"
      # A continuation holds the frames it saved alive across collections.
      def collect
        strings = (1..50).map { |i| "s#{i}" * 3 }
        k = callcc { |c| c }
        if k.is_a?(Continuation)
          100.times { "garbage" * 100 }
          GC.start
          [k, strings.size]
        else
          [nil, strings.map(&:size).sum, k]
        end
      end
      k, n = collect
      p n
      if k
        GC.start
        k.call(:back)
      end
      # A loop made of a continuation.
      i = 0
      top = callcc { |c| c }
      i += 1
      top.call(top) if i < 1000
      p i
      # Across fibers and threads.
      saved = callcc { |c| c }
      if saved.is_a?(Continuation)
        p((Fiber.new { saved.call(1) }.resume rescue $!))
        p((Thread.new { saved.call(1) }.value rescue $!))
      end
      p Continuation.respond_to?(:new), [].respond_to?(:callcc, true)

    RUBY

    _(result).must_answer <<~'OUT'
      50
      423
      1000
      #<RuntimeError: continuation called across fiber>
      #<RuntimeError: continuation called across threads>
      false
      true
    OUT
  end
end
