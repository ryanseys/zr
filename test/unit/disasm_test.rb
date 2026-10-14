# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/backend/aarch64/listing"
require_relative "../native/ops"

# Keeps the instruction selection of the backend in a snapshot. One
# function per opcode compiles to a listing of the instructions that
# `Backend::Aarch64::Codegen` selects and the relocations that it records.
# A change in instruction selection then shows as a diff, not as a
# program with different output for an unknown reason.
#
# `ZR_BLESS=1 ruby -Ilib -Itest test/unit/disasm_test.rb` rewrites it.
class DisasmTest < Minitest::Test
  SNAPSHOT = File.join(ROOT, "test/native/disasm.txt")
  # The symbols in the fixtures that this link defines. `elsewhere` is an
  # import, so the listing shows the difference between the two kinds.
  DEFINED = %w[other here].freeze

  def render
    Zr::Native::Ops.all.map do |name, f|
      "# #{name}\n#{Zr::Backend::Aarch64::Listing.of(f, defined: DEFINED)}\n"
    end.join("\n")
  end

  def test_every_opcode_lowers_as_it_did
    text = render
    if Checks.bless?
      File.write(SNAPSHOT, text)
      skip "blessed #{SNAPSHOT}"
    end
    assert_equal File.read(SNAPSHOT), text, "run with ZR_BLESS=1 to record"
  end

  # If the snapshot does not cover all of the backend, it can become
  # stale with no failure.
  def test_the_snapshot_covers_every_opcode
    lowered = Zr::Native::Ops.all.values.flat_map { |f| f.blocks.flat_map { |b| b.insts.map(&:op) } }.uniq
    missing = (Zr::IR::Inst::BINOPS + Zr::IR::Inst::BITOPS + Zr::IR::Inst::FBINOPS + Zr::IR::Inst::FUNOPS +
      Zr::IR::Inst::CONVERSIONS + Zr::IR::Inst::PAIRS +
      %i[iconst load store stack_addr symbol_value func_addr call call_indirect
         icmp fcmp select ireduce uextend sextend jump brif switch return]) - lowered
    assert_empty missing, "opcodes no fixture reaches"
  end
end
