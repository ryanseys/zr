# frozen_string_literal: true

require "rbconfig"
require_relative "../target"

module Ze0
  module Harness
    # How the corpus builds a program for one target and runs what it
    # built, and whose recording the answer is held to. A native binary
    # runs on its own host; a wasm module runs under wasmtime, with the
    # test directory preopened and the environment passed in by name.
    class Runner
      # The recording's name for each OS.
      PLATFORMS = { darwin: "macos", linux: "linux", wasi: "wasi" }.freeze

      attr_reader :target

      def initialize(root, target = Target.default)
        @root = root
        @target = target
      end

      def platform = PLATFORMS.fetch(@target.os)

      def wasm? = @target.roads == [:wasm]

      # nil when this host runs what the target builds, else why not.
      def refusal
        if wasm?
          return nil if Target.tool?("wasmtime")

          return "the corpus runs #{@target.triple} modules under wasmtime, which is not on the PATH"
        end
        return nil if @target.native?

        "the corpus runs #{@target.triple} binaries only on their own host, and this host is #{Target.host_triple}"
      end

      # The build of `rel` into `out`.
      def build_argv(rel, out)
        [RbConfig.ruby, File.join(@root, "bin/ze0"), "zr", "build", rel, "-o", out, "--target", @target.triple]
      end

      # The run of `out` with `args` under `env`: the command, and the
      # environment the process itself takes.
      def run(out, args, env)
        return [[out, *args], env] unless wasm?

        [["wasmtime", "run", "--dir", ".", *env.flat_map { |key, value| ["--env", "#{key}=#{value}"] }, out, *args], {}]
      end

      # wasmtime's report of a trap, which ends the module as abort(3)
      # ends a process: the corpus counts it as a crash.
      def trapped?(answer) = wasm? && answer.stderr.include?("wasm trap: ")
    end
  end
end
