# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/shipped"

# A platform gem ships a compiled compiler with a manifest that gives the
# content digest of its sources. The binary runs only while the sources
# still have that digest. Here the manifest is in a temporary directory,
# and nothing under the root changes.
class ShippedTest < Minitest::Test
  Shipped = Zr::Shipped
  FILES = [File.join(ROOT, "exe/zr"), File.join(ROOT, "lib/zr/version.rb")].freeze

  def test_a_platform_matches_only_an_aarch64_host_of_its_os
    refute Shipped.host?("x86_64-linux")
    skip "not an arm64 Mac" unless RUBY_PLATFORM.start_with?("arm64-darwin")

    assert Shipped.host?("arm64-darwin")
    refute Shipped.host?("aarch64-linux-gnu")
  end

  # The digest names each file by its path below the root, so the same
  # tree in another place gives the same digest. A file outside the root
  # is not part of it.
  def test_the_digest_leaves_out_files_outside_the_root
    Dir.mktmpdir("zr-shipped-") do |dir|
      outside = File.join(dir, "library.rb")
      File.write(outside, "1\n")

      assert_equal Shipped.digest(FILES), Shipped.digest(FILES + [outside])
      refute_equal Shipped.digest(FILES), Shipped.digest(FILES.take(1))
    end
  end

  def test_a_matching_digest_is_current_and_later_only_the_stamps_are_compared
    with_manifest(Shipped.manifest(FILES, "arm64-darwin")) do
      assert Shipped.current?(FILES, :stamps)
      stub_method(Shipped, :digest, ->(_) { raise "the digest is read again" }) do
        assert Shipped.current?(FILES, :stamps)
      end
    end
  end

  def test_a_different_digest_or_version_is_not_current
    with_manifest(Shipped.manifest(FILES.take(1), "arm64-darwin")) { refute Shipped.current?(FILES, :stamps) }
    with_manifest(Shipped.manifest(FILES, "arm64-darwin").sub(/^version .*/, "version 0.0.0")) do
      refute Shipped.current?(FILES, :stamps)
    end
  end

  private

  # Runs the block with `text` as the manifest of a shipped binary, and
  # an empty verified cache.
  def with_manifest(text)
    Dir.mktmpdir("zr-shipped-") do |dir|
      manifest = File.join(dir, "zr.manifest")
      binary = File.join(dir, "zr")
      File.write(manifest, text)
      File.write(binary, "")
      File.chmod(0o755, binary)
      stub_method(Shipped, :manifest_path, manifest) do
        stub_method(Shipped, :binary, binary) do
          stub_method(Shipped, :verified_path, File.join(dir, "cache", "verified.marshal")) { yield }
        end
      end
    end
  end
end
