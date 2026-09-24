# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/backend/aarch64/listing"
require_relative "../native/ops"

# What the backend picks, pinned. One function per opcode compiles to a
# listing of the instructions `Backend::Aarch64::Codegen` chose and the relocations it
# recorded, and the whole set is one snapshot. A change in instruction
# selection then arrives as a diff to read rather than as a corpus
# program that answers differently for a reason nobody can see.
#
# `ZR_BLESS=1 ruby -Ilib -Itest test/unit/disasm_test.rb` rewrites it.
class DisasmTest < Minitest::Test
  SNAPSHOT = File.join(ROOT, "test/native/disasm.txt")
  # The symbols the fixtures name that this link defines; `elsewhere` is
  # the import, so an import and a local symbol can be told apart.
  DEFINED = %w[other here].freeze

  def render
    Zr::Native::Ops.all.map do |name, f|
      "# #{name}\n#{Zr::Backend::Aarch64::Listing.of(f, defined: DEFINED)}\n"
    end.join("\n")
  end

  def test_every_opcode_lowers_as_it_did
    text = render
    if ENV["ZR_BLESS"] == "1"
      File.write(SNAPSHOT, text)
      skip "blessed #{SNAPSHOT}"
    end
    assert_equal File.read(SNAPSHOT), text, "run with ZR_BLESS=1 to record"
  end

  # A snapshot that covers less than the backend does is a snapshot that
  # can go stale without saying so.
  def test_the_snapshot_covers_every_opcode
    lowered = Zr::Native::Ops.all.values.flat_map { |f| f.blocks.flat_map { |b| b.insts.map(&:op) } }.uniq
    missing = (Zr::IR::Inst::BINOPS + Zr::IR::Inst::BITOPS + Zr::IR::Inst::FBINOPS + Zr::IR::Inst::FUNOPS +
      Zr::IR::Inst::CONVERSIONS + Zr::IR::Inst::PAIRS +
      %i[iconst load store stack_addr symbol_value func_addr call call_indirect
         icmp fcmp select ireduce uextend sextend jump brif return]) - lowered
    assert_empty missing, "opcodes no fixture reaches"
  end
end
