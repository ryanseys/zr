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

        # Marks a tool that reads the running ruby's own tables, or runs
        # ruby as the reference, so it needs the pinned ruby (`Dev.pinned!`).
        def host_ruby! = @host_ruby = true
        def host_ruby? = @host_ruby || false
      end

      attr_reader :name

      def initialize(name)
        @name = name
        defaults
      end

      # Gives each variable that an option sets its starting value (nil,
      # or false for a flag), so that every command has all its variables
      # from the start. A subclass with options defines it, and calls
      # `super` when its parent has options too.
      def defaults = nil

      # How this command's name reads in a message.
      def label = name.empty? ? "zr-dev" : "zr-dev #{name}"

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
      def fail!(message) = Dev.fail!("#{label}: #{message}")
    end

    # A command whose first word names one of its own commands, as
    # `zr-dev gen unicode` and `zr-dev gems try` do. `commands` maps
    # each word to its summary and a lambda that loads its class.
    #
    # A group can also have a `fallback`: a lambda that loads the command
    # for every other first word, and for none. Then the group has no help
    # of its own: `--help` shows the help of the fallback.
    class Group < Command
      class << self
        def commands(table = nil)
          table ? @commands = table : @commands
        end

        def fallback(loader = nil)
          loader ? @fallback = loader : @fallback
        end
      end

      def start(argv)
        word = argv.first
        fallback = self.class.fallback
        return help if fallback.nil? && (word.nil? || %w[help -h --help].include?(word))

        entry = self.class.commands[word]
        return entry.last.call.new([name, word].reject(&:empty?).join(" ")).start(argv.drop(1)) if entry
        return fallback.call.new(name).start(argv) if fallback

        unknown(word)
      end

      def help
        puts "usage: #{label} <command> [options]", *self.class.summary, ""
        width = self.class.commands.keys.map(&:size).max
        self.class.commands.each { |word, (summary, _)| puts format("  %-#{width}s  %s", word, summary) }
        0
      end

      def unknown(word)
        warn "#{label}: no command #{word}; `#{label} help` lists them"
        2
      end
    end
  end
end
