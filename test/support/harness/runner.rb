# frozen_string_literal: true

require "rbconfig"
require "tmpdir"
require_relative "../../../lib/zr/cli"
require_relative "../../../lib/zr/target"
require_relative "wasmtime"

module Zr
  module Harness
    # Builds a whole program for one target, runs the result, and selects
    # the recording to check the output against. A native binary runs on
    # its own host. A wasm module runs under wasmtime, with the test
    # directory preopened and each environment variable passed by name.
    class Runner
      # The platform name in recording file names, for each OS.
      PLATFORMS = { darwin: "macos", linux: "linux", wasi: "wasi" }.freeze

      attr_reader :target

      # The target to build for: the host's target, or the target that
      # `ZR_TARGET` gives, as in the cross-target CI jobs. An unknown
      # triple raises an error here, not later.
      def self.named(triple)
        return Target.default if triple.nil? || triple.empty?

        Target.fetch(triple) or raise ArgumentError, "no target #{triple}; `zr targets` names them"
      end

      # `compiler` is the wasmtime compiler for a module: the tests'
      # default, or Cranelift when run speed is the result (`zr-dev bench`).
      def initialize(root, target = Target.default, compiler: Wasmtime.compiler)
        @root = root
        @target = target
        @compiler = compiler
      end

      def platform = PLATFORMS.fetch(@target.os)

      def wasm? = @target.outputs == [:wasm]

      # nil when this host can run the target's output, else the reason.
      def refusal
        if wasm?
          return nil if Wasmtime.installed?

          return "#{@target.triple} modules run under wasmtime, which is not on the PATH"
        end
        return nil if @target.runs_here?

        "#{@target.triple} binaries run only on their own host, and this host is #{Target.host_triple}"
      end

      # The command that builds `rel` into `out`. It runs ruby without
      # rubygems, which the compiler does not use, with the GC tuning in
      # `build_env`. Without it, `zr` starts a second process to set that
      # tuning.
      def build_argv(rel, out)
        [RbConfig.ruby, "--disable-gems", File.join(@root, "exe/zr"), "build", rel, "-o", out,
         "--target", @target.triple]
      end

      def build_env = GcTuning::GC_ENV

      # The command that runs `out` with `args` under `env`, and the
      # environment for the process itself.
      #
      # A module must run under the same conditions as a binary. Thus the
      # guest gets the test directory and its own temporary directory. A
      # WASI guest sees only the directories and variables that it is
      # given. Without a temporary directory, `Dir.tmpdir` fails, and a
      # program that writes a file fails where the binary does not. The
      # module is compiled first (`Wasmtime.precompile`), so the memory
      # limit of a run counts the program and not wasmtime's compiler.
      def run(out, args, env)
        return [[out, *args], env] unless wasm?

        dirs = { "." => ".", Dir.tmpdir => "/tmp" }
        compiled = Wasmtime.precompile(out, compiler: @compiler)
        [Wasmtime.run(compiled || out, *args, dirs: dirs, env: { "TMPDIR" => "/tmp" }.merge(env), compiler: @compiler,
                                              argv0: (out if compiled)), {}]
      end

      # True when wasmtime reports a trap. A trap stops the module as
      # abort(3) stops a process, so it counts as a crash.
      def trapped?(answer) = wasm? && answer.stderr.include?("wasm trap: ")
    end
  end
end
