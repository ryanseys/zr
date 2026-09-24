# frozen_string_literal: true

require_relative "toolchain"
require_relative "../target"

module Zr
  module Native
    # The link step through a target's `cc`: objects to a binary.
    # `Link::Darwin` runs it only for what zr's own Mach-O linker refuses,
    # or under `ZR_LINKER=cc`; `Link::Static` for every ELF binary.
    module Link
      # The main thread's stack, which holds ruby frames as native frames.
      # `runtime/kernel/fiber.rb` sizes every other task's.
      STACK = 0x400_0000

      module_function

      # Answers nil, or the linker's message when it refused.
      def run(objects, out, flags: [], target: Target.default)
        log, ok = Toolchain.run([Toolchain.command(target, "cc"), "-o", out, *objects, *flags])
        ok ? nil : log.strip
      end
    end
  end
end
