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
require_relative "cli/ruby_options"
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
  # once it is installed. The repository's own tools are `zr-dev`
  # commands (tool/zr-dev.rb) and bin/minitest; the gem has neither.
  #
  # Each word that `zr` takes first is a command (lib/zr/cli/commands/):
  # `CLI.start` finds its class in `COMMANDS` and runs it. Any other first
  # word that is a switch, `-`, a file or a name that ends in `.rb` runs
  # zr as a ruby (`ruby_mode?`): `zr app.rb args`, `zr -e 'p 1'`. A
  # command's name always wins, so a script named like one runs as
  # `zr ./build` or `zr -- build`. The process's
  # entry points (`start`, `guard`, `kept!`, `served!`, `tune!`,
  # `run_binary` and `exit_as`) are the calls that `exe/zr` and the build
  # server (lib/zr/server.rb) make.
  module CLI
    # Exit status 3: zr does not support the program or the target. The
    # test harness counts this separately from zr's defects.
    REFUSED = 3

    # A command of `zr`: its first word, the class that runs it, and its
    # row in `zr help`.
    # @rbs skip -- typed in sig/zr/cli/verb.rbs
    Verb = Data.define(:name, :command, :usage, :about)

    # The commands, in the order of `zr help`.
    VERBS = [
      Verb.new("run", Commands::Compile, "run <file.rb> [args...]", "compile a program, run it, then delete the build"),
      Verb.new("build", Commands::Compile, "build <file.rb> -o <out>",
               "compile a program to a binary, a WASI module or an object (`compile` is another name)"),
      Verb.new("gems", Commands::Gems, "gems [<file.rb>]", "list the gems of a build and their sources"),
      Verb.new("inspect", Commands::Inspect, "inspect <binary>", "print the gems that a binary was built with"),
      Verb.new("diff", Commands::Diff, "diff <file.rb> [args...]", "run a program in ruby and as a zr binary; compare"),
      Verb.new("doctor", Commands::Doctor, "doctor", "check this host: ruby, targets, wasmtime, OpenSSL, gems, cache"),
      Verb.new("cache", Commands::Cache, "cache [path|size|clean]", "show or clean the build cache"),
      Verb.new("version", Commands::Version, "version", "print the version"),
      Verb.new("help", Commands::Help, "help [<command>]", "print help for zr or for one command")
    ].freeze #: Array[Verb]

    # The command that each first word names.
    COMMANDS = VERBS.to_h { |verb| [verb.name, verb.command] }.freeze #: Hash[String, singleton(Command)]

    # Other names of commands.
    ALIASES = { "compile" => "build" }.freeze #: Hash[String, String]

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

    # Takes the flags of settings (`Config::SETTINGS`, such as `--jobs 2`)
    # off the front of `argv` and off the front of a command's words, and
    # makes them this process's settings. Returns the other words. `argv`
    # stays as it is, so zr started again for the collector (`tune!`)
    # reads the same flags.
    #: (Array[String] argv) -> Array[String]
    def settings!(argv)
      given, rest = Config.flags(argv)
      verb = rest.first
      if verb && (COMMANDS.key?(verb) || ALIASES.key?(verb))
        more, words = Config.flags(rest.drop(1))
        given = given.merge(more)
        rest = [verb, *words]
      end
      Config.given!(given)
      rest
    end

    # Runs the command that the first word of `argv` names, with the words
    # after it.
    #: (Array[String] argv) -> void
    def start(argv)
      return ruby(argv) if ruby_mode?(argv)

      args = argv.dup
      verb = args.shift
      # -h prints the short list of commands; --help and `zr help` the long one.
      return Help.show(args.first, long: false) if verb == "-h" && !Help.asked?(args)

      verb = ALIASES.fetch(verb, verb) if verb
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

    # Whether `argv` runs zr as a ruby: its first word names no command,
    # so ruby reads it as a switch, `-`, empty (standard input) or the
    # script. A script that is not there stops as ruby stops for it. Only
    # a word that is one letter away from a command, and is not a file,
    # a path or a name that ends in `.rb`, is a mistyped command. With no
    # word, zr reads the program from standard input, unless it is a
    # terminal.
    #: (Array[String] argv, ?tty: bool) -> bool
    def ruby_mode?(argv, tty: $stdin.tty?)
      word = argv.first
      return !tty if word.nil?
      return false if COMMANDS.key?(word) || ALIASES.key?(word) || Help::FLAGS.include?(word) || word == "--version"

      word.empty? || word.start_with?("-") || word.end_with?(".rb") || word.include?("/") || File.file?(word) ||
        COMMANDS.keys.none? { |name| Help.near?(word, name) }
    end

    # Runs zr as a ruby (`Commands::Compile#ruby`). A command line that
    # ruby rejects ends as ruby ends it: one line and status 1.
    #: (Array[String] argv) -> void
    def ruby(argv)
      run = command("run") #: Commands::Compile
      run.ruby(argv)
    rescue RubyOptions::Invalid => e
      warn "zr: #{e.message} (RuntimeError)"
      exit 1
    end

    # Whether the command line compiles, so `exe/zr` tunes the collector
    # for it (`tune!`). That can start zr again with the same words, so
    # ruby mode tunes only when the words give the same program again:
    # not for standard input, which is read, and not after -C.
    #: (Array[String] argv) -> bool
    def compiles?(argv)
      return COMPILE.include?(ALIASES.fetch(argv.first.to_s, argv.first.to_s)) unless ruby_mode?(argv)

      options = RubyOptions.parse(argv)
      options.runs?($stdin.tty?) && !options.dumps? && options.chdirs.empty? && !(options.inline.empty? && [nil, "-"].include?(options.script))
    rescue RubyOptions::Invalid
      false
    end

    # The command for `verb`. The process keeps it, so a compile command
    # keeps what `kept!` and `served!` give it.
    #: (String verb) -> Command
    def command(verb)
      commands = Session.current.memo(:commands) { {} } #: Hash[String, Command]
      commands[verb] ||= COMMANDS.fetch(verb).new(verb)
    end

    # Says what is wrong with a first word that names no command, and exits.
    #: (String? verb) -> bot
    def unknown_verb(verb)
      if verb.nil?
        warn Help.short
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
