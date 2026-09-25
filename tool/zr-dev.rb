#!/usr/bin/env ruby
# frozen_string_literal: true

# zr-dev: the tools that work on a zr checkout. `zr-dev help` lists them,
# and `zr-dev <command> --help` gives the options of one.
#
#   ruby tool/zr-dev.rb gen unicode        under ruby, from any directory
#   bin/zr-dev gen unicode                 the same tools, compiled by zr
#                                          (`rake build:tools`)
#
# Each command loads its file only when it runs. The requires are
# literal, so that zr finds every file when it compiles this one.
require_relative "lib/zr/dev"

module Zr
  module Dev
    COMMANDS = {
      "gen" => ["Write a generated file again, or check it", -> { require_relative "gen"; Gen }]
    }.freeze

    def self.start(argv)
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

exit Zr::Dev.start(ARGV)
