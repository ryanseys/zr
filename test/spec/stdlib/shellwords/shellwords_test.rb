# frozen_string_literal: true

require "spec_helper"

describe "Shellwords programs" do
  it "the vendored gem compiles, and split, escape and join all answer" do
    result = zr(<<~'RUBY')
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

  it "an alias written inside class << self resolves against the singleton table" do
    result = zr(<<~'RUBY', files: {"shellwords.rb" => fixture("stdlib/shellwords/shellwords.rb")})
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
