# frozen_string_literal: true

require "spec_helper"

describe "irb" do
  # The program of this example is three lines with nothing said in it,
  # which is the one place in this tree where that is right: an irb
  # session prints the lines around the call, so anything written in the
  # program is part of the answer and every edit to it would move the
  # expectation.
  #
  # CRuby's prelude writes a Binding#irb that requires irb on the first
  # call and then calls irb's own, which replaces it. The session runs on
  # the scope the call stands in, so it reads that frame's locals, and
  # the listing names the line it stopped on.
  #
  # HOME and XDG_CONFIG_HOME are the program's own directory, which holds
  # no .irbrc, so nothing of the machine's reaches the session.
  it "binding.irb opens a session on the scope that asked" do
    result = zr(<<~'RUBY', stdin: "p x + 1\nexit\n", env: { "HOME" => ".", "XDG_CONFIG_HOME" => "." })
      x = 41
      binding.irb
      puts "after #{x}"
    RUBY

    _(result).must_answer <<~'OUT'

      From: stdlib/irb/irb_test.rb @ line 2 :

          1: x = 41
       => 2: binding.irb
          3: puts "after #{x}"

      Switch to inspect mode.
      p x + 1
      42
      42
      exit
      after 41
    OUT
  end

  it "irb is the version ruby carries, and its own method replaces the preludes" do
    result = zr(<<~'RUBY')
      # The prelude's Binding#irb is a stand-in that loads irb. Requiring irb
      # by hand is that same load, so the method a program calls afterwards is
      # irb's own and not the one it started with.
      before = Binding.instance_method(:irb)
      require "irb"
      p IRB::VERSION
      p Binding.instance_method(:irb) == before
      p Binding.private_method_defined?(:irb)
    RUBY

    _(result).must_answer <<~'OUT'
      "1.18.0"
      false
      false
    OUT
  end
end
