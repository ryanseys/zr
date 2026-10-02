# frozen_string_literal: true

require_relative "lib/zr/dev"

# The table of zr-dev's commands, and the dispatch over it. Each command
# loads its file only when it runs. The requires are literal, so that zr
# finds every file when it compiles the tools.
module Zr
  module Dev
    COMMANDS = {
      "gen" => ["Write a generated file again, or check it", -> { require_relative "gen"; Gen }],
      "rubyspec" => ["Run ruby/spec in ruby and in a zr binary, and list the gaps",
                     -> { require_relative "rubyspec"; RubySpec }],
      "probe" => ["Run Ruby files under ruby and as zr binaries, and show the differences",
                  -> { require_relative "probe"; Probe }],
      "expect" => ["Write the expected output of program tests from ruby 4.0.7", -> { require_relative "expect"; Expect }],
      "record" => ["Ask ruby what a benchmark answers, and write it beside the benchmark",
                   -> { require_relative "record"; Record }],
      "affected" => ["Run the tests that a change can reach", -> { require_relative "affected"; Affected }],
      "progress" => ["Where the test tier running now stands", -> { require_relative "progress"; Progress }],
      "bench" => ["How long the programs that zr builds take to run", -> { require_relative "bench"; Bench }],
      "compile" => ["How long zr takes to compile, and where", -> { require_relative "compile"; Compile }],
      "edit" => ["How long `zr run` takes right after an edit to zr", -> { require_relative "edit"; Edit }],
      "host" => ["Run a program on CRuby over zr's kernel, with no build", -> { require_relative "hosted"; Hosted }],
      "golden" =>["Save or check the kernel's lowering on each target", -> { require_relative "golden"; Golden }],
      "reach" => ["How much of the runtime each program reaches (the A4 spike)", -> { require_relative "reach"; Reach }],
      "codesize" => ["Count the instructions the backend writes for the runtime", -> { require_relative "codesize"; Codesize }],
      "stage" => ["Check that zr compiles itself to the same bytes (1 or 2)", -> { require_relative "stage"; Stage }],
      "repro" => ["Build one program from two copies of the tree, and compare the bytes", -> { require_relative "repro"; Repro }],
      "gems" => ["Check which gems zr compiles, and group what stops the others", -> { require_relative "gems"; GemCompat }],
      "vendor" => ["Write vendor/ (ruby's library and gems, as upstream ships them) again, or check it",
                   -> { require_relative "vendor"; VendorCommand }],
      "serve" => ["Keep a warm compiler that zr run and zr build of this checkout use", -> { require_relative "serve"; Serve }]
    }.freeze

    # `zr-dev` itself: the group of all the commands, with no name of its
    # own.
    class Main < Group
      commands COMMANDS

      def help
        super
        puts "", "`zr-dev <command> --help` gives the options of a command."
        0
      end
    end

    def self.start(argv) = Main.new("").start(argv)
  end
end
