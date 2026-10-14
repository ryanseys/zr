# frozen_string_literal: true

require_relative "../../../lib/zr/paths"

module Zr
  module Harness
    # The kernel files that a KernelJIT or a KernelHost takes: the imports
    # of the portable kernel, which any file can call, then the files that
    # `patterns` match. A pattern is a glob under lib/zr/runtime/kernel,
    # or an absolute path.
    module KernelFiles
      IMPORTS = File.join(Paths::RUNTIME, "kernel/imports.rb")

      def self.[](*patterns)
        files = patterns.flat_map { |pattern| Dir[File.expand_path(pattern, File.join(Paths::RUNTIME, "kernel"))].sort }
        raise ArgumentError, "no kernel file matches #{patterns.inspect}" if files.empty?

        [IMPORTS, *files].uniq
      end
    end
  end
end
