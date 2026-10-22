# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/backend/aarch64"
require_relative "../../lib/zr/backend/x86_64"

# A slot's address plus a constant compiles on each backend, whatever the
# constant. The planner makes the sum one address from sp only where the
# backend reaches it (`frame_reach?`): two `add`s from sp reach 16 MiB on
# arm64, and `lea` reaches a signed 32-bit offset on x86-64. Past that,
# the sum is a plain addition.
class FrameReachTest < Minitest::Test
  CONSTANTS = [1 << 28, -64, 1 << 40, -(1 << 40)].freeze
  BACKENDS = [Zr::Backend::Aarch64::Codegen, Zr::Backend::X86_64::Codegen].freeze

  def slot_plus(k)
    f = Zr::IR::Function.new("slot_plus", [], "i64")
    f.ret(f.iadd(f.stack_addr(f.slot(8)), f.iconst("i64", k)))
    f
  end

  def test_a_slot_address_plus_any_constant_compiles
    BACKENDS.each do |backend|
      CONSTANTS.each do |k|
        code = backend.new(slot_plus(k)).compile

        refute_empty code.bytes, "#{backend} with #{k}"
      end
    end
  end
end
