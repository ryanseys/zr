# frozen_string_literal: true

require_relative "registers"
require_relative "assembler"
require_relative "../../obj/model"

module Zr
  module Backend
    module X86_64
      # The functions that the kernel subset cannot express, in x86-64
      # machine code for the System V ABI.
      module Stub
        include Registers

        # The context `zr_switch` saves and restores: the callee-saved
        # registers, rsp, the address to resume at, and the SSE and x87
        # control words (`kernel/arch/x86_64/context.rb` reads it).
        CONTEXT = { rbx: 0, rbp: 8, r12: 16, r13: 24, r14: 32, r15: 40, rsp: 48, rip: 56, mxcsr: 64, fpucw: 68 }.freeze #: Hash[Symbol, Integer]
        CONTEXT_BYTES = 72
        SAVED = { rbx: RBX, rbp: RBP, r12: R12, r13: R13, r14: R14, r15: R15 }.freeze #: Hash[Symbol, Registers::Register]

        # A C frame record's context follows its five fields.
        CFRAME_CONTEXT = 40
        # The Value that `zr_cframe_call` returns after a leap.
        QUNDEF = 0x24

        module_function

        # `zr_switch(from: Ptr, to: Ptr)`: saves this stack in `from`, and
        # resumes the stack in `to`. A context resumes with a jump to its
        # rip with its rsp, as a return to the caller of `zr_switch`.
        #: (?assembler: singleton(Assembler)) -> Obj::Code
        def switch(assembler: Assembler)
          a = assembler.new
          SAVED.each { |name, r| a.store([RDI, CONTEXT.fetch(name)], r) }
          a.lea RAX, [RSP, 8]
          a.store([RDI, CONTEXT[:rsp]], RAX)
          a.load RAX, [RSP, 0]
          a.store([RDI, CONTEXT[:rip]], RAX)
          a.stmxcsr [RDI, CONTEXT[:mxcsr]]
          a.fnstcw [RDI, CONTEXT[:fpucw]]
          load_context(a, RSI)
          Obj::Code.new("zr_switch", a.to_binary, align: 16)
        end

        # `zr_cframe_call(record: Ptr, fn: Ptr, argv: Ptr, argc: Word) -> Word`:
        # calls the C function `fn` with the `argc` words at `argv`, the
        # first six in registers and the rest on the stack, and returns its
        # rax. `argv` holds at least eight words. It first saves a context
        # in `record` that resumes at a landing here, so a C-API function
        # can leap back (`zr_cframe_leap`); the landing returns undef.
        #: (?assembler: singleton(Assembler)) -> Obj::Code
        def cframe_call(assembler: Assembler)
          a = assembler.new
          landing = a.make_label("landing")
          copy = a.make_label("copy")
          call = a.make_label("call")
          a.push RBP
          a.mov RBP, RSP
          a.push RBX
          a.push R12
          save_context(a, RDI, landing)
          a.mov RBX, RDI
          a.mov R11, RSI
          a.mov R12, RDX
          a.mov RAX, RCX
          a.sub RAX, 6
          a.j :le, call
          # The words after the sixth, at the bottom of a 16-byte aligned
          # area below rsp.
          a.lea R10, [RAX, 1]
          a.and R10, -2
          a.shl R10, 3
          a.sub RSP, R10
          a.lea RSI, [R12, 48]
          a.mov RDI, RSP
          a.put_label copy
          a.load RDX, [RSI, 0]
          a.store([RDI, 0], RDX)
          a.add RSI, 8
          a.add RDI, 8
          a.sub RAX, 1
          a.j :ne, copy
          a.put_label call
          ARGS.each_with_index { |r, n| a.load(r, [R12, 8 * n]) }
          a.mov_imm RAX.w, 0
          a.call_reg R11
          a.load RSP, [RBX, CFRAME_CONTEXT + CONTEXT[:rsp]]
          a.pop R12
          a.pop RBX
          a.pop RBP
          a.ret
          a.put_label landing
          a.pop R12
          a.pop RBX
          a.pop RBP
          a.mov_imm RAX, QUNDEF
          a.ret
          Obj::Code.new("zr_cframe_call", a.to_binary, align: 16)
        end

        # `zr_cframe_leap(record: Ptr)`: resumes the context that
        # `zr_cframe_call` saved in `record`, so that call returns undef.
        #: (?assembler: singleton(Assembler)) -> Obj::Code
        def cframe_leap(assembler: Assembler)
          a = assembler.new
          a.lea RDI, [RDI, CFRAME_CONTEXT]
          load_context(a, RDI)
          Obj::Code.new("zr_cframe_leap", a.to_binary, align: 16)
        end

        # `zr_gc_call(fn: Ptr, a: Ptr, b: Ptr) -> Word`: a tail call of the
        # C function `fn(a, b)` for the collector.
        #: (?assembler: singleton(Assembler)) -> Obj::Code
        def gc_call(assembler: Assembler)
          a = assembler.new
          a.mov RAX, RDI
          a.mov RDI, RSI
          a.mov RSI, RDX
          a.jmp_reg RAX
          Obj::Code.new("zr_gc_call", a.to_binary, align: 16)
        end

        # The C functions of one Value argument that return a two-word
        # struct by value, in rax and rdx, and the kernel def that fills it.
        PAIR_RESULTS = { "rb_time_timespec" => "zr_capi_time_timespec", "rb_time_timeval" => "zr_capi_time_timeval",
                         "rb_time_interval" => "zr_capi_time_interval" }.freeze #: Hash[String, String]

        # A C function of PAIR_RESULTS: its filler writes 16 bytes of this
        # frame, then the stub loads the two words.
        #: (String name, ?assembler: singleton(Assembler)) -> Obj::Code
        def pair_result(name, assembler: Assembler)
          a = assembler.new
          a.push RBP
          a.mov RBP, RSP
          a.sub RSP, 16
          a.mov RSI, RSP
          relocs = [] #: Array[Obj::Reloc]
          a.call_rel { |at| relocs << Obj::Reloc.new(at, :plt32, PAIR_RESULTS.fetch(name), -4) }
          a.load RAX, [RSP, 0]
          a.load RDX, [RSP, 8]
          a.mov RSP, RBP
          a.pop RBP
          a.ret
          Obj::Code.new(name, a.to_binary, relocs: relocs, align: 16)
        end

        # Saves the callee-saved registers, rsp and the control words in
        # the context at `base`, with `resume` as the address to resume at.
        #: (Assembler a, Registers::Register base, Assembler::Label resume) -> void
        def save_context(a, base, resume)
          SAVED.each { |name, r| a.store([base, CFRAME_CONTEXT + CONTEXT.fetch(name)], r) }
          a.store([base, CFRAME_CONTEXT + CONTEXT[:rsp]], RSP)
          a.lea_label RAX, resume
          a.store([base, CFRAME_CONTEXT + CONTEXT[:rip]], RAX)
          a.stmxcsr [base, CFRAME_CONTEXT + CONTEXT[:mxcsr]]
          a.fnstcw [base, CFRAME_CONTEXT + CONTEXT[:fpucw]]
        end

        # Loads a context from `base` and jumps to its rip.
        #: (Assembler a, Registers::Register base) -> void
        def load_context(a, base)
          SAVED.each { |name, r| a.load(r, [base, CONTEXT.fetch(name)]) }
          a.ldmxcsr [base, CONTEXT[:mxcsr]]
          a.fldcw [base, CONTEXT[:fpucw]]
          a.load RSP, [base, CONTEXT[:rsp]]
          a.load RAX, [base, CONTEXT[:rip]]
          a.jmp_reg RAX
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
