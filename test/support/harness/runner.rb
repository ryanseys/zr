# frozen_string_literal: true

require "rbconfig"
require_relative "../../../lib/ze0/cli"
require_relative "../../../lib/ze0/target"

module Ze0
  module Harness
    # How a whole program is built for one target and what it built is
    # run, and whose recording the answer is held to. A native binary
    # runs on its own host; a wasm module runs under wasmtime, with the
    # test directory preopened and the environment passed in by name.
    class Runner
      # The recording's name for each OS.
      PLATFORMS = { darwin: "macos", linux: "linux", wasi: "wasi" }.freeze

      attr_reader :target

      # The target a run builds for: the host's own, or the one
      # `ZE0_TARGET` names, as the cross-target rows of CI do. A triple
      # no target answers to is named here rather than failing later.
      def self.named(triple)
        return Target.default if triple.nil? || triple.empty?

        Target.fetch(triple) or raise ArgumentError, "no target #{triple}; `ze0 targets` names them"
      end


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

          return "#{@target.triple} modules run under wasmtime, which is not on the PATH"
        end
        return nil if @target.native?

        "#{@target.triple} binaries run only on their own host, and this host is #{Target.host_triple}"
      end

      # The build of `rel` into `out`: ruby without rubygems, which the
      # compiler never asks for, under the collector tuning `ze0` would
      # otherwise start a second process to get.
      def build_argv(rel, out)
        [RbConfig.ruby, "--disable-gems", File.join(@root, "exe/ze0"), "zr", "build", rel, "-o", out,
         "--target", @target.triple]
      end

      def build_env = CLI::GC_ENV

      # The run of `out` with `args` under `env`: the command, and the
      # environment the process itself takes.
      def run(out, args, env)
        return [[out, *args], env] unless wasm?

        [["wasmtime", "run", "--dir", ".", *env.flat_map { |key, value| ["--env", "#{key}=#{value}"] }, out, *args], {}]
      end

      # wasmtime's report of a trap, which ends the module as abort(3)
      # ends a process, and counts as a crash.
      def trapped?(answer) = wasm? && answer.stderr.include?("wasm trap: ")
    end
  end
end
