# frozen_string_literal: true

require_relative "../link"
require_relative "../../obj/elf/object_file"

module Zr
  module Native
    module Link
      # Links a static ELF binary with the target host's `cc` against its
      # static libc (musl). The result is one file with no dynamic loader.
      module Static
        # `--build-id=none`: the same objects always link to the same
        # bytes. `-no-pie`: the result does not depend on the toolchain's
        # default (Alpine's gcc makes a static PIE; musl-cross makes an
        # ET_EXEC). The stack is not executable.
        FLAGS = ["-static", "-no-pie", "-Wl,--build-id=none", "-Wl,-z,noexecstack"].freeze

        # Removes code that nothing calls. Each item is in its own section.
        STRIP_FLAGS = ["-Wl,--gc-sections"].freeze

        module_function

        # Returns nil, or the linker's message. zr has no Ruby linker for
        # ELF, so `linker` has only `cc` to select.
        def link(image, out, work:, objects:, strip:, linker:, target:, link: [])
          return "no linker but cc writes an ELF binary" if linker == "ruby"

          obj = File.join(work, "unit.o")
          File.binwrite(obj, Obj::Elf::ObjectFile.write(image))
          Link.run(objects + [obj], out, flags: FLAGS + (strip ? STRIP_FLAGS : []) + link, target: target)
        end

        # The byte ranges of a linked binary that do not depend on the
        # inputs: none, because the link writes no build ID.
        def stamps(_bytes) = []
      end
    end
  end
end
