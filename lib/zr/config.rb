# frozen_string_literal: true

require "etc"
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

    attr_reader :linker, :jobs, :wasm_width, :cache, :host_ruby

    def initialize
      @linker = ENV["ZR_LINKER"].to_s.empty? ? "auto" : ENV["ZR_LINKER"]
      raise ArgumentError, "ZR_LINKER=#{@linker}: use #{LINKERS.join(", ")}" unless LINKERS.include?(@linker)

      @jobs_given = ENV.key?("ZR_JOBS")
      @jobs = Integer(ENV.fetch("ZR_JOBS") { [Etc.nprocessors, 6].min })
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
      @host_ruby = ENV.fetch("ZR_HOST_RUBY", "ruby")
      freeze
    end

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

    # Whether `ZR_JOBS` sets the worker count. Then it also overrides the
    # memory limit (`Native::Parallel.afforded`).
    def jobs_given? = @jobs_given

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
