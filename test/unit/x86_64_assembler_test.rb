# frozen_string_literal: true
# zr-test: on x86_64

require "test_helper"
require "open3"
require "tmpdir"
require_relative "../../lib/zr/backend/x86_64"
require_relative "../../lib/zr/obj/elf/object_file"

# Encodes each form that the x86-64 codegen and stubs emit, writes the
# code into an ELF object, and reads it back with LLVM's disassembler in
# Intel syntax. It skips when the host has no objdump that reads x86-64.
class X86_64AssemblerTest < Minitest::Test
  include Zr::Backend::X86_64::Registers

  Asm = Zr::Backend::X86_64::Assembler

  # Each form, with the text that the disassembler gives for it.
  FORMS = [
    [->(a) { a.mov RAX, RCX }, "mov rax, rcx"],
    [->(a) { a.mov R12, RDI }, "mov r12, rdi"],
    [->(a) { a.mov RAX.w, R9.w }, "mov eax, r9d"],
    [->(a) { a.mov RSI.b, RAX.b }, "mov sil, al"],
    [->(a) { a.mov_imm RAX, 5 }, "mov eax, 0x5"],
    [->(a) { a.mov_imm R11, 0xFFFF_FFFF }, "mov r11d, 0xffffffff"],
    [->(a) { a.mov_imm RCX, -2 }, "mov rcx, -0x2"],
    [->(a) { a.mov_imm RDX, 1 << 63 }, "movabs rdx, -0x8000000000000000"],
    [->(a) { a.ld RAX, [RSP, 8] }, "mov rax, qword ptr [rsp + 0x8]"],
    [->(a) { a.ld R13, [R13, 0] }, "mov r13, qword ptr [r13]"],
    [->(a) { a.ld RAX.w, [RBP, -16] }, "mov eax, dword ptr [rbp - 0x10]"],
    [->(a) { a.ld RDI.b, [R12, 300] }, "movzx edi, byte ptr [r12 + 0x12c]"],
    [->(a) { a.store [RSP, 0], R15 }, "mov qword ptr [rsp], r15"],
    [->(a) { a.store [RBX, 4], RSI.w }, "mov dword ptr [rbx + 0x4], esi"],
    [->(a) { a.store [RAX, 1], RDI.b }, "mov byte ptr [rax + 0x1], dil"],
    [->(a) { a.lea RAX, [RSP, 4096] }, "lea rax, [rsp + 0x1000]"],
    [->(a) { a.movsxd_load RAX, [RCX, 0, RAX, 4] }, "movsxd rax, dword ptr [rcx + 4*rax]"],
    [->(a) { a.movzx8 RAX.w, RSI.b }, "movzx eax, sil"],
    [->(a) { a.movsx8 RAX, RCX.b }, "movsx rax, cl"],
    [->(a) { a.movsxd RAX, R8.w }, "movsxd rax, r8d"],
    [->(a) { a.add RAX, RCX }, "add rax, rcx"],
    [->(a) { a.sub RAX.w, 1 }, "sub eax, 0x1"],
    [->(a) { a.and R10, -2 }, "and r10, -0x2"],
    [->(a) { a.or RAX, 0x1000 }, "or rax, 0x1000"],
    [->(a) { a.xor RAX.w, 63 }, "xor eax, 0x3f"],
    [->(a) { a.cmp RDI, 0x24 }, "cmp rdi, 0x24"],
    [->(a) { a.cmp R14.w, R15.w }, "cmp r14d, r15d"],
    [->(a) { a.and RAX.b, RCX.b }, "and al, cl"],
    [->(a) { a.or RAX.b, RCX.b }, "or al, cl"],
    [->(a) { a.tst RAX, RAX }, "test rax, rax"],
    [->(a) { a.tst RBX, 0x100 }, "test rbx, 0x100"],
    [->(a) { a.imul RAX, RCX }, "imul rax, rcx"],
    [->(a) { a.imul RAX.w, RAX.w, 10 }, "imul eax, eax, 0xa"],
    [->(a) { a.shl RAX, :cl }, "shl rax, cl"],
    [->(a) { a.sar R9.w, 3 }, "sar r9d, 0x3"],
    [->(a) { a.shr RAX, 63 }, "shr rax, 0x3f"],
    [->(a) { a.neg RAX }, "neg rax"],
    [->(a) { a.div RCX }, "div rcx"],
    [->(a) { a.idiv RCX.w }, "idiv ecx"],
    [->(a) { a.sign_extend_rax(true) }, "cqo"],
    [->(a) { a.sign_extend_rax(false) }, "cdq"],
    [->(a) { a.bt RBX, 5 }, "bt rbx, 0x5"],
    [->(a) { a.btc RAX, 63 }, "btc rax, 0x3f"],
    [->(a) { a.btr RAX, 63 }, "btr rax, 0x3f"],
    [->(a) { a.bsf RAX, RCX }, "bsf rax, rcx"],
    [->(a) { a.bsr RAX.w, RCX.w }, "bsr eax, ecx"],
    [->(a) { a.popcnt RAX, R12 }, "popcnt rax, r12"],
    [->(a) { a.bswap RAX }, "bswap rax"],
    [->(a) { a.bswap R9.w }, "bswap r9d"],
    [->(a) { a.cmov :e, RAX, RDX }, "cmove rax, rdx"],
    [->(a) { a.set :ne, RSI }, "setne sil"],
    [->(a) { a.set :o, RCX }, "seto cl"],
    [->(a) { a.call_reg R11 }, "call r11"],
    [->(a) { a.jmp_reg RAX }, "jmp rax"],
    [->(a) { a.push RBP }, "push rbp"],
    [->(a) { a.pop R12 }, "pop r12"],
    [->(a) { a.ret }, "ret"],
    [->(a) { a.movq XMM0, RAX }, "movq xmm0, rax"],
    [->(a) { a.movq RCX, XMM1 }, "movq rcx, xmm1"],
    [->(a) { a.addsd XMM0, XMM1 }, "addsd xmm0, xmm1"],
    [->(a) { a.divsd XMM0, XMM1 }, "divsd xmm0, xmm1"],
    [->(a) { a.sqrtsd XMM0, XMM0 }, "sqrtsd xmm0, xmm0"],
    [->(a) { a.ucomisd XMM1, XMM0 }, "ucomisd xmm1, xmm0"],
    [->(a) { a.cvtsi2sd XMM0, RAX }, "cvtsi2sd xmm0, rax"],
    [->(a) { a.cvtsi2sd XMM0, RAX.w }, "cvtsi2sd xmm0, eax"],
    [->(a) { a.cvttsd2si RAX, XMM0 }, "cvttsd2si rax, xmm0"],
    [->(a) { a.roundsd XMM0, XMM0, 9 }, "roundsd xmm0, xmm0, 0x9"],
    [->(a) { a.movsd_store [R10, 72], XMM7 }, "movsd qword ptr [r10 + 0x48], xmm7"],
    [->(a) { a.stmxcsr [RDI, 64] }, "stmxcsr dword ptr [rdi + 0x40]"],
    [->(a) { a.ldmxcsr [RSI, 64] }, "ldmxcsr dword ptr [rsi + 0x40]"],
    [->(a) { a.fnstcw [RDI, 68] }, "fnstcw word ptr [rdi + 0x44]"],
    [->(a) { a.fldcw [RSI, 68] }, "fldcw word ptr [rsi + 0x44]"]
  ].freeze

  def objdump
    @objdump ||= ["/opt/homebrew/opt/llvm/bin/llvm-objdump", "llvm-objdump", "objdump"].find do |tool|
      _, status = Open3.capture2e(tool, "--version")
      status.success?
    rescue SystemCallError
      false
    end
  end

  # The disassembly of `code`, one instruction a line.
  def disassemble(code)
    skip "no objdump" unless objdump
    unit = Zr::Obj::Unit.new
    unit.functions << Zr::Obj::Code.new("forms", code)
    Dir.mktmpdir("zr-x86-") do |dir|
      obj = File.join(dir, "forms.o")
      File.binwrite(obj, Zr::Obj::Elf::ObjectFile.write(unit, arch: :x86_64))
      out, status = Open3.capture2e(objdump, "-d", "--x86-asm-syntax=intel", "--no-show-raw-insn", "--no-leading-addr", obj)
      skip "#{objdump} reads no x86-64: #{out.lines.first}" unless status.success?
      out.lines.map(&:strip).grep(/\A[a-z]/).reject { |l| l.end_with?(":") || l.start_with?("file format") || l.include?("file format") }
    end
  end

  def test_every_form_disassembles_as_written
    a = Asm.new
    FORMS.each { |emit, _| emit.call(a) }
    assert_equal FORMS.map(&:last), disassemble(a.to_binary).map { |l| l.gsub(/\s+/, " ") }
  end

  def test_a_branch_reaches_its_label_in_either_direction
    a = Asm.new
    top = a.make_label("top")
    out = a.make_label("out")
    a.put_label top
    a.j :ne, out
    a.jmp top
    a.put_label out
    a.ret
    code = a.to_binary
    # jne rel32 is 6 bytes, jmp rel32 is 5: out is at 11.
    assert_equal [0x0F, 0x85, 5, 0, 0, 0], code.bytes[0, 6]
    assert_equal [0xE9, *[-11].pack("l<").bytes], code.bytes[6, 5]
  end

  def test_a_symbol_form_gives_the_offset_of_its_displacement
    a = Asm.new
    at = []
    a.mov RAX, RCX
    a.lea_rip(RDX) { |o| at << o }
    a.call_rel { |o| at << o }
    # mov is 3 bytes; lea rdx, [rip] is REX, 8D, ModRM, then disp32.
    assert_equal [6, 11], at
    assert_equal 15, a.size
  end

  def test_a_jump_table_word_is_the_distance_from_the_table
    a = Asm.new
    table = a.make_label("table")
    there = a.make_label("there")
    a.put_label table
    a.table_word there, table
    a.ret
    a.put_label there
    a.ret
    assert_equal [5].pack("l<").bytes, a.to_binary.bytes[0, 4]
  end
end
