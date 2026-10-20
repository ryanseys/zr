# frozen_string_literal: true

require_relative "lib/zr/dev"

# The table of zr-dev's commands, and the dispatch over it. Each command
# loads its file only when it runs. The requires are literal, so that zr
# finds every file when it compiles the tools.
module Zr
  module Dev
    COMMANDS = {
      "gen" => ["Write a generated file again, or check it", -> { require_relative "gen"; Commands::Gen }],
      "rubyspec" => ["Run ruby/spec in ruby and in zr binaries, and compare each example",
                     -> { require_relative "rubyspec"; Commands::RubySpec }],
      "cruby-test" => ["Run CRuby's test-all in ruby and in zr binaries, and compare each test",
                       -> { require_relative "cruby_test"; Commands::CRubyTest }],
      "gem-tests" => ["Run the bundled gems' own tests in ruby and in zr, and compare each test",
                      -> { require_relative "gem_tests"; Commands::GemTests }],
      "fuzz" => ["Write Ruby programs, run them in ruby and in zr, and keep each difference",
                 -> { require_relative "fuzz"; Commands::Fuzz }],
      "expect" => ["Write the expected output of program tests and benchmarks from the pinned ruby",
                   -> { require_relative "expect"; Commands::Expect }],
      "test" => ["Run zr's tests: all, or the test files, lines and programs given", -> { require_relative "test"; Commands::Test }],
      "bump" => ["Set the version: version.rb, Gemfile.lock, the README's links and CHANGELOG.md", -> { require_relative "bump"; Commands::Bump }],
      "changelog" => ["Print the CHANGELOG.md section of a version: its release notes",
                      -> { require_relative "changelog"; Commands::Changelog }],
      "bench" => ["How long the programs that zr builds take to run", -> { require_relative "bench"; Commands::Bench }],
      "compile" => ["How long zr takes to compile, and where", -> { require_relative "compile"; Commands::Compile }],
      "host" => ["Run a program on CRuby over zr's kernel, with no build", -> { require_relative "host"; Commands::Host }],
      "golden" => ["Save or check the kernel's lowering on each target", -> { require_relative "golden"; Commands::Golden }],
      "stage" => ["Check that zr compiles itself to the same bytes (1 or 2)", -> { require_relative "stage"; Commands::Stage }],
      "gems" => ["Check which gems zr compiles, and group what stops the others", -> { require_relative "gems"; Commands::Gems }],
      "vendor" => ["Write vendor/ (ruby's library and gems, as upstream ships them) again, or check it",
                   -> { require_relative "vendor"; Commands::Vendor }],
      "ext" => ["Tools for C extensions: what one imports from ruby", -> { require_relative "ext"; Commands::Ext }]
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
