# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/obj/model"
require_relative "../../lib/zr/obj/macho/block"

# A branch reaches 128 MB. A program's code sits after the runtime's,
# and with eval support the runtime's code is about 136 MB, so a call
# from the program can be too far from the runtime function it calls.
# The link then calls an island at the end of the program's code, which
# jumps to the function from anywhere (lib/zr/obj/macho/block.rb).
class MachOIslandsTest < Minitest::Test
  Block = Zr::Obj::MachO::Block

  BASE = 0x1_0000_0000
  CODE = BASE + (200 << 20)
  FAR = BASE + 0x1000
  NEAR = CODE - (1 << 20)

  # `nop; bl far; bl near; bl far; ret`
  def block(calls = { 4 => "far", 8 => "near", 12 => "far" })
    code = [0xD503_201F, 0x9400_0000, 0x9400_0000, 0x9400_0000, 0xD65F_03C0].pack("L<5")
    unit = Zr::Obj::Unit.new.function("main", code, relocs: calls.map { |at, name| Zr::Obj::Reloc.new(at, :branch26, name) })
    outside = { "_far" => FAR, "_near" => NEAR }
    Block.new([Zr::Obj::MachO::ObjectFile.of(unit)], outside: ->(name) { outside[name] })
  end

  # Places every part from CODE on, as the image places a program.
  def placed(block)
    Block::PARTS.inject(CODE) { |at, part| block.place(part, at) + block.size(part) }
    block.addresses!
    block
  end

  def words(block) = block.bytes(:text).unpack("L<*")

  def branch_target(word, place)
    offset = word & 0x3FF_FFFF
    offset -= 1 << 26 if offset >= 1 << 25
    place + (offset << 2)
  end

  # The address that an island's `adrp x16; add x16, x16` puts in x16.
  def island_target(adrp, add, place)
    page = (((adrp >> 5) & 0x7FFFF) << 2) | ((adrp >> 29) & 3)
    page -= 1 << 21 if page >= 1 << 20
    (place & ~0xFFF) + (page << 12) + ((add >> 10) & 0xFFF)
  end

  def test_a_call_out_of_reach_goes_through_an_island_that_jumps_to_its_target
    text = words(placed(block))

    island = CODE + 20
    assert_equal 5 + 3, text.size, "one island of three words after the code"
    assert_equal [island, NEAR, island], [4, 8, 12].map { |at| branch_target(text[at / 4], CODE + at) }
    assert_equal FAR, island_target(text[5], text[6], island)
    assert_equal 0xD61F_0200, text[7], "the island ends in br x16"
  end

  def test_two_calls_to_one_target_share_its_island
    b = placed(block)

    assert_equal 20 + Block::ISLAND, b.size(:text)
  end

  def test_calls_within_reach_have_no_island
    b = placed(block({ 8 => "near" }))

    assert_equal 20, b.size(:text)
    assert_equal NEAR, branch_target(words(b)[2], CODE + 8)
  end

  # A program near the runtime's code needs no island.
  def test_a_program_close_to_its_target_has_no_island
    b = block({ 4 => "far", 12 => "far" })
    Block::PARTS.inject(FAR + (1 << 20)) { |at, part| b.place(part, at) + b.size(part) }

    assert_equal 20, b.size(:text)
  end
end
