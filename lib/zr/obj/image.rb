# frozen_string_literal: true

require_relative "macho/image"
require_relative "elf/image"

module Zr
  module Obj
    # A reader of a C extension's object or image in the target's format:
    # Mach-O for darwin, ELF for linux. Both readers answer `defined`,
    # `undefined`, `c_name` and `c_strings`.
    module Image
      module_function

      #: (String bytes) -> (MachO::Image | Elf::Image)
      def read(bytes) = Elf::Image.elf?(bytes) ? Elf::Image.read(bytes) : MachO::Image.read(bytes)
    end
  end
end
