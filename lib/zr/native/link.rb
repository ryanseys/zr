# frozen_string_literal: true

require_relative "toolchain"
require_relative "../target"

module Zr
  module Native
    # Links objects into a binary with the target's `cc`. `Link::Darwin`
    # uses it only when zr's Mach-O linker refuses, or with
    # `ZR_LINKER=cc`. `Link::Static` uses it for every ELF binary.
    module Link
      module_function

      # Returns nil, or the linker's message when it refused.
      #: (Array[String] objects, String out, ?flags: Array[String], ?target: Target) -> String?
      def run(objects, out, flags: [], target: Target.default)
        log, ok = Toolchain.run([Toolchain.command(target, "cc"), "-o", out, *objects, *flags])
        ok ? nil : log.strip
      end
    end
  end
end
