# frozen_string_literal: true

require_relative "../link"
require_relative "../../ext/c_api"
require_relative "../../obj/elf/object_file"

module Zr
  module Native
    module Link
      # Links a dynamic ELF binary with the target host's `cc` against its
      # shared libc (glibc). ld.so loads libc, libm and libcrypt at start,
      # and a C extension that the program dlopens finds ruby's C API in
      # the binary's own dynamic symbols.
      module Dynamic
        # `--build-id=none`: the same objects always link to the same
        # bytes. `-no-pie`: an ET_EXEC at a fixed address, as the static
        # targets are. `-z now` binds every import at start. glibc 2.34
        # and later keep pthread and dl in libc.so.6; libm and libcrypt
        # are their own objects.
        FLAGS = ["-no-pie", "-Wl,--build-id=none", "-Wl,-z,noexecstack", "-Wl,-z,now"].freeze #: Array[String]
        LIBRARIES = ["-lm", "-lcrypt"].freeze #: Array[String]

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
          list = File.join(work, "exports.list")
          File.write(list, exports)
          flags = FLAGS + ["-Wl,--dynamic-list=#{list}"] + (strip ? STRIP_FLAGS : []) + link + LIBRARIES
          Link.run(objects + [obj], out, flags: flags, target: target)
        end

        # The dynamic list: the C API, which a C extension's undefined
        # `rb_*` names bind to. ld leaves out a name that no object
        # defines.
        #: () -> String
        def exports = "{\n#{Ext::CApi.names.sort.map { |name| "  #{name};\n" }.join}};\n"

        # The byte ranges of a linked binary that do not depend on the
        # inputs: none, because the link writes no build ID.
        #: (String _bytes) -> Array[Range[Integer]]
        def stamps(_bytes) = []
      end
    end
  end
end
