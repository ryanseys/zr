# frozen_string_literal: true

require_relative "../link"
require_relative "../../obj/macho/object_file"
require_relative "../../obj/macho/executable"
require_relative "../../obj/macho/prelink"
require_relative "../../obj/macho/stamps"

module Zr
  module Native
    module Link
      # Links a Mach-O binary for aarch64-apple-darwin.
      # `Obj::MachO::Executable` links the program against the runtime's
      # objects (prelinked once and kept, `Native::Build.prelink`) and
      # writes the binary. `cc` links only what it refuses, or every
      # program with `ZR_LINKER=cc`.
      module Darwin
        # `ld` writes this value to `LC_MAIN.stacksize`.
        # `Obj::MachO::Executable` writes that field from the same value, so
        # the stack size is the same with both linkers.
        STACK_FLAGS = ["-Wl,-stack_size,0x#{STACK.to_s(16)}"].freeze

        # A program without eval calls the runtime only through calls that
        # the linker can see, so the linker removes code that nothing
        # calls. An executable from `ld` exports every global, and ld keeps
        # exported symbols, so this also removes the exports. A program
        # with eval keeps them: its JIT uses dlsym when the symbol table is
        # not sorted.
        STRIP_FLAGS = ["-Wl,-dead_strip", "-Wl,-no_exported_symbols"].freeze

        module_function

        # Returns nil, or the message of the step that refused. `linker`
        # selects the linker. `auto` uses `Obj::MachO::Executable`, and
        # `cc` for what it refuses. `ruby` returns the refusal and does not
        # use `cc`. `cc` does not use `Obj::MachO::Executable`. A program
        # that does not strip uses eval; its JIT finds the runtime's
        # functions by name in the symbol table, which
        # `Obj::MachO::Executable` sorts.
        def link(image, out, work:, objects:, strip:, linker:, target:)
          unless linker == "cc"
            why = begin
              Obj::MachO::Executable.write(image, out, prelink: Build.prelink(objects), skeleton: Build.skeleton(objects))
            rescue Obj::MachO::Refused => e
              e.message
            end
            return nil unless why
            return "Obj::MachO::Executable cannot link this: #{why}" if linker == "ruby" || !target.tool("cc")
          end
          obj = File.join(work, "unit.o")
          File.binwrite(obj, Obj::MachO::ObjectFile.write(image))
          Link.run(objects + [obj], out, flags: STACK_FLAGS + (strip ? STRIP_FLAGS : []), target: target)
        end

        # The byte ranges of a linked binary that do not depend on the
        # inputs: the UUID that `ld` writes and the code signature of its page.
        def stamps(bytes) = Obj::MachO::Stamps.of(bytes)
      end
    end
  end
end
