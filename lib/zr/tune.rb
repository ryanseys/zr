# frozen_string_literal: true

require "rbconfig"
require_relative "config"

module Zr
  # The collector limits and YJIT for a compile that allocates much.
  #
  # A cold build lowers the kernel, the core and eval support: tens of
  # millions of objects. Ruby reads the collector's malloc limits only
  # at startup, so a process without them starts itself again with them
  # set (3.17 s against 3.47 s for the runtime's 4,733 functions), and
  # YJIT compiles the compiler's hot methods.
  #
  # A warm `zr run` of a small program allocates little, and there YJIT
  # costs more than it gives: its own compiling added 0.1 s to a 0.39 s
  # run. So `exe/zr` sets the limits at once but turns YJIT on only at
  # the first step of heavy work (`later`, then `heavy!`). The second
  # start costs 0.04 s; a second start at the first heavy step would cost
  # more, because a large program's HIR (bundler: 1.7 s) is built twice.
  # A test tier and the tools tune fully at once (`now`). `ZR_TUNE=0`
  # keeps ruby's limits and leaves YJIT off.
  module Tune
    GC_ENV = { "RUBY_GC_MALLOC_LIMIT" => "64000000", "RUBY_GC_OLDMALLOC_LIMIT" => "128000000" }.freeze

    # Set with the limits when zr starts itself again, so that the new
    # process knows that the limits are zr's, not the user's.
    ADDED = "ZR_GC_ADDED"

    module_function

    # Tunes this process now. With a `script`, a process without the limits
    # starts `script` again with them and with `env`; without one (a rake
    # task), the limits go only to the child processes.
    def now(script = nil, argv = ARGV, env: {})
      limits(script, argv, env)
      yjit
    end

    # Sets the limits now, and turns YJIT on at the first `heavy!`.
    def later(script, argv = ARGV, env: {})
      limits(script, argv, env)
      @pending = Config.current.tune?
    end

    # Called before heavy work: the lowering of the kernel, the core, eval
    # support or a large program.
    def heavy!
      yjit if @pending
    end

    def limits(script, argv, env)
      @added ||= !ENV.delete(ADDED).nil?
      return unless Config.current.tune?
      return if ENV.key?("RUBY_GC_MALLOC_LIMIT") || Zr.compiled?

      ENV.update(GC_ENV)
      exec(env.merge(ADDED => "1"), RbConfig.ruby, script, *argv) if script
    end

    # The environment changes for a program that zr runs: without the
    # limits that zr set for itself, so the program sees the environment
    # that the user gave zr.
    def program_env = @added ? GC_ENV.transform_values { nil } : {}

    def yjit
      @pending = false
      RubyVM::YJIT.enable if Config.current.tune? && defined?(RubyVM::YJIT.enable)
    end
  end
end
