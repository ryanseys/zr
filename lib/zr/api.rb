# frozen_string_literal: true

require_relative "error"
require_relative "config"
require_relative "paths"
require_relative "session"
require_relative "target"
require_relative "version"

module Zr
  # What `Zr.build` gives: the path that it wrote, the target's triple,
  # the kind of output (:binary, :obj or :wasm), the warnings of the build
  # (each line that starts "zr: warning:"), and the names of the gems that
  # the program uses.
  # @rbs skip -- typed in sig/zr/api.rbs
  Result = Data.define(:path, :target, :emit, :warnings, :gems)

  # One build in a process at a time: a build keeps its state in the
  # process's Session (lib/zr/session.rb), as a zr process does.
  BUILD_LOCK = Mutex.new

  # The CLI's --emit word of each kind of output.
  EMITS = { binary: nil, obj: "obj", wasm: "wasm" }.freeze #: Hash[Symbol, String?]

  # The settings that apply to a command line only: the run cache, the
  # restart with larger collector limits, and the backtrace of an error.
  CLI_ONLY = %w[ZR_RUN_CACHE ZR_TUNE ZR_DEBUG].freeze

  # Builds the program `file` (or `source`, named `file`, default "-")
  # into `out`, as `zr build` does, and returns a Result. `target` is a
  # triple (default: this host's, else aarch64-apple-darwin). `settings`
  # are the settings of `zr help` by the name of their flag
  # (`jobs: 2`, `linker: "cc"`, `cache_dir: "/tmp/c"`); zr reads no `ZR_*`
  # variable of ENV for the build. Each line that zr prints goes to
  # `diagnostics`: an IO, an object that takes `call(line)`, or nil.
  #
  # Raises an error that includes Zr::Error for a program, a target or a
  # setting that the caller can fix: Refused (a form zr does not
  # support, with `file`, `line` and `form`), InvalidProgram,
  # TargetRefused, Config::Invalid, GemSet::Unresolved, BuildError. Any
  # other error is a defect in zr. docs/reference/ruby-api.md has the rest.
  # @rbs file: String?
  # @rbs source: String?
  # @rbs out: String
  # @rbs target: String?
  # @rbs emit: Symbol
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs diagnostics: untyped
  # @rbs return: Result
  def self.build(file = nil, source: nil, out:, target: nil, emit: :binary, settings: {}, diagnostics: $stderr)
    raise ArgumentError, "give a file, or source:" if file.nil? && source.nil?

    kind = EMITS.fetch(emit) { raise ArgumentError, "emit: is :binary, :obj or :wasm, not #{emit.inspect}" }
    config = Config.new(API.given(settings), {})
    BUILD_LOCK.synchronize do
      API.with_config(config) do
        API.with_diagnostics(diagnostics) do |lines|
          API.build(file || "-", source || File.read(file.to_s), File.expand_path(out), target, kind, emit, lines)
        end
      end
    end
  end

  # The parts of `Zr.build`.
  module API
    module_function

    # The settings by their variable's name, as `Config` reads the flags.
    #: (Hash[Symbol, untyped] settings) -> Hash[String, String]
    def given(settings)
      settings.to_h do |name, value|
        setting = Config::FLAGS.fetch("--#{name.to_s.tr("_", "-")}") { raise ArgumentError, "no setting #{name}" }
        raise ArgumentError, "#{name} applies to the zr command only" if CLI_ONLY.include?(setting.env)

        text = case value
               when true then "1"
               when false then "0"
               when Array then value.join(setting.env == "ZR_LINK_ARGS" ? " " : ",")
               else value.to_s
               end
        [setting.env, text]
      end
    end

    # Runs the block with `config` as the settings of the process, and
    # puts the process's own back after. The runtimes that a build holds
    # stay when the settings that steer a build are the same.
    #: [T] (Config config) { () -> T } -> T
    def with_config(config)
      session = Session.current
      # The settings that the process read already, if any: ENV is not read.
      held = session.peek(:config) #: Config?
      keep = held&.fingerprint == config.fingerprint
      session.reset!(keep_runtimes: keep)
      session.set(:config, config)
      yield
    ensure
      Session.current.reset!(keep_runtimes: keep || false)
    end

    # Runs the block with `$stderr` sent to `diagnostics`, and yields the
    # lines that the build printed. A forked worker writes to the
    # process's own stderr.
    #: [T] (untyped diagnostics) { (Array[String]) -> T } -> T
    def with_diagnostics(diagnostics)
      lines = [] #: Array[String]
      was = $stderr
      # A Sink answers each method of IO that zr calls on $stderr.
      $stderr = Sink.new(diagnostics, lines) # steep:ignore
      yield lines
    ensure
      $stderr = was
    end

    # The build itself, as `zr build` makes it (CLI::Commands::Compile).
    # rubocop:disable Metrics/ParameterLists -- the parts of one call
    #: (String file, String source, String out, String? triple, String? kind, Symbol emit, Array[String] lines) -> Result
    def build(file, source, out, triple, kind, emit, lines)
      require_relative "cli"
      require_relative "runtime"
      require_relative "native/build"
      require_relative "build_options"
      if (why = CLI::Refusals.host_refusal)
        raise TargetRefused, why
      end

      target = Target.default
      if triple
        target = Target.fetch(triple) or raise ArgumentError, "no target #{triple}; the targets are #{Target.all.join(", ")}"
      end
      kind ||= "wasm" if target.outputs == [:wasm]
      if (why = target.refusal(kind))
        raise TargetRefused, "#{target.triple}: #{why}"
      end

      gems = CLI::Options.gem_set(source)
      switches = CLI::RubyOptions.new.tap { |options| options.shebang!(source) }.switches
      options = BuildOptions.new(target: target, gem_set: gems, gate: true, switches: switches)
      command = CLI.command("build") #: CLI::Commands::Compile
      program = command.lower!(file, options, source: source, assemble: kind.nil?)
      Paths.tmpdir("zr-build-") do |work|
        Paths.publish(out) do |draft|
          failed = case kind
                   when "obj" then program.write_object(draft)
                   when "wasm" then program.write_wasm(draft)
                   else program.write_binary(draft, work: work, link: Config.current.link)
                   end
          raise BuildError, failed if failed
        end
      end
      Result.new(path: out, target: target.triple, emit: emit, warnings: lines.grep(/\Azr: warning: /), gems: program.gems)
    end
    # rubocop:enable Metrics/ParameterLists

    # The `$stderr` of a build from Ruby: each line goes to the caller's
    # diagnostics, and to the build's own list.
    class Sink
      # @rbs @to: untyped
      # @rbs @lines: Array[String]
      # @rbs @part: String

      #: (untyped to, Array[String] lines) -> void
      def initialize(to, lines)
        @to = to
        @lines = lines
        @part = +""
      end

      #: (*untyped parts) -> Integer
      def write(*parts)
        text = parts.join
        @part << text
        while (line = @part.slice!(/\A[^\n]*\n/))
          @lines << line.chomp
          @to.respond_to?(:call) ? @to.call(line.chomp) : @to&.write(line)
        end
        text.bytesize
      end

      #: (*untyped parts) -> nil
      def print(*parts)
        write(*parts)
        nil
      end

      #: (*untyped lines) -> nil
      def puts(*lines)
        write("\n") if lines.empty?
        lines.each do |line|
          text = line.to_s
          write(text.end_with?("\n") ? text : "#{text}\n")
        end
        nil
      end

      #: () -> self
      def flush = self

      #: () -> bool
      def tty? = false

      #: () -> bool
      def isatty = false # rubocop:disable Naming/PredicateMethod -- IO's own name

      #: () -> bool
      def sync = true # rubocop:disable Naming/PredicateMethod -- IO's own name
    end
  end
end
