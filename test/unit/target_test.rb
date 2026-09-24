# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"

# The targets zr builds for. Every built form hangs off a runtime's
# digest, so two targets must never share one: a cache that mixed them
# would hand one target's object to another.
class TargetTest < Minitest::Test
  def test_every_target_is_found_by_its_triple
    Zr::Target.all.each { |target| assert_same target, Zr::Target.fetch(target.triple) }
    assert_nil Zr::Target.fetch("sparc-sun-solaris")
  end

  def test_two_targets_never_share_a_digest
    digests = Zr::Target.all.map { |target| Zr::Runtime.allocate.tap { |rt| rt.instance_variable_set(:@target, target) }.digest }
    assert_equal digests.uniq.size, digests.size
  end

  def test_the_default_is_the_host_or_darwin
    assert_equal Zr::Target.host || Zr::Target::AARCH64_DARWIN, Zr::Target.default
  end

  def test_a_road_the_target_lacks_is_refused_by_name
    assert_match(/does not build a native binary for wasm32-wasi/, Zr::Target::WASM32_WASI.refusal(nil))
    assert_match(/does not build --emit obj for wasm32-wasi/, Zr::Target::WASM32_WASI.refusal("obj"))
    assert_nil Zr::Target::WASM32_WASI.refusal("wasm")
  end

  # A cross toolchain answers for a target off its host by the triple's
  # name; the host's own answers only for the host's target.
  def test_a_tool_is_the_host_s_or_a_cross_toolchain_s
    Zr::Target.all.each do |target|
      tool = target.tool("cc") or next
      assert(target.native? ? tool == "cc" : tool.start_with?("#{target.triple}-"), "#{target.triple}: #{tool}")
    end
  end

  # zr's own linker writes a Mach-O binary, so every host builds one; an
  # ELF binary needs the target's own cc.
  def test_a_darwin_binary_needs_no_toolchain
    darwin = Zr::Target::AARCH64_DARWIN
    assert_nil darwin.refusal("obj")
    assert_nil darwin.refusal(nil) unless ENV["ZR_LINKER"] == "cc"
  end
end
