# frozen_string_literal: true

require_relative "toolchain"

module Ze0
  module Native
    # The link step: objects and static archives to a binary, with the
    # system linker through `cc`. The one place ze0 leaves Ruby to make a
    # binary, and the seam `Obj::Exe` replaces when it lands.
    module Link
      module_function

      # Answers nil, or the linker's message when it refused.
      def run(objects, out, archives: [], flags: [])
        log, ok = Toolchain.run(["cc", "-o", out, *objects, *archives, *flags])
        ok ? nil : log.strip
      end
    end
  end
end
