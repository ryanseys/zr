# frozen_string_literal: true

require "test_helper"
require "digest"
require_relative "../../tool/lib/zr/dev"

# Some core files are ports of a Ruby file of CRuby that zr cannot load as
# it is. Each says which one, with that file's SHA-256 at RUBY_REVISION:
#
#   # zr port: follows <path> of ruby at RUBY_REVISION (sha256 <hex>)
#
# When the pin moves and the file changes, this test names the port to
# bring up to date. It reads the file from the CRuby checkout (RUBY_SRC).
class CorePortsTest < Minitest::Test
  CORE = File.join(ROOT, "lib/zr/runtime/core")
  HEADER = /^\s*# zr port: follows (\S+) of ruby at RUBY_REVISION \(sha256 (\h{64})\)$/

  # The ports that must carry a header.
  PORTS = { "pathname.rb" => "pathname_builtin.rb", "set.rb" => "lib/set/subclass_compatible.rb" }.freeze

  def test_each_port_names_the_file_that_it_follows
    PORTS.each do |port, upstream|
      assert_includes headers.fetch(port, []).map(&:first), upstream, port
    end
  end

  def test_each_port_follows_its_file_at_the_pinned_revision
    skip "no CRuby checkout (RUBY_SRC)" unless Zr::Dev.ruby_src?

    headers.each do |port, rows|
      rows.each do |upstream, digest|
        assert_equal digest, Digest::SHA256.hexdigest(Zr::Dev.cruby(upstream)), "#{port}: #{upstream} changed; bring the port up to date"
      end
    end
  end

  private

  # `{ core file => [[upstream path, sha256]…] }`.
  def headers
    @headers ||= Dir[File.join(CORE, "**/*.rb")].to_h do |file|
      [file.delete_prefix("#{CORE}/"), File.read(file).scan(HEADER)]
    end.reject { |_, rows| rows.empty? }
  end
end
