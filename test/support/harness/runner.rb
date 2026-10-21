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
    # its own host, or through `ZR_TEST_EXEC`. A wasm module runs under
    # wasmtime, with the test directory preopened and each environment
    # variable passed by name.
    class Runner
      # The platform name in recording file names, for each OS.
      PLATFORMS = { darwin: "macos", linux: "linux", wasi: "wasi" }.freeze

      attr_reader :target

      # `compiler` is the wasmtime compiler for a module: the tests'
      # default, or Cranelift when run speed is the result (`zr-dev bench`).
      def initialize(root, target = Target.default, compiler: Wasmtime.compiler)
        @root = root
        @target = target
        @compiler = compiler
      end

      def platform = PLATFORMS.fetch(@target.os)

      # The name of the recordings that this target's answers may differ
      # by (`foo.rb.<name>.expected`): on Linux the platform and the libc
      # (`linux-gnu`, `linux-musl`), as glibc and musl differ in strerror
      # text, qsort order and libm digits; elsewhere the platform.
      def recording = @target.os == :linux ? "linux-#{@target.libc == :glibc ? "gnu" : "musl"}" : platform

      def wasm? = @target.outputs == [:wasm]

      # nil when this host can run the target's output, else the reason.
      def refusal
        if wasm?
          return nil if Wasmtime.installed?

          return "#{@target.triple} modules run under wasmtime, which is not on the PATH"
        end
        return nil if @target.runs_here? || exec

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

      # The command words that run a binary on a host of the target, from
      # `ZR_TEST_EXEC`: the binary and its arguments follow them, in the
      # test's directory and environment.
      def exec = ENV["ZR_TEST_EXEC"]&.split&.then { |words| words.empty? ? nil : words }

      # The command that runs `out` with `args` under `env`, and the
      # environment for the process itself.
      #
      # A module must run under the same conditions as a binary. Thus the
      # guest gets the test directory and its own temporary directory. A
      # WASI guest sees only the directories and variables that it is
      # given. Without a temporary directory, `Dir.tmpdir` fails, and a
      # program that writes a file fails where the binary does not. The
      # module is compiled first (`precompile`), so the memory limit of a
      # run counts the program and not wasmtime's compiler. A caller that
      # times the compile gives its result as `compiled`.
      def run(out, args, env, compiled: :here)
        return [[*exec, out, *args], env] if exec && !wasm?
        return [[out, *args], env] unless wasm?

        dirs = { "." => ".", Dir.tmpdir => "/tmp" }
        compiled = precompile(out) if compiled == :here
        env = { "TMPDIR" => "/tmp" }.merge(env)
        if compiled.is_a?(Hash)
          return [Wasmtime.run(out, *args, dirs: dirs, env: env, compiler: split_compiler, preload: compiled.fetch(:preload)), {}]
        end

        [Wasmtime.run(compiled || out, *args, dirs: dirs, env: env, compiler: @compiler, argv0: (out if compiled)), {}]
      end

      # The compiled form of a wasm module `out`, or nil: a native binary
      # needs none. For a program module, `{ preload: }` names its compiled
      # runtime (`Wasmtime.runtime`); wasmtime compiles the small program
      # module as it runs it.
      def precompile(out)
        return nil unless wasm?

        name = Wasmtime.runtime_of(out)
        return Wasmtime.precompile(out, compiler: @compiler) unless name

        path = [File.dirname(out), Wasmtime.split_dir].map { |dir| File.join(dir, name) }.find { |file| File.file?(file) }
        preload = path && Wasmtime.runtime(path, compiler: split_compiler)
        preload ? { preload: preload } : nil
      end

      # The compiler of a split run: the one given to this runner when it
      # is not the tests' default (`zr-dev bench`), else the split default.
      def split_compiler = @compiler == Wasmtime.compiler ? Wasmtime.split_compiler : @compiler

      # True when wasmtime reports a trap. A trap stops the module as
      # abort(3) stops a process, so it counts as a crash.
      def trapped?(answer) = wasm? && answer.stderr.include?("wasm trap: ")
    end
  end
end
