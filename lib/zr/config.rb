# frozen_string_literal: true

require "rbconfig"
require_relative "session"

module Zr
  # The `ZR_*` environment variables that steer a build, read once.
  # `Config.current` reads the environment on first use; every later call
  # in the same process gets that same frozen instance, so one build sees
  # one consistent set of settings even if something changes `ENV`
  # afterward. Code reads a `ZR_*` variable only through this class.
  class Config
    # @rbs @jobs_given: bool
    # @rbs @jobs: Integer?
    # @rbs @eval_mode: String?
    # @rbs @timing: bool
    # @rbs @verify: bool
    # @rbs @kernel_checked: bool
    # @rbs @wasm_names: bool
    # @rbs @tune: bool
    # @rbs @run_cache: bool
    # @rbs @trace: bool

    # `ZR_LINKER`: `auto` (zr's own linker, and cc for what it cannot
    # link), `ruby` (zr's linker only) or `cc`. Empty or unset is `auto`.
    LINKERS = %w[auto ruby cc].freeze

    # `ZR_CODE_CACHE`: on, off, or on with a check of each hit.
    CODE_CACHES = %w[1 0 verify].freeze

    # A `ZR_*` value that zr cannot use. The message names the variable,
    # its value, and a value that works. The CLI prints it and exits 2.
    class Invalid < ArgumentError; end

    attr_reader :linker, :host_ruby #: String
    attr_reader :wasm_width #: Integer
    attr_reader :cache #: String?
    attr_reader :cache_max_gb, :test_binaries_gb #: Float
    attr_reader :link #: Array[String]

    #: () -> void
    def initialize
      @linker = choice("ZR_LINKER", LINKERS, "auto")
      @jobs_given = !ENV["ZR_JOBS"].to_s.empty?
      @jobs = number("ZR_JOBS", nil, "4", min: 1) if @jobs_given
      # Not exposed as a plain reader: `eval` is a Kernel method, and
      # `eval_walk?` is the only thing anything reads this for.
      @eval_mode = ENV["ZR_EVAL"]
      @timing = Config.flag?("ZR_TIMING")
      @verify = Config.flag?("ZR_VERIFY")
      @kernel_checked = Config.flag?("ZR_KERNEL_CHECKED")
      @wasm_names = Config.flag?("ZR_WASM_NAMES")
      # `ZR_WASM_WIDTH`: the group size of a large wasm function's dispatch
      # (`Backend::Wasm::Codegen::Body::LADDER` explains the default).
      @wasm_width = number("ZR_WASM_WIDTH", 256, "256", min: 1)
      @tune = Config.flag?("ZR_TUNE", default: true)
      @cache = ENV["ZR_CACHE"]
      # `ZR_CACHE_MAX_GB`: the most GB an installed zr keeps in its cache
      # (default 5; 0 turns the limit off).
      @cache_max_gb = number("ZR_CACHE_MAX_GB", 5.0, "10", kind: :Float, min: 0)
      # `ZR_TEST_BINARIES_GB`: the most GB of binaries that the program tests
      # keeps in the store (default 8).
      @test_binaries_gb = number("ZR_TEST_BINARIES_GB", 8.0, "8", kind: :Float, min: 0)
      # `ZR_HOST_RUBY`: the ruby that zr starts when it needs ruby itself:
      # to resolve gems (lib/zr/gem_set.rb), and for ruby's report of a
      # syntax error (`CLI::Refusals.syntax_report`).
      @host_ruby = ENV["ZR_HOST_RUBY"].to_s.empty? ? running_ruby : ENV["ZR_HOST_RUBY"] #: String
      # `ZR_LINK_ARGS`: words for the system linker, as `--link` gives
      # them, split as a shell splits them.
      @link = words(ENV.fetch("ZR_LINK_ARGS", "")).freeze
      @run_cache = Config.flag?("ZR_RUN_CACHE", default: true)
      @trace = Config.flag?("ZR_TRACE")
      @code_cache = choice("ZR_CODE_CACHE", CODE_CACHES, "1")
      @server = ENV["ZR_SERVER"].to_s.empty? ? nil : ENV["ZR_SERVER"]
      freeze
    end

    # The words of `line` as Shellwords.split gives them. zr does not
    # require shellwords: the compiled compiler goes into a program with
    # eval, and shellwords would give that program String#shellsplit,
    # String#shellescape and Array#shelljoin.
    #: (String line) -> Array[String]
    def words(line)
      words = [] #: Array[String]
      field = +""
      line.scan(/\G\s*(?>([^\0\s\\'"]+)|'([^\0']*)'|"((?:[^\0"\\]|\\[^\0])*)"|(\\[^\0]?)|(\S))(\s|\z)?/m) do |groups|
        # The pattern has groups, so `scan` yields an Array of them.
        word, sq, dq, esc, garbage, sep = groups #: Array[String?]
        raise Invalid, "ZR_LINK_ARGS has a quote with no end: #{line.inspect}. Close the quote, or put a \ before it." if garbage

        # One of the five groups matches; the last is an escape.
        field << (word || sq || dq&.gsub(/\\([$`"\\\n])/, '\\1') || esc.to_s.gsub(/\\(.)/, '\\1'))
        next unless sep

        words << field
        field = +""
      end
      words
    end
    private :words

    # The ruby that runs zr, or `ruby` on PATH in a binary that zr built,
    # whose `RbConfig.ruby` names zr itself.
    #: () -> String
    def running_ruby =RbConfig::CONFIG["ruby_install_name"] == "ruby" ? RbConfig.ruby : "ruby"
    private :running_ruby

    # The value of `name` when it is one of `values`, or `default` when
    # it is unset or empty.
    #: (String name, Array[String] values, String default) -> String
    def choice(name, values, default)
      value = ENV[name].to_s
      return default if value.empty?
      return value if values.include?(value)

      *others, last = values
      raise Invalid, "#{name} is #{value.inspect}. Set it to #{others.join(", ")} or #{last}, for example #{name}=#{default}."
    end

    # The number in `name` (an Integer, or with `kind: :Float` any
    # number) that is at least `min`, or `default` when it is unset or
    # empty. `example` is a good value for the message.
    #: (String name, Integer default, String example, ?kind: :Integer, ?min: Integer?) -> Integer
    #: (String name, nil default, String example, ?kind: :Integer, ?min: Integer?) -> Integer?
    #: (String name, Float default, String example, ?kind: :Float, ?min: Integer?) -> Float
    def number(name, default, example, kind: :Integer, min: nil)
      value = ENV[name].to_s
      return default if value.empty?

      number = Kernel.send(kind, value, exception: false)
      return number if number && (min.nil? || number >= min)

      what = kind == :Integer ? "a whole number" : "a number"
      what += " of #{min} or more" if min
      raise Invalid, "#{name} is #{value.inspect}. Set it to #{what}, for example #{name}=#{example}."
    end
    private :choice, :number

    # `ZR_EVAL=walk` builds a native program with the tree-walking
    # interpreter as its eval support, instead of the compiler.
    #: () -> bool
    def eval_walk? = @eval_mode == "walk"

    # `ZR_TIMING=1` prints one line to stderr for each build phase.
    #: () -> bool
    def timing? = @timing

    # `ZR_VERIFY=1` runs the IR against the interpreter as it lowers.
    #: () -> bool
    def verify? = @verify

    # `ZR_KERNEL_CHECKED=1` lowers the kernel with a check at each
    # operator whose meaning differs from Ruby's (`Machine::Function#check_wrap`).
    # It is part of the runtime digest.
    #: () -> bool
    def kernel_checked? = @kernel_checked

    # `ZR_WASM_NAMES=1` adds the wasm name section, for a stack trace or
    # a profiler that reads function names.
    #: () -> bool
    def wasm_names? = @wasm_names

    # `ZR_TUNE=0` keeps ruby's limits and leaves YJIT off.
    #: () -> bool
    def tune? = @tune

    # `ZR_TRACE=1` builds the program with its trace events armed, as
    # `--trace` does, for a TracePoint that it reaches by a computed name.
    #: () -> bool
    def trace? = @trace

    # `ZR_RUN_CACHE=0` makes `zr run` build each run (`Cache::Run`).
    #: () -> bool
    def run_cache? = @run_cache

    # `ZR_CODE_CACHE`: "1", "0" or "verify" (`Native::CodeCache`).
    attr_reader :code_cache #: String

    # `ZR_SERVER`: nil (use the server if one listens at its default
    # socket), "0" (never), or the path of a socket (lib/zr/server.rb).
    attr_reader :server #: String?

    # Whether `ZR_JOBS` sets the worker count. Then it also overrides the
    # memory limit (`Native::Parallel.afforded`).
    #: () -> bool
    def jobs_given? = @jobs_given

    # `ZR_JOBS`, or the processors up to 6. etc loads at the first call,
    # not with this file: the compiler goes into a program with eval, and
    # etc would give that program IO#pathconf.
    #: () -> Integer
    def jobs
      # `ZR_JOBS` gives a number when it is set.
      given = @jobs #: Integer
      return given if @jobs_given

      require "etc"
      [Etc.nprocessors, 6].min
    end

    # `ZR_DEBUG=1` shows the backtrace of an error that stops zr
    # (`CLI.guard`). It is read on its own, not with the rest: it must
    # work when another ZR_* value is bad.
    #: () -> bool
    def self.debug? = flag?("ZR_DEBUG")

    # Whether the environment variable `name` is on. Unset or empty gives
    # `default`, "0" is off, and any other value is on.
    #: (String name, ?default: bool) -> bool
    def self.flag?(name, default: false)
      value = ENV[name]
      value.nil? || value.empty? ? default : value != "0"
    end

    # The one instance for this process. A later call returns the same
    # instance; `reset!` and `with` are the only way to get a new one.
    #: () -> Config
    def self.current = Session.current.memo(:config) { new }

    # Drops the current instance, so the next `current` reads `ENV` again.
    #: () -> void
    def self.reset!
      Session.current.forget(:config)
    end

    # Sets each of `ENV` (by keyword, e.g. `ZR_TUNE: "0"`) for the block,
    # yields the `Config` that reading it there gives, and puts `ENV`
    # back after. For tests only; a build reads `Config.current` once.
    #: [T] (**String? overrides) { (Config) -> T } -> T
    def self.with(**overrides)
      saved = overrides.to_h { |name, _| [name, ENV[name.to_s]] }
      begin
        overrides.each { |name, value| ENV[name.to_s] = value }
        reset!
        yield current
      ensure
        saved.each { |name, value| ENV[name.to_s] = value }
        reset!
      end
    end
  end
end
