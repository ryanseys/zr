# frozen_string_literal: true

require "rbconfig"
require_relative "version"
require_relative "paths"
require_relative "config"
require_relative "target"
require_relative "gc_tuning"
require_relative "cli/errors"
require_relative "cli/help"
require_relative "cli/options"
require_relative "cli/refusals"
require_relative "cli/runner"
require_relative "cli/command"
require_relative "cli/commands/cache"
require_relative "cli/commands/compile"
require_relative "cli/commands/diff"
require_relative "cli/commands/doctor"
require_relative "cli/commands/gems"
require_relative "cli/commands/help"
require_relative "cli/commands/inspect"
require_relative "cli/commands/version"

module Zr
  # The `zr` command: `exe/zr` in a checkout, and the gem's executable
  # once it is installed. The repository's own tools (tests, bootstrap,
  # benchmarks, generated tables) are rake tasks.
  #
  # Each word that `zr` takes first is a command (lib/zr/cli/commands/):
  # `CLI.start` finds its class in `COMMANDS` and runs it. The process's
  # entry points (`start`, `guard`, `kept!`, `served!`, `tune!`,
  # `run_binary` and `exit_as`) are the calls that `exe/zr` and the build
  # server (lib/zr/server.rb) make.
  module CLI
    # @rbs @commands: Hash[String, Command]

    # Exit status 3: zr does not support the program or the target. The
    # test harness counts this separately from zr's defects.
    REFUSED = 3

    # The command that each first word names. The order is the order of
    # `zr help`.
    COMMANDS = {
      "run" => Commands::Compile,
      "build" => Commands::Compile,
      "doctor" => Commands::Doctor,
      "gems" => Commands::Gems,
      "inspect" => Commands::Inspect,
      "diff" => Commands::Diff,
      "version" => Commands::Version,
      "help" => Commands::Help,
      "cache" => Commands::Cache
    }.freeze #: Hash[String, singleton(Command)]

    # The commands that compile.
    COMPILE = COMMANDS.select { |_, command| command == Commands::Compile }.keys.freeze #: Array[String]

    module_function

    # Sets the collector limits and YJIT for a compile (`GcTuning`). With
    # `later`, only the first step of heavy work tunes, so a warm build
    # pays for neither.
    #: (?String? script, ?later: bool) -> void
    def tune!(script = nil, later: false)
      later ? GcTuning.later(script, ARGV) : GcTuning.now(script, ARGV)
    end

    # Runs the command that the first word of `argv` names, with the words
    # after it.
    #: (Array[String] argv) -> void
    def start(argv)
      args = argv.dup
      verb = args.shift
      verb = "version" if %w[--version -v].include?(verb)
      verb = "help" if Help::FLAGS.include?(verb)
      return unknown_verb(verb) unless COMMANDS.key?(verb)

      # COMMANDS has the word, so it is a String.
      known = verb #: String
      handler = command(known)
      if !handler.reads_help? && Help.asked?(args)
        Help.show(known)
        exit
      end
      Errors.usage_error("unexpected argument '#{args.first}'", known) if handler.plain? && !args.empty?
      handler.run(args)
    end

    # The command for `verb`. The process keeps it, so a compile command
    # keeps what `kept!` and `served!` give it.
    #: (String verb) -> Command
    def command(verb)
      commands = @commands ||= {} #: Hash[String, Command]
      commands[verb] ||= COMMANDS.fetch(verb).new(verb)
    end

    # Says what is wrong with a first word that names no command, and exits.
    #: (String? verb) -> bot
    def unknown_verb(verb)
      if verb.nil?
        warn Help::USAGE
        exit 2
      end
      return Errors.usage_error("unknown option '#{verb}'") if verb.start_with?("-")

      near = COMMANDS.keys.find { |name| Help.near?(verb, name) }
      Errors.usage_error("unknown command '#{verb}'#{"; did you mean '#{near}'?" if near}")
    end

    #: [T] () { () -> T } -> T
    def guard(&) = Errors.guard(&)

    #: (Array[String] argv) -> void
    def kept!(argv)
      run = command("run") #: Commands::Compile
      run.kept!(argv)
    end

    #: () { (String binary, Array[String] rest, bool temp) -> Object? } -> void
    def served!(&)
      run = command("run") #: Commands::Compile
      run.served!(&)
    end

    #: (String binary, Array[String] rest) -> Process::Status
    def run_binary(binary, rest) = Runner.run_binary(binary, rest)

    #: (Process::Status status) -> bot
    def exit_as(status) = Runner.exit_as(status)
  end
end
