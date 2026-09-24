# frozen_string_literal: true

require "rbconfig"
require "tmpdir"
require_relative "../../../lib/zr/cli"
require_relative "../../../lib/zr/target"
require_relative "wasmtime"

module Zr
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
      # `ZR_TARGET` names, as the cross-target rows of CI do. A triple
      # no target answers to is named here rather than failing later.
      def self.named(triple)
        return Target.default if triple.nil? || triple.empty?

        Target.fetch(triple) or raise ArgumentError, "no target #{triple}; `zr targets` names them"
      end


      # `compiler` is wasmtime's, for a module: the checks' choice, or
      # Cranelift where the speed of what runs is the answer (`rake bench`).
      def initialize(root, target = Target.default, compiler: Wasmtime.compiler)
        @root = root
        @target = target
        @compiler = compiler
      end

      def platform = PLATFORMS.fetch(@target.os)

      def wasm? = @target.outputs == [:wasm]

      # nil when this host runs what the target builds, else why not.
      def refusal
        if wasm?
          return nil if Wasmtime.installed?

          return "#{@target.triple} modules run under wasmtime, which is not on the PATH"
        end
        return nil if @target.native?

        "#{@target.triple} binaries run only on their own host, and this host is #{Target.host_triple}"
      end

      # The build of `rel` into `out`: ruby without rubygems, which the
      # compiler never asks for, under the collector tuning `zr` would
      # otherwise start a second process to get.
      def build_argv(rel, out)
        [RbConfig.ruby, "--disable-gems", File.join(@root, "exe/zr"), "build", rel, "-o", out,
         "--target", @target.triple]
      end

      def build_env = CLI::GC_ENV

      # The run of `out` with `args` under `env`: the command, and the
      # environment the process itself takes.
      #
      # A module is asked the same question as a binary or it is not the
      # same question, so the guest gets the test directory and a
      # temporary directory of its own. Without the second, `Dir.tmpdir`
      # finds nothing to answer with -- a WASI guest sees no filesystem
      # it was not given and no environment it was not passed -- and a
      # program that writes a file fails where the binary does not.
      def run(out, args, env)
        return [[out, *args], env] unless wasm?

        dirs = { "." => ".", Dir.tmpdir => "/tmp" }
        [Wasmtime.run(out, *args, dirs: dirs, env: { "TMPDIR" => "/tmp" }.merge(env), compiler: @compiler), {}]
      end

      # wasmtime's report of a trap, which ends the module as abort(3)
      # ends a process, and counts as a crash.
      def trapped?(answer) = wasm? && answer.stderr.include?("wasm trap: ")
    end
  end
end
