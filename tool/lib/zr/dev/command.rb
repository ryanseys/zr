# frozen_string_literal: true

require "optparse"

module Zr
  module Dev
    # One tool. A subclass sets its summary and its usage, adds its
    # options, and does its work in `run`:
    #
    #   class Oracle < Command
    #     summary "Check every spec literal against ruby"
    #     usage "[path] [-n pattern]"
    #
    #     def options(o) = o.on("-n PATTERN") { |v| @filter = v }
    #     def run(argv) = ...
    #   end
    #
    # `run` returns true or nil for success and false for a failure; the
    # exit status follows it. A tool that finds a fault it cannot go past
    # calls `fail!`.
    class Command
      class << self
        # The one line that `zr-dev help` shows.
        def summary(text = nil)
          text ? @summary = text : @summary
        end

        # The words after the command's name in its usage line. A subclass
        # has its parent's usage unless it gives its own.
        def usage(text = nil)
          return @usage = text if text

          @usage || (superclass.respond_to?(:usage) ? superclass.usage : "")
        end

        # Marks a tool that must run under CRuby, not in a binary that zr
        # built: it reads the running ruby's own tables, or it runs ruby as
        # the reference. `bin/zr-dev` gives such a tool to ruby.
        def host_ruby! = @host_ruby = true
        def host_ruby? = @host_ruby || false
      end

      attr_reader :name

      def initialize(name)
        @name = name
      end

      # Parses `argv` and runs the tool. Returns the exit status.
      def start(argv)
        parser = OptionParser.new do |o|
          o.banner = "usage: zr-dev #{name} #{self.class.usage}".rstrip
          o.separator(self.class.summary.to_s)
          options(o)
        end
        rest = parser.parse(argv)
        run(rest) == false ? 1 : 0
      rescue OptionParser::ParseError => e
        warn "zr-dev #{name}: #{e.message}", parser
        2
      end

      def options(_parser) = nil

      def run(_argv) = raise(NotImplementedError, "#{self.class} has no run")

      # Stops the tool with a message and status 1.
      def fail!(message)
        warn "zr-dev #{name}: #{message}"
        exit 1
      end
    end

    # A command whose first word names one of its own commands, as
    # `zr-dev gen unicode` and `zr-dev spec check` do. `commands` maps
    # each word to its summary and a lambda that loads its class.
    class Group < Command
      class << self
        def commands(table = nil)
          table ? @commands = table : @commands
        end
      end

      def start(argv)
        word = argv.first
        return help if word.nil? || %w[help -h --help].include?(word)

        entry = self.class.commands[word] or return unknown(word)
        entry.last.call.new("#{name} #{word}").start(argv.drop(1))
      end

      def help
        puts "usage: zr-dev #{name} <command> [options]", self.class.summary, ""
        width = self.class.commands.keys.map(&:size).max
        self.class.commands.each { |word, (summary, _)| puts format("  %-#{width}s  %s", word, summary) }
        0
      end

      def unknown(word)
        warn "zr-dev #{name}: no command #{word}; `zr-dev #{name} help` lists them"
        2
      end
    end
  end
end
