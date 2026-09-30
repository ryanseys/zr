# frozen_string_literal: true

require_relative "flags"

module Zr
  # The `ZR_*` environment variables that steer a build, read once.
  # `Config.current` reads the environment on first use; every later call
  # in the same process gets that same frozen instance, so one build sees
  # one consistent set of settings even if something changes `ENV`
  # afterward. Code reads a `ZR_*` variable only through this class.
  # (`ZR_BINARY` and `ZR_COMPILED` are the exception: `Bootstrap::Handoff`
  # reads them before it loads anything else.)
  class Config
    # `ZR_LINKER`: `auto` (zr's own linker, and cc for what it cannot
    # link), `ruby` (zr's linker only) or `cc`. Empty or unset is `auto`.
    LINKERS = %w[auto ruby cc].freeze

    # `ZR_CODE_CACHE`: on, off, or on with a check of each hit.
    CODE_CACHES = %w[1 0 verify].freeze

    # A `ZR_*` value that zr cannot use. The message names the variable,
    # its value, and a value that works. The CLI prints it and exits 2.
    class Invalid < ArgumentError; end

    attr_reader :linker, :wasm_width, :cache, :cache_max_gb, :link, :test_binaries_gb, :host_ruby

    def initialize
      @linker = choice("ZR_LINKER", LINKERS, "auto")
      @jobs_given = !ENV["ZR_JOBS"].to_s.empty?
      @jobs = number("ZR_JOBS", nil, "4", min: 1) if @jobs_given
      # Not exposed as a plain reader: `eval` is a Kernel method, and
      # `eval_walk?` is the only thing anything reads this for.
      @eval_mode = ENV["ZR_EVAL"]
      @timing = Zr.flag?("ZR_TIMING")
      @verify = Zr.flag?("ZR_VERIFY")
      @wasm_names = Zr.flag?("ZR_WASM_NAMES")
      # `ZR_WASM_WIDTH`: the group size of a large wasm function's dispatch
      # (`Backend::Wasm::Codegen::Body::LADDER` explains the default).
      @wasm_width = number("ZR_WASM_WIDTH", 256, "256", min: 1)
      @tune = Zr.flag?("ZR_TUNE", default: true)
      @cache = ENV["ZR_CACHE"]
      # `ZR_CACHE_MAX_GB`: the most GB an installed zr keeps in its cache
      # (default 5; 0 turns the limit off).
      @cache_max_gb = number("ZR_CACHE_MAX_GB", 5.0, "10", kind: :Float, min: 0)
      # `ZR_TEST_BINARIES_GB`: the most GB of binaries that the spec tier
      # keeps in the store (default 8).
      @test_binaries_gb = number("ZR_TEST_BINARIES_GB", 8.0, "8", kind: :Float, min: 0)
      # `ZR_HOST_RUBY`: the ruby that the compiled compiler starts to
      # resolve gems (lib/zr/gem_set.rb).
      @host_ruby = ENV["ZR_HOST_RUBY"].to_s.empty? ? "ruby" : ENV["ZR_HOST_RUBY"]
      # `ZR_LINK_ARGS`: words for the system linker, as `--link` gives
      # them, split as a shell splits them.
      @link = words(ENV.fetch("ZR_LINK_ARGS", "")).freeze
      # `ZR_LEDGER`: nil when unset, so the default can be a checkout's.
      @ledger = ENV["ZR_LEDGER"].to_s.empty? ? nil : ENV["ZR_LEDGER"] != "0"
      @run_cache = Zr.flag?("ZR_RUN_CACHE", default: true)
      @code_cache = choice("ZR_CODE_CACHE", CODE_CACHES, "1")
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
        raise Invalid, "ZR_LINK_ARGS has a quote with no end: #{line.inspect}. Close the quote, or put a \ before it." if garbage

        field << (word || sq || dq&.gsub(/\\([$`"\\\n])/, '\\1') || esc.gsub(/\\(.)/, '\\1'))
        next unless sep

        words << field
        field = +""
      end
      words
    end
    private :words

    # The value of `name` when it is one of `values`, or `default` when
    # it is unset or empty.
    def choice(name, values, default)
      value = ENV[name].to_s
      return default if value.empty?
      return value if values.include?(value)

      raise Invalid, "#{name} is #{value.inspect}. Set it to #{values[0..-2].join(", ")} or #{values[-1]}, for example #{name}=#{default}."
    end

    # The number in `name` (an Integer, or with `kind: :Float` any
    # number) that is at least `min`, or `default` when it is unset or
    # empty. `example` is a good value for the message.
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
    attr_reader :ledger

    # `ZR_RUN_CACHE=0` makes `zr run` build each run (`RunCache`).
    def run_cache? = @run_cache

    # `ZR_CODE_CACHE`: "1", "0" or "verify" (`Native::CodeCache`).
    attr_reader :code_cache

    # `ZR_ISEQ_CACHE=0` makes ruby compile zr's own files at each start
    # (`IseqCache`).
    def iseq_cache? = @iseq_cache

    # `ZR_SERVER`: nil (use the server if one listens at its default
    # socket), "0" (never), or the path of a socket (lib/zr/server.rb).
    attr_reader :server

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

    # `ZR_DEBUG=1` shows the backtrace of an error that stops zr
    # (`CLI.guard`). It is read on its own, not with the rest: it must
    # work when another ZR_* value is bad.
    def self.debug? = Zr.flag?("ZR_DEBUG")

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
