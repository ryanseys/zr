# frozen_string_literal: true

require "rbconfig"
require_relative "config"
require_relative "paths"

module Zr
  # The collector limits and YJIT for a compile that allocates much.
  #
  # A cold build lowers the kernel, the core and eval support: tens of
  # millions of objects. Ruby reads the collector's malloc limits only
  # at startup, so a process without them starts itself again with them
  # set (3.17 s against 3.47 s for the runtime's 4,733 functions), and
  # YJIT compiles the compiler's hot methods.
  #
  # A warm `zr run` of a small program allocates little. There YJIT costs
  # more than it gives (its own compiling added 0.1 s to a 0.39 s run),
  # and the limits give nothing (a program of json, optparse, set and erb
  # built in the same time without them), while a start again costs
  # 32 ms. So `exe/zr` waits (`later`): the first step of heavy work
  # (`heavy!`, the lowering of the kernel, the core or eval support)
  # starts zr again with the limits, and a process with them turns YJIT
  # on there. That step comes before the build directory exists and
  # before most of the work, so little runs twice. A large program's own
  # lowering only turns YJIT on (`restart: false`): its HIR (bundler:
  # 1.7 s) would be built twice. A test tier and the tools tune fully at
  # once (`now`). `ZR_TUNE=0` keeps ruby's limits and leaves YJIT off.
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

    # Tunes at the first `heavy!`: starts `script` again with the limits
    # then, if this process does not have them, and turns YJIT on.
    def later(script, argv = ARGV, env: {})
      @added ||= !ENV.delete(ADDED).nil?
      @pending = Config.current.tune?
      @restart = @pending && !limited? ? [script, argv.dup, env] : nil
    end

    # Called before heavy work: the lowering of the kernel, the core, eval
    # support or a large program. With `restart`, a process that `later`
    # left without the limits starts again with them, unless a build
    # directory is open (a start again would leave it behind).
    def heavy!(restart: true)
      if restart && @restart && !Paths.tmpdir_open?
        script, argv, env = @restart
        ENV.update(GC_ENV)
        exec(env.merge(ADDED => "1"), RbConfig.ruby, script, *argv)
      end
      yjit if @pending
    end

    def limited? = ENV.key?("RUBY_GC_MALLOC_LIMIT") || Zr.compiled?

    def limits(script, argv, env)
      @added ||= !ENV.delete(ADDED).nil?
      return unless Config.current.tune?
      return if limited?

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
