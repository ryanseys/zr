# frozen_string_literal: true

require_relative "../link"
require_relative "../../deps"
require_relative "../../obj/elf/object_file"

module Ze0
  module Native
    module Link
      # A static ELF binary, linked by the target host's `cc` against its
      # static libc (musl): the whole program in one file, no loader.
      module Static
        # `--build-id=none`: a link of the same objects writes the same
        # bytes. `-no-pie`: a toolchain's default decides nothing, and
        # Alpine's gcc would make a static PIE where musl-cross makes an
        # ET_EXEC. The stack is not executable.
        FLAGS = ["-static", "-no-pie", "-Wl,--build-id=none", "-Wl,-z,noexecstack"].freeze

        # What nothing calls is left out: every item is a section of its own.
        STRIP_FLAGS = ["-Wl,--gc-sections"].freeze

        module_function

        # Answers nil, or the linker's message. There is no Ruby linker for
        # ELF yet, so `road` has nothing to choose between.
        def link(image, out, work:, objects:, strip:, road:, target:)
          return "no linker but cc writes an ELF binary" if road == "ruby"

          obj = File.join(work, "unit.o")
          File.binwrite(obj, Obj::Elf::ObjectFile.write(image))
          Link.run(objects + [obj], out, archives: Deps.build(target), flags: FLAGS + (strip ? STRIP_FLAGS : []), target: target)
        end

        # The byte ranges of a linked binary that no input decides: none,
        # since the link writes no build ID.
        def stamps(_bytes) = []
      end
    end
  end
end
