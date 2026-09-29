# frozen_string_literal: true

require_relative "flags"

module Zr
  # The `ZR_*` environment variables that steer a build, read once.
  # `Config.current` reads the environment on first use; every later call
  # in the same process gets that same frozen instance, so one build sees
  # one consistent set of settings even if something changes `ENV`
  # afterward. Code reads a `ZR_*` variable only through this class.
  # (`ZR_BINARY` and `ZR_COMPILED` are the exception: `CompiledCompiler`
  # reads them before it loads anything else.)
  class Config
    # `ZR_LINKER`: `auto` (zr's own linker, and cc for what it cannot
    # link), `ruby` (zr's linker only) or `cc`. Empty or unset is `auto`.
    LINKERS = %w[auto ruby cc].freeze

    attr_reader :linker, :wasm_width, :cache, :cache_max_gb, :link

    def initialize
      @linker = ENV["ZR_LINKER"].to_s.empty? ? "auto" : ENV["ZR_LINKER"]
      raise ArgumentError, "ZR_LINKER=#{@linker}: use #{LINKERS.join(", ")}" unless LINKERS.include?(@linker)

      @jobs_given = ENV.key?("ZR_JOBS")
      @jobs = Integer(ENV["ZR_JOBS"]) if @jobs_given
      # Not exposed as a plain reader: `eval` is a Kernel method, and
      # `eval_walk?` is the only thing anything reads this for.
      @eval_mode = ENV["ZR_EVAL"]
      @timing = Zr.flag?("ZR_TIMING")
      @verify = Zr.flag?("ZR_VERIFY")
      @wasm_names = Zr.flag?("ZR_WASM_NAMES")
      # `ZR_WASM_WIDTH`: the group size of a large wasm function's dispatch
      # (`Backend::Wasm::Codegen::Body::LADDER` explains the default).
      @wasm_width = Integer(ENV.fetch("ZR_WASM_WIDTH", 256))
      @tune = Zr.flag?("ZR_TUNE", default: true)
      @cache = ENV["ZR_CACHE"]
      # `ZR_CACHE_MAX_GB`: the most GB an installed zr keeps in its cache
      # (default 5; 0 turns the limit off).
      @cache_max_gb = Float(ENV.fetch("ZR_CACHE_MAX_GB", 5))
      # `ZR_LINK_ARGS`: words for the system linker, as `--link` gives
      # them, split as a shell splits them.
      @link = words(ENV.fetch("ZR_LINK_ARGS", "")).freeze
      # `ZR_LEDGER`: nil when unset, so the default can be a checkout's.
      @ledger = ENV["ZR_LEDGER"].to_s.empty? ? nil : ENV["ZR_LEDGER"] != "0"
      @run_cache = Zr.flag?("ZR_RUN_CACHE", default: true)
      @code_cache = ENV.fetch("ZR_CODE_CACHE", "1")
      @iseq_cache = Zr.flag?("ZR_ISEQ_CACHE", default: true)
      @server = ENV["ZR_SERVER"].to_s.empty? ? nil : ENV["ZR_SERVER"]
      freeze
    end

    # The words of `line` as Shellwords.split gives them. zr does not
    # require shellwords: the compiled compiler goes into a program with
    # eval, and shellwords would give that program String#shellsplit,
    # String#shellescape and Array#shelljoin.
    def words(line)
      words = []
      field = +""
      line.scan(/\G\s*(?>([^\0\s\\'"]+)|'([^\0']*)'|"((?:[^\0"\\]|\\[^\0])*)"|(\\[^\0]?)|(\S))(\s|\z)?/m) do |word, sq, dq, esc, garbage, sep|
        raise ArgumentError, "ZR_LINK_ARGS: a quote has no end: #{line.inspect}" if garbage

        field << (word || sq || dq&.gsub(/\\([$`"\\\n])/, '\\1') || esc.gsub(/\\(.)/, '\\1'))
        next unless sep

        words << field
        field = +""
      end
      words
    end
    private :words

    # `ZR_EVAL=walk` builds a native program with the tree-walking
    # interpreter as its eval support, instead of the compiler.
    def eval_walk? = @eval_mode == "walk"

    # `ZR_TIMING=1` prints one line to stderr for each build phase.
    def timing? = @timing

    # `ZR_VERIFY=1` runs the IR against the interpreter as it lowers.
    def verify? = @verify

    # `ZR_WASM_NAMES=1` adds the wasm name section, for a stack trace or
    # a profiler that reads function names.
    def wasm_names? = @wasm_names

    # `ZR_TUNE=0` keeps ruby's limits and leaves YJIT off.
    def tune? = @tune

    # `ZR_LEDGER`: true or false when set, else nil (`Zr.ledger?`).
    def ledger = @ledger

    # `ZR_RUN_CACHE=0` makes `zr run` build each run (`RunCache`).
    def run_cache? = @run_cache

    # `ZR_CODE_CACHE`: "1", "0" or "verify" (`Native::CodeCache`).
    def code_cache = @code_cache

    # `ZR_ISEQ_CACHE=0` makes ruby compile zr's own files at each start
    # (`IseqCache`).
    def iseq_cache? = @iseq_cache

    # `ZR_SERVER`: nil (use the server if one listens at its default
    # socket), "0" (never), or the path of a socket (lib/zr/server.rb).
    def server = @server

    # Whether `ZR_JOBS` sets the worker count. Then it also overrides the
    # memory limit (`Native::Parallel.afforded`).
    def jobs_given? = @jobs_given

    # `ZR_JOBS`, or the processors up to 6. etc loads at the first call,
    # not with this file: the compiler goes into a program with eval, and
    # etc would give that program IO#pathconf.
    def jobs
      return @jobs if @jobs_given

      require "etc"
      [Etc.nprocessors, 6].min
    end

    # The one instance for this process. A later call returns the same
    # instance; `reset!` and `with` are the only way to get a new one.
    def self.current = @current ||= new

    # Drops the current instance, so the next `current` reads `ENV` again.
    def self.reset!
      @current = nil
    end

    # Sets each of `ENV` (by keyword, e.g. `ZR_TUNE: "0"`) for the block,
    # yields the `Config` that reading it there gives, and puts `ENV`
    # back after. For tests only; a build reads `Config.current` once.
    def self.with(**overrides)
      saved = overrides.to_h { |name, _| [name, ENV[name.to_s]] }
      overrides.each { |name, value| ENV[name.to_s] = value }
      reset!
      yield current
    ensure
      saved.each { |name, value| ENV[name.to_s] = value }
      reset!
    end
  end
end
