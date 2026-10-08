# frozen_string_literal: true

require_relative "registers"
require_relative "assembler"
require_relative "../../obj/model"

module Zr
  module Backend
    module Aarch64
      # The functions that the kernel subset cannot express. This file
      # assembles their machine code and gives it as raw bytes to every target path.
      module Stub
        # @rbs skip -- in sig/zr/backend/aarch64/registers.rbs
        include Registers

        # The context `zr_switch` saves and restores: the callee-saved
        # registers x19..x27, the frame pair x29 and x30, sp, and d8..d15.
        # Not x28: it contains the gate word. The gate word belongs to the
        # whole program, not to one stack. Thus a switch does not change it,
        # and a resumed stack sees the current gates.
        CONTEXT = { x19: 0, x21: 16, x23: 32, x25: 48, x27: 64, x29: 80, x30: 88, sp: 96, d8: 104 }.freeze #: Hash[Symbol, Integer]
        CONTEXT_BYTES = 176

        # A C frame record (`CFrame`, lib/zr/runtime/kernel/c_frame.rb):
        # the stub saves its context after the record's five fields.
        # `test/unit/host_boot_test.rb` checks that the kernel's layout
        # agrees.
        CFRAME_CONTEXT = 40
        # The Value that `zr_cframe_call` returns after a leap: undef, a
        # pending unwind.
        QUNDEF = 0x24

        # The registers that a C frame record's context keeps, two at a
        # time, and C's argument registers.
        SAVED_PAIRS = [[X19, X20], [X21, X22], [X23, X24], [X25, X26]].freeze #: Array[[Registers::Register, Registers::Register]]
        DOUBLE_PAIRS = [[D8, D9], [D10, D11], [D12, D13], [D14, D15]].freeze #: Array[[Registers::Register, Registers::Register]]
        ARGUMENT_PAIRS = [[X0, X1], [X2, X3], [X4, X5], [X6, X7]].freeze #: Array[[Registers::Register, Registers::Register]]

        module_function

        # `zr_switch(from: Ptr, to: Ptr)`: saves this stack in `from`, and
        # resumes the stack in `to`. A new context needs only x30 (the start
        # address) and sp (its stack top).
        #: (?assembler: singleton(Assembler)) -> Obj::Code
        def switch(assembler: Assembler)
          a = assembler.new
          pairs = [[X19, X20], [X21, X22], [X23, X24], [X25, X26], [X29, X30]] #: Array[[Registers::Register, Registers::Register]]
          at = [0, 16, 32, 48, CONTEXT[:x29]]
          doubles = [[D8, D9], [D10, D11], [D12, D13], [D14, D15]] #: Array[[Registers::Register, Registers::Register]]
          pairs.each_with_index { |(p, q), i| a.stp p, q, [X0, at[i]] }
          a.str X27, [X0, CONTEXT[:x27]]
          a.mov X9, SP
          doubles.each_with_index { |(p, q), i| a.stp p, q, [X0, CONTEXT[:d8] + (16 * i)] }
          a.str X9, [X0, CONTEXT[:sp]]
          pairs.each_with_index { |(p, q), i| a.ldp p, q, [X1, at[i]] }
          a.ldr X27, [X1, CONTEXT[:x27]]
          a.ldr X9, [X1, CONTEXT[:sp]]
          a.mov SP, X9
          doubles.each_with_index { |(p, q), i| a.ldp p, q, [X1, CONTEXT[:d8] + (16 * i)] }
          a.ret
          Obj::Code.new("zr_switch", a.to_binary, align: 4)
        end

        # `zr_cframe_call(record: Ptr, fn: Ptr, argv: Ptr, argc: Word) -> Word`:
        # calls the C function `fn` with the `argc` words at `argv` as its
        # arguments, the first eight in x0..x7 and the rest on the stack,
        # and returns its x0. `argv` holds at least eight words.
        #
        # It first saves this stack's context in `record` (after its
        # fields, at CFRAME_CONTEXT), with x30 set to
        # a landing in this stub, so a C-API function can leap back here
        # (`zr_cframe_leap`) when an unwind must skip the C frames, as
        # CRuby's rb_raise longjmps. The landing returns undef. The stub
        # keeps the record and the caller's x30 in 16 bytes of stack, and
        # x19 holds the record during the call. It leaves x28 as C or the
        # leap left it; the kernel loads the gate word again after it
        # (`zr_call_c`).
        #: (?assembler: singleton(Assembler)) -> Obj::Code
        def cframe_call(assembler: Assembler)
          a = assembler.new
          landing = a.make_label("landing")
          copy = a.make_label("copy")
          call = a.make_label("call")
          a.sub SP, SP, 16
          a.stp X0, X30, [SP, 0]
          a.add X15, X0, CFRAME_CONTEXT
          save_context(a, X15, landing)
          a.mov X19, X0
          a.mov X16, X1
          a.mov X17, X2
          # The words after the eighth, at the bottom of a 16-byte aligned
          # area below sp.
          a.subs X9, X3, 8
          a.b call, cond: :le
          a.add X10, X9, 1
          a.and X10, X10, 0xFFFF_FFFF_FFFF_FFFE
          a.lsl X10, X10, 3
          a.mov X11, SP
          a.sub X11, X11, X10
          a.mov SP, X11
          a.add X12, X17, 64
          a.put_label copy
          a.ldr X13, [X12, 0]
          a.str X13, [X11, 0]
          a.add X12, X12, 8
          a.add X11, X11, 8
          a.subs X9, X9, 1
          a.b copy, cond: :ne
          a.put_label call
          ARGUMENT_PAIRS.each_with_index { |(p, q), i| a.ldp p, q, [X17, 16 * i] }
          a.blr X16
          a.ldr X9, [X19, CFRAME_CONTEXT + CONTEXT[:sp]]
          a.mov SP, X9
          a.ldr X30, [SP, 8]
          a.add SP, SP, 16
          a.ldr X19, [X19, CFRAME_CONTEXT + CONTEXT[:x19]]
          a.ret
          a.put_label landing
          a.ldr X30, [SP, 8]
          a.add SP, SP, 16
          a.movz X0, QUNDEF
          a.ret
          Obj::Code.new("zr_cframe_call", a.to_binary, align: 4)
        end

        # `zr_cframe_leap(record: Ptr)`: resumes the context that
        # `zr_cframe_call` saved in `record`, so that call returns undef.
        # The frames between, C and kernel, are dropped as a longjmp drops
        # them; the kernel restores its own state first (`zr_cframe_leap`'s
        # caller in lib/zr/runtime/kernel/c_frame.rb).
        #: (?assembler: singleton(Assembler)) -> Obj::Code
        def cframe_leap(assembler: Assembler)
          a = assembler.new
          a.add X0, X0, CFRAME_CONTEXT
          load_context(a, X0)
          a.ret
          Obj::Code.new("zr_cframe_leap", a.to_binary, align: 4)
        end

        # `zr_gc_call(fn: Ptr, data: Ptr) -> Word`: calls the C function
        # `fn` with `data` for the collector, a T_DATA's mark or free
        # function. It is a tail call, so C returns to the caller. No
        # unwind leaves such C (the kernel stops one), so it saves no
        # context.
        #: (?assembler: singleton(Assembler)) -> Obj::Code
        def gc_call(assembler: Assembler)
          a = assembler.new
          a.mov X16, X0
          a.mov X0, X1
          a.br X16
          Obj::Code.new("zr_gc_call", a.to_binary, align: 4)
        end

        # The C functions of one Value argument that return a two-word
        # struct by value, in x0 and x1, and the kernel def that fills it
        # for each: C's `struct timespec` and `struct timeval` of a Time.
        PAIR_RESULTS = { "rb_time_timespec" => "zr_capi_time_timespec", "rb_time_timeval" => "zr_capi_time_timeval",
                         "rb_time_interval" => "zr_capi_time_interval" }.freeze #: Hash[String, String]

        # A C function of PAIR_RESULTS. A kernel def returns one word, so
        # the stub gives its filler 16 bytes of its own frame after the
        # argument, then loads the two words.
        #: (String name, ?assembler: singleton(Assembler)) -> Obj::Code
        def pair_result(name, assembler: Assembler)
          a = assembler.new
          a.sub SP, SP, 32
          a.stp X29, X30, [SP, 0]
          a.mov X29, SP
          a.add X1, SP, 16
          relocs = [] #: Array[Obj::Reloc]
          a.patch_location { |at| relocs << Obj::Reloc.new(at, :branch26, PAIR_RESULTS.fetch(name)) }
          a.bl 0
          a.ldp X0, X1, [SP, 16]
          a.ldp X29, X30, [SP, 0]
          a.add SP, SP, 32
          a.ret
          Obj::Code.new(name, a.to_binary, relocs: relocs, align: 4)
        end

        # Saves the callee-saved registers, x29, sp and d8..d15 in the
        # context at `base`, with `resume` as the x30 that a load returns to.
        #: (Assembler a, Registers::Register base, Assembler::Label resume) -> void
        def save_context(a, base, resume)
          SAVED_PAIRS.each_with_index { |(p, q), i| a.stp p, q, [base, 16 * i] }
          a.str X27, [base, CONTEXT[:x27]]
          a.str X29, [base, CONTEXT[:x29]]
          a.adr X9, resume
          a.str X9, [base, CONTEXT[:x30]]
          a.mov X9, SP
          a.str X9, [base, CONTEXT[:sp]]
          DOUBLE_PAIRS.each_with_index { |(p, q), i| a.stp p, q, [base, CONTEXT[:d8] + (16 * i)] }
        end

        # Loads what `save_context` saved from the context at `base`.
        #: (Assembler a, Registers::Register base) -> void
        def load_context(a, base)
          SAVED_PAIRS.each_with_index { |(p, q), i| a.ldp p, q, [base, 16 * i] }
          a.ldp X29, X30, [base, CONTEXT[:x29]]
          a.ldr X27, [base, CONTEXT[:x27]]
          a.ldr X9, [base, CONTEXT[:sp]]
          a.mov SP, X9
          DOUBLE_PAIRS.each_with_index { |(p, q), i| a.ldp p, q, [base, CONTEXT[:d8] + (16 * i)] }
        end

        # The machine code of the raw function `name` (`Machine::RAW`).
        #: (String name) -> Obj::Code
        def function(name)
          case name
          when "zr_switch" then switch
          when "zr_cframe_call" then cframe_call
          when "zr_cframe_leap" then cframe_leap
          when "zr_gc_call" then gc_call
          when *PAIR_RESULTS.keys then pair_result(name)
          else raise ArgumentError, "no raw function named #{name}"
          end
        end
      end
    end
  end
end
