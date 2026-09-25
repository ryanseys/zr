# frozen_string_literal: true

require "spec_helper"

describe "IO::console programs" do
  it "console escape answers its receiver" do
    result = zr(<<~'RUBY')
      # The cursor/erase/scroll family writes an escape and answers the RECEIVER,
      # so `io.goto(0, 0).erase_line(0)` chains. They answered nil.
      #
      # Two rules ride along, both from `console_move`/`console_scroll`: a distance
      # of ZERO writes nothing at all, and a NEGATIVE one flips the direction
      # rather than emitting a negative number -- `cursor_up(-3)` moves three DOWN.
      # The old `format!` wrote `ESC[0A` and `ESC[-3A`, the second of which is not
      # an escape sequence.

      require "stringio"
      require "io/console"

      out = StringIO.new
      p out.respond_to?(:goto)

      r, w = IO.pipe

      def bytes(w, r)
        w.flush
        r.read_nonblock(400)
      rescue IO::WaitReadable, EOFError
        ""
      end

      p w.goto(3, 5).equal?(w)
      p bytes(w, r)

      p w.goto_column(7).equal?(w)
      p bytes(w, r)

      p w.cursor_up(2).equal?(w)
      p w.cursor_down(2).equal?(w)
      p w.cursor_left(2).equal?(w)
      p w.cursor_right(2).equal?(w)
      p bytes(w, r)

      # Zero writes nothing.
      p w.cursor_up(0).equal?(w)
      p w.scroll_forward(0).equal?(w)
      p bytes(w, r)

      # A negative distance flips the letter and drops the sign.
      p w.cursor_up(-3).equal?(w)
      p w.cursor_left(-4).equal?(w)
      p w.scroll_forward(-2).equal?(w)
      p w.scroll_backward(-2).equal?(w)
      p bytes(w, r)

      p w.erase_line(0).equal?(w)
      p w.erase_screen(2).equal?(w)
      p w.clear_screen.equal?(w)
      p bytes(w, r)

      p w.cursor = [3, 5]
      p bytes(w, r)

      r.close
      w.close
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      "\e[4;6H"
      true
      "\e[8G"
      true
      true
      true
      true
      "\e[2A\e[2B\e[2D\e[2C"
      true
      true
      ""
      true
      true
      true
      true
      "\e[3B\e[4C\e[2T\e[2S"
      true
      true
      true
      "\e[0K\e[2J\e[2J\e[1;1H"
      [3, 5]
      "\e[4;6H"
    OUT
  end

  it "require gated io row appears at the require" do
    result = zr(<<~'RUBY')
      puts STDOUT.respond_to?(:getch)
      puts STDOUT.respond_to?(:winsize)
      puts STDOUT.respond_to?(:nonblock?)
      puts IO.respond_to?(:console)
      require "io/console"
      puts STDOUT.respond_to?(:getch)
      puts IO.respond_to?(:console)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
      true
      true
    OUT
  end

  it "satisfied require activates at its own line" do
    result = zr(<<~'RUBY')
      # A `require` records itself where it is WRITTEN, not for the whole program
      # at once. Every effect of loading a feature -- `$LOADED_FEATURES` naming it,
      # a require-gated builtin row becoming answerable -- starts at this line.
      #
      # zr satisfies `io/console` and `set` natively and splices `prime` from a
      # vendored gem. Even so, a program that requires one on its last line must
      # not answer for it on its first. Like CRuby's `rb_provide_feature`, the
      # record happens at the require's own position, ahead of the file it names.

      # Require-gated rows: `respond_to?(:getch)` is how a library decides whether
      # the console extension is there at all.
      p STDOUT.respond_to?(:winsize)
      p IO.instance_methods(false).include?(:getch)
      require "io/console"
      p STDOUT.respond_to?(:winsize)
      p IO.instance_methods(false).include?(:getch)

      # A spliced gem is not loaded before its require either.
      p $LOADED_FEATURES.any? { |f| f.end_with?("prime.rb") }
      require "prime"
      p $LOADED_FEATURES.any? { |f| f.end_with?("prime.rb") }

      # ...and a second require of one records nothing twice.
      require "prime"
      p $LOADED_FEATURES.count { |f| f.end_with?("prime.rb") }

      # What ruby has loaded before line 1 stays loaded from line 1.
      p $LOADED_FEATURES.any? { |f| f.end_with?("set.rb") }
      p require("set")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
      true
      false
      true
      1
      true
      false
    OUT
  end
end
