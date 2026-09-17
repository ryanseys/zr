# frozen_string_literal: true

require "spec_helper"

describe "Shellwords programs" do
  it "shellwords" do
    result = ze0(<<~'RUBY')
      # Shellwords -- the pure-Ruby stdlib gem the lock resolves, compiled
      # from its real upstream source. Its module methods are defined with
      # `module_function`, then aliased to shorter names inside `class << self`
      # (`alias split shellsplit`) -- class-method aliases resolved against the
      # singleton table. rubygems parses build flags with it.
      require "shellwords"

      puts Shellwords::VERSION

      # split / shellsplit: tokenize a command line the way a Bourne shell does.
      p Shellwords.split('here are "two words"')
      p Shellwords.shellsplit("ruby prog.rb | less")

      # escape / shellescape: quote one argument for safe shell interpolation.
      puts Shellwords.escape("a b'c")
      puts Shellwords.escape("plain")

      # join / shelljoin: the inverse -- escape and space-join an argv.
      puts Shellwords.join(["echo", "a b", "c"])

      # The String refinements the gem also ships.
      p "one two three".shellsplit
      puts "a b".shellescape
    RUBY

    _(result).must_answer <<~'OUT'
      0.2.2
      ["here", "are", "two words"]
      ["ruby", "prog.rb", "|", "less"]
      a\ b\'c
      plain
      echo a\ b c
      ["one", "two", "three"]
      a\ b
    OUT
  end

  it "shellwords class method aliases run from the vendored gem" do
    result = ze0(<<~'RUBY', files: {"shellwords.rb" => "# Shellwords -- the pure-Ruby stdlib gem the lock resolves, compiled\n# from its real upstream source. Its module methods are defined with\n# `module_function`, then aliased to shorter names inside `class << self`\n# (`alias split shellsplit`) -- class-method aliases resolved against the\n# singleton table. rubygems parses build flags with it.\nrequire \"shellwords\"\n\nputs Shellwords::VERSION\n\n# split / shellsplit: tokenize a command line the way a Bourne shell does.\np Shellwords.split('here are \"two words\"')\np Shellwords.shellsplit(\"ruby prog.rb | less\")\n\n# escape / shellescape: quote one argument for safe shell interpolation.\nputs Shellwords.escape(\"a b'c\")\nputs Shellwords.escape(\"plain\")\n\n# join / shelljoin: the inverse -- escape and space-join an argv.\nputs Shellwords.join([\"echo\", \"a b\", \"c\"])\n\n# The String refinements the gem also ships.\np \"one two three\".shellsplit\nputs \"a b\".shellescape\n__END__\n0.2.2\n[\"here\", \"are\", \"two words\"]\n[\"ruby\", \"prog.rb\", \"|\", \"less\"]\na\\ b\\'c\nplain\necho a\\ b c\n[\"one\", \"two\", \"three\"]\na\\ b\n"})
      # shellwords defines its module methods (`module_function`) then aliases
      # them inside `class << self` (`alias split shellsplit`) -- a class-method
      # alias that resolves against the singleton table, not instance methods.

      require "shellwords"
      p Shellwords.split('a "b c"')
      puts Shellwords.escape("a b")
      puts Shellwords.join(["a", "b c"])
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b c"]
      a\ b
      a b\ c
    OUT
  end
end
