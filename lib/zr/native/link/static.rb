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
        FLAGS = ["-static", "-no-pie", "-Wl,--build-id=none", "-Wl,-z,noexecstack"].freeze #: Array[String]

        # Removes code that nothing calls. Each item is in its own section.
        STRIP_FLAGS = ["-Wl,--gc-sections"].freeze #: Array[String]

        module_function

        # Returns nil, or the linker's message. zr has no Ruby linker for
        # ELF, so `linker` has only `cc` to select.
        # @rbs image: Obj::Unit
        # @rbs out: String
        # @rbs work: String
        # @rbs objects: Array[String]
        # @rbs strip: bool
        # @rbs linker: String
        # @rbs target: Target
        # @rbs link: Array[String]
        # @rbs embeds: Array[Obj::MachO::Relink]
        # @rbs return: String?
        def link(image, out, work:, objects:, strip:, linker:, target:, link: [], embeds: [])
          return "an ELF binary cannot embed a Mach-O bundle" unless embeds.empty?
          return "ZR_LINKER=ruby: zr has no linker of its own for an ELF binary. Set ZR_LINKER=auto or cc" if linker == "ruby"

          obj = File.join(work, "unit.o")
          File.binwrite(obj, Obj::Elf::ObjectFile.write(image, arch: target.arch))
          Link.run(objects + [obj], out, flags: FLAGS + Toolchain.elf_linker_flags + (strip ? STRIP_FLAGS : []) + link, target: target)
        end

        # The byte ranges of a linked binary that do not depend on the
        # inputs: none, because the link writes no build ID.
        #: (String _bytes) -> Array[Range[Integer]]
        def stamps(_bytes) = []
      end
    end
  end
end
