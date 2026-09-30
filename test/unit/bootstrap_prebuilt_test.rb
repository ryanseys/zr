# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/bootstrap/prebuilt"

# A platform gem ships a compiled compiler with a manifest that gives the
# content digest of its sources. The binary runs only while the sources
# still have that digest. Here the manifest is in a temporary directory,
# and nothing under the root changes.
class BootstrapPrebuiltTest < Minitest::Test
  Prebuilt = Zr::Bootstrap::Prebuilt
  FILES = [File.join(ROOT, "exe/zr"), File.join(ROOT, "lib/zr/version.rb")].freeze

  def test_a_platform_matches_only_an_aarch64_host_of_its_os
    refute Prebuilt.host?("x86_64-linux")
    skip "not an arm64 Mac" unless RUBY_PLATFORM.start_with?("arm64-darwin")

    assert Prebuilt.host?("arm64-darwin")
    refute Prebuilt.host?("aarch64-linux-gnu")
  end

  # The digest names each file by its path below the root, so the same
  # tree in another place gives the same digest. A file outside the root
  # is not part of it.
  def test_the_digest_leaves_out_files_outside_the_root
    Dir.mktmpdir("zr-shipped-") do |dir|
      outside = File.join(dir, "library.rb")
      File.write(outside, "1\n")

      assert_equal Prebuilt.digest(FILES), Prebuilt.digest(FILES + [outside])
      refute_equal Prebuilt.digest(FILES), Prebuilt.digest(FILES.take(1))
    end
  end

  def test_a_matching_digest_is_current_and_later_only_the_stamps_are_compared
    with_manifest(Prebuilt.manifest(FILES, "arm64-darwin")) do
      assert Prebuilt.current?(FILES, :stamps)
      stub_method(Prebuilt, :digest, ->(_) { raise "the digest is read again" }) do
        assert Prebuilt.current?(FILES, :stamps)
      end
    end
  end

  def test_a_different_digest_or_version_is_not_current
    with_manifest(Prebuilt.manifest(FILES.take(1), "arm64-darwin")) { refute Prebuilt.current?(FILES, :stamps) }
    with_manifest(Prebuilt.manifest(FILES, "arm64-darwin").sub(/^version .*/, "version 0.0.0")) do
      refute Prebuilt.current?(FILES, :stamps)
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
      stub_method(Prebuilt, :manifest_path, manifest) do
        stub_method(Prebuilt, :binary, binary) do
          stub_method(Prebuilt, :verified_path, File.join(dir, "cache", "verified.marshal")) { yield }
        end
      end
    end
  end
end
