# frozen_string_literal: true

require_relative "errors"

module Zr
  module CLI
    # One command of `zr`. `CLI.start` makes the command that `CLI::COMMANDS`
    # names for the first word of the command line, and gives it the words
    # after that word (`run`). A command reads its own options: the table of
    # `Options.parse` for the commands that compile, a few words by hand for
    # the others.
    class Command
      # The word that names the command. One class can have more than one
      # name: `Commands::Compile` is `run` and `build`.
      attr_reader :name

      def initialize(name)
        @name = name
      end

      # Runs the command with the words after its name.
      def run(argv) = raise(NotImplementedError, "#{self.class}#run")

      # Whether the command takes no file and no option but -h and --help.
      def plain? = false

      # Whether the command reads -h and --help in its own options, so
      # `CLI.start` leaves them to it.
      def reads_help? = false

      private

      # A usage error for this command (`Errors.usage_error`).
      def usage_error(message) = Errors.usage_error(message, name)
    end
  end
end
