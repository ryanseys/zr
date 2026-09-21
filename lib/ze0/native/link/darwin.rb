# frozen_string_literal: true

require_relative "../link"
require_relative "../../obj/macho/object_file"
require_relative "../../obj/macho/executable"
require_relative "../../obj/macho/prelink"
require_relative "../../obj/macho/stamps"

module Ze0
  module Native
    module Link
      # A Mach-O binary for aarch64-apple-darwin. `Obj::MachO::Executable`
      # links the program beside the runtime's objects, linked once and kept
      # (`Native::Build.prelink`), and writes the binary; `cc` links only
      # what it refuses, or every program under `ZE0_LINK=cc`.
      module Darwin
        # `ld` turns this into `LC_MAIN.stacksize`. `Obj::MachO::Executable`
        # writes that field itself from the same number, so a program gets
        # the same room whichever road links it.
        STACK_FLAGS = ["-Wl,-stack_size,0x#{STACK.to_s(16)}"].freeze

        # A program that does not eval reaches the runtime only through
        # calls the linker can see, so what nothing calls is left out. An
        # executable exports every global, and ld keeps what is exported,
        # so the exports go too.
        STRIP_FLAGS = ["-Wl,-dead_strip", "-Wl,-no_exported_symbols"].freeze

        module_function

        # Answers nil, or the message of the step that refused. `road`
        # picks the linker: `auto` takes `Obj::MachO::Executable` and `cc`
        # for what it refuses, `ruby` answers what it refused rather than
        # reaching for `cc`, and `cc` skips it. A program that does not
        # strip evals, and its JIT finds the runtime's functions by name,
        # so every global is exported.
        def link(image, out, work:, objects:, strip:, road:, target:)
          unless road == "cc"
            why = begin
              Obj::MachO::Executable.write(image, out, prelink: Build.prelink(objects), exports: !strip,
                                                       skeleton: Build.skeleton(objects))
            rescue Obj::MachO::Refused => e
              e.message
            end
            return nil unless why
            return "Obj::MachO::Executable cannot link this: #{why}" if road == "ruby" || !target.tool("cc")
          end
          obj = File.join(work, "unit.o")
          File.binwrite(obj, Obj::MachO::ObjectFile.write(image))
          Link.run(objects + [obj], out, flags: STACK_FLAGS + (strip ? STRIP_FLAGS : []), target: target)
        end

        # The byte ranges of a linked binary that no input decides: the
        # UUID `ld` writes and the signature over its page.
        def stamps(bytes) = Obj::MachO::Stamps.of(bytes)
      end
    end
  end
end
