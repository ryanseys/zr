# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/zr"

# The targets ze0 builds for. Every built form hangs off a runtime's
# digest, so two targets must never share one: a cache that mixed them
# would hand one target's object to another.
class TargetTest < Minitest::Test
  def test_every_target_is_found_by_its_triple
    Ze0::Target.all.each { |target| assert_same target, Ze0::Target.fetch(target.triple) }
    assert_nil Ze0::Target.fetch("sparc-sun-solaris")
  end

  def test_two_targets_never_share_a_digest
    digests = Ze0::Target.all.map { |target| Ze0::Zr::Runtime.allocate.tap { |rt| rt.instance_variable_set(:@target, target) }.digest }
    assert_equal digests.uniq.size, digests.size
  end

  def test_the_default_is_the_host_or_darwin
    assert_equal Ze0::Target.host || Ze0::Target::AARCH64_DARWIN, Ze0::Target.default
  end

  def test_a_road_the_target_lacks_is_refused_by_name
    assert_match(/does not build a native binary for wasm32-wasi/, Ze0::Target::WASM32_WASI.refusal(nil))
    assert_match(/does not build --emit obj for wasm32-wasi/, Ze0::Target::WASM32_WASI.refusal("obj"))
    assert_nil Ze0::Target::WASM32_WASI.refusal("wasm")
  end

  # A cross toolchain answers for a target off its host by the triple's
  # name; the host's own answers only for the host's target.
  def test_a_tool_is_the_host_s_or_a_cross_toolchain_s
    Ze0::Target.all.each do |target|
      tool = target.tool("cc") or next
      assert(target.native? ? tool == "cc" : tool.start_with?("#{target.triple}-"), "#{target.triple}: #{tool}")
    end
  end

  def test_a_native_binary_is_refused_off_its_host
    darwin = Ze0::Target::AARCH64_DARWIN
    if darwin.native?
      assert_nil darwin.refusal("obj")
    else
      assert_match(/needs a aarch64-apple-darwin host/, darwin.refusal(nil))
    end
  end
end
