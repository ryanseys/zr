# frozen_string_literal: true

require_relative "lib/zr/dev"

# The table of zr-dev's commands, and the dispatch over it. Each command
# loads its file only when it runs. The requires are literal, so that zr
# finds every file when it compiles the tools.
module Zr
  module Dev
    COMMANDS = {
      "gen" => ["Write a generated file again, or check it", -> { require_relative "gen"; Gen }],
      "spec" => ["Check, tidy, verify, split or grow the spec files", -> { require_relative "spec"; Specs }],
      "oracle" => ["Check every spec literal against ruby 4.0.7", -> { require_relative "oracle"; Oracle }],
      "rubyspec" => ["Run ruby/spec in ruby and in a zr binary, and list the gaps",
                     -> { require_relative "rubyspec"; RubySpec }],
      "probe" => ["Run Ruby files under ruby and as zr binaries, and show the differences",
                  -> { require_relative "probe"; Probe }],
      "record" => ["Ask ruby what a whole program answers, and write it beside the program",
                   -> { require_relative "record"; Record }],
      "affected" => ["Run the specs that a change can reach", -> { require_relative "affected"; Affected }],
      "progress" => ["Where the test tier running now stands", -> { require_relative "progress"; Progress }],
      "bench" => ["How long the programs that zr builds take to run", -> { require_relative "bench"; Bench }],
      "compile" => ["How long zr takes to compile, and where", -> { require_relative "compile"; Compile }],
      "edit" => ["How long `zr run` takes right after an edit to zr", -> { require_relative "edit"; Edit }],
      "codesize" => ["Count the instructions the backend writes for the runtime", -> { require_relative "codesize"; Codesize }],
      "stage" => ["Check that zr compiles itself to the same bytes (1 or 2)", -> { require_relative "stage"; Stage }],
      "repro" => ["Build one program from two copies of the tree, and compare the bytes", -> { require_relative "repro"; Repro }],
      "cache" => ["Show, prune or clear the runtime cache", -> { require_relative "cache"; Cache }],
      "gem" => ["Build the platform gem, with the compiled compiler in it", -> { require_relative "gem"; PlatformGem }],
      "serve" => ["Keep a warm compiler that zr run and zr build of this checkout use", -> { require_relative "serve"; Serve }]
    }.freeze

    def self.start(argv)
      hand_to_ruby!(argv) if Zr.compiled? && !tools.current?
      word = argv.first
      return help if word.nil? || %w[help -h --help].include?(word)

      entry = COMMANDS[word]
      unless entry
        warn "zr-dev: no command #{word}; `zr-dev help` lists them"
        return 2
      end
      entry.last.call.new(word).start(argv.drop(1))
    end

    def self.help
      puts "usage: zr-dev <command> [options]", ""
      width = COMMANDS.keys.map(&:size).max
      COMMANDS.each { |word, (summary, _)| puts format("  %-#{width}s  %s", word, summary) }
      puts "", "`zr-dev <command> --help` gives the options of a command."
      0
    end
  end
end
