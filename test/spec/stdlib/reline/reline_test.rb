# frozen_string_literal: true

require "spec_helper"

describe "Reline programs" do
  it "file readlines" do
    result = ze0(<<~'RUBY')
      # File.readlines: read a file back as an array of lines, keeping the
      # "\n" terminator (CRuby default). chomp: true strips it; an encoding:
      # keyword is accepted and ignored. Uses a cwd-relative path because
      # Windows MinGW builds can't fopen /tmp paths.
      path = "file_readlines_tmp.txt"
      File.write(path, "alpha\nbeta\ngamma\n")
      p File.readlines(path)
      p File.readlines(path, chomp: true)
      p File.readlines(path, encoding: 'utf-8')

      # A file whose last line has no trailing newline keeps that line bare.
      File.write(path, "x\ny")
      p File.readlines(path)

      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      ["alpha\n", "beta\n", "gamma\n"]
      ["alpha", "beta", "gamma"]
      ["alpha\n", "beta\n", "gamma\n"]
      ["x\n", "y"]
    OUT
  end

  it "file readlines limit" do
    result = ze0(<<~'RUBY')
      require "tmpdir"

      Dir.mktmpdir do |d|
        f = File.join(d, "o.txt")
        File.write(f, "l1\nl2\n")
        p File.readlines(f, 2).first
        p File.readlines(f).first
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "l1"
      "l1\n"
    OUT
  end

  it "the config, the width and grapheme arithmetic, and the module surface all run without a terminal" do
    result = ze0(<<~'RUBY')
      # reline -- the pure-Ruby line editor irb and every other Ruby REPL reads
      # through. Vendored whole; what is exercised here is the part that runs
      # without a terminal: the config, the width/grapheme arithmetic its rendering
      # is built on, and the module-level surface it delegates to its Core.
      require "reline"

      # The SHAPE, not the number. Zeo vendors reline's latest upstream release and
      # the oracle reads the copy ruby 4.0.6 ships, so the two versions differ on
      # purpose -- see `crates/zeo-rt/ext/UPSTREAM.md`. What has to agree is everything below.
      p Reline::VERSION.match?(/\A\d+\.\d+\.\d+\z/)

      # --- the SingleForwardable delegators the module surface is made of ---------
      p Reline.completion_append_character
      Reline.completion_append_character = " "
      p Reline.completion_append_character
      p Reline.basic_word_break_characters
      p Reline.completion_case_fold
      p Reline.core.class
      p Reline.line_editor.class

      # --- Unicode width, which every rendering decision goes through -------------
      p Reline::Unicode.get_mbchar_width("a")
      p Reline::Unicode.get_mbchar_width("あ")
      p Reline::Unicode.calculate_width("hello")
      p Reline::Unicode.calculate_width("héllo")
      p Reline::Unicode.calculate_width("日本語")
      p Reline::Unicode.take_range("hello world", 0, 5)
      p Reline::Unicode.split_by_width("hello world", 5).first

      # --- the key and config objects --------------------------------------------
      k = Reline::Key.new("a", :ed_insert, false)
      p [k.char, k.method_symbol]
      p Reline::Key.new("a", :ed_insert, false) == Reline::Key.new("a", :ed_insert, false)

      config = Reline::Config.new
      p config.class
      p config.autocompletion
      p config.editing_mode_is?(:emacs)
      config.read_lines(["set editing-mode vi\n"])
      p config.editing_mode_is?(:vi_insert)

      # --- history ----------------------------------------------------------------
      h = Reline::History.new(Reline::Config.new)
      h.push("one")
      h.push("two")
      p [h.size, h[0], h[-1]]
      h.delete_at(0)
      p [h.size, h[0]]

      # --- the editor itself, with no terminal attached ---------------------------
      editor = Reline::LineEditor.new(Reline::Config.new)
      p editor.class
      p editor.line
      p editor.byte_pointer
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      " "
      " \t\n`><=;|&{("
      nil
      Reline::Core
      Reline::LineEditor
      1
      2
      5
      5
      6
      "hello"
      ["hello", " worl", "d"]
      ["a", :ed_insert]
      true
      Reline::Config
      false
      true
      true
      [2, "one", "two"]
      [1, "two"]
      Reline::LineEditor
      ""
      0
    OUT
  end
end
