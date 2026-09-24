# frozen_string_literal: true

require_relative "../../lib/zr/obj/model"

module Zr
  module Test
    # The object unit that the ELF and Mach-O writer tests write: a `main`
    # that exits 3, a string, a table that points at the string, and a
    # bss block. Each format test reads its output back.
    module ObjUnit
      # `mov w0, #3; bl exit`, the branch patched by the link.
      MAIN_EXIT_3 = [0x60, 0x00, 0x80, 0x52, 0x00, 0x00, 0x00, 0x94].pack("C*")

      module_function

      # `addend` is the addend of the table's pointer to `msg`.
      def unit(addend: 0)
        u = Obj::Unit.new
        u.function("main", MAIN_EXIT_3, relocs: [Obj::Reloc.new(4, :branch26, "exit")])
        u.datum("msg", :text_const, "hello, zr!\n", linkage: :export)
        u.datum("table", :data_const, "\0" * 8, relocs: [Obj::Reloc.new(0, :abs64, "msg", addend)])
        u.datum("counter", :bss, 16)
        u
      end
    end
  end
end
