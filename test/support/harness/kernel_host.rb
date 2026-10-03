# frozen_string_literal: true

require_relative "../../../lib/zr/machine/host"
require_relative "../../../lib/zr/paths"

module Zr
  module Harness
    # Kernel files run on CRuby (`Machine::Host`), with the interface of
    # `KernelJIT`: a test that runs on both compares the kernel's Ruby
    # with the code zr compiles from it.
    class KernelHost
      # The imports of the portable kernel, which any of its files can call.
      IMPORTS = File.join(Paths::RUNTIME, "kernel/imports.rb")

      # `patterns` are globs under lib/zr/runtime/kernel, or absolute paths. `constants` sets the
      # constants that the files read from a kernel file outside them.
      def initialize(*patterns, constants: {})
        files = patterns.flat_map { |pattern| Dir[File.expand_path(pattern, File.join(Paths::RUNTIME, "kernel"))].sort }
        raise ArgumentError, "no kernel file matches #{patterns.inspect}" if files.empty?

        @host = Machine::Host.new([IMPORTS, *files].uniq, constants: constants)
      end

      # Calls the kernel def `name` with `args`, and returns what it
      # returns.
      def call(name, *) = @host.call(name, *)
    end
  end
end
