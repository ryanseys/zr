# frozen_string_literal: true

require_relative "../../../lib/zr/machine/host"
require_relative "kernel_files"

module Zr
  module Harness
    # Kernel files run on CRuby (`Machine::Host`), with the interface of
    # `KernelJIT`: a test that runs on both compares the kernel's Ruby
    # with the code zr compiles from it.
    class KernelHost
      # `patterns` name the files (KernelFiles). `constants` sets the
      # constants that the files read from a kernel file outside them.
      def initialize(*patterns, constants: {})
        @host = Machine::Host.new(KernelFiles[*patterns], constants: constants)
      end

      # Calls the kernel def `name` with `args`, and returns what it
      # returns.
      def call(name, *) = @host.call(name, *)
    end
  end
end
