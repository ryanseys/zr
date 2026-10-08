# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# websocket-driver's C extension, which masks a frame's payload, in a zr
# binary two ways: as the bundle that this ruby's install of the gem built
# (the install kept no objects), and as zr builds it from the gem's
# extconf.rb when the build gives it arguments (`ZR_EXT_CONFIG`).
class CExtWebsocketDriverTest < Minitest::Test
  PROGRAM = <<~RUBY
    require "websocket_mask"
    mask = [1, 2, 3, 4].pack("C*")
    [+"", "a", "hello", "x" * 1000].each do |payload|
      masked = WebSocket::Mask.mask(payload.b, mask)
      p [masked.bytesize, masked.unpack1("H*")[0, 24], masked.encoding, WebSocket::Mask.mask(masked, mask) == payload.b]
    end
    p WebSocket::Mask.mask("abc".b, nil)
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @version = Zr::Test::CExt.installed("websocket-driver")
    skip "websocket-driver is not installed in this ruby" unless @version
  end

  def test_the_installed_bundle_runs_as_in_ruby
    assert_same_as_ruby({})
  end

  def test_the_extension_that_zr_builds_runs_as_in_ruby
    assert_same_as_ruby({ "ZR_EXT_CONFIG" => "websocket-driver=--with-websocket_mask-dir=#{Zr::Test::CExt::DIR}/none" })
  end

  def assert_same_as_ruby(build_env)
    ruby, (zr,) = Zr::Test::CExt.gem_outputs("websocket-driver", @version, PROGRAM, [{}], build_env: build_env)
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
  end
end
