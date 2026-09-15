# frozen_string_literal: true

require_relative "toolchain"
require_relative "../target"

module Ze0
  module Native
    # The link step: objects and static archives to a binary, with the
    # target's linker through its `cc`. `Link::Darwin` and `Link::Static` say
    # which objects a target's link takes and which flags; this runs it.
    module Link
      # The main thread's stack, which holds ruby frames as native frames.
      # `rt/kernel/fiber.rb` sizes every other task's.
      STACK = 0x400_0000

      module_function

      # Answers nil, or the linker's message when it refused.
      def run(objects, out, archives: [], flags: [], target: Target.default)
        log, ok = Toolchain.run([Toolchain.command(target, "cc"), "-o", out, *objects, *archives, *flags])
        ok ? nil : log.strip
      end
    end
  end
end
