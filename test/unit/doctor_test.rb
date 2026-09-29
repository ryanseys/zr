# frozen_string_literal: true

require "test_helper"
require "open3"
require_relative "../../lib/zr/doctor"

# `zr doctor` checks what zr needs on this host (lib/zr/doctor.rb), and
# `zr version`, `zr cache` and `zr run --emit wasm` tell the user where
# they stand.
class DoctorTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")

  def test_another_ruby_fails
    check = Zr::Doctor.ruby("4.1.0")

    assert_equal :fail, check.status
    assert_equal "4.1.0; zr needs #{Zr::RUBY} or a later 4.0 release", check.detail
  end

  def test_a_later_patch_release_warns
    check = Zr::Doctor.ruby("4.0.9")

    assert_equal :warn, check.status
    assert_equal "4.0.9; zr is tested with #{Zr::RUBY}", check.detail
  end

  def test_the_pinned_ruby_is_ok
    assert_equal :ok, Zr::Doctor.ruby(Zr::RUBY).status
  end

  def test_a_host_that_cannot_run_its_binaries_warns
    check = Zr::Doctor.host("x86_64-linux")

    assert_equal :warn, check.status
    assert_includes check.detail, "--emit wasm"
  end

  def test_no_wasmtime_warns
    assert_equal :warn, Zr::Doctor.wasmtime(nil).status
  end

  def test_a_failed_check_makes_the_run_fail
    failing = Zr::Doctor::Check.new(:fail, "ruby", "4.0.8")
    out = StringIO.new
    was = Zr::Doctor.method(:checks)
    Zr::Doctor.define_singleton_method(:checks) { [failing] }

    refute Zr::Doctor.run(out)
    assert_equal "fail  ruby               4.0.8\n", out.string
  ensure
    Zr::Doctor.define_singleton_method(:checks, was)
  end

  def zr(*args, env: {})
    # rubygems requires BUNDLER_SETUP at boot, so a bundle leaks through it too.
    unbundled = { "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLER_SETUP" => nil, "BUNDLE_BIN_PATH" => nil, "BUNDLER_VERSION" => nil }
    Open3.capture3(unbundled.merge("ZR_COMPILED" => "0").merge(env), RbConfig.ruby, EXE, *args, chdir: ROOT)
  end

  def test_version_names_the_pinned_ruby
    out, _, status = zr("version")

    assert_predicate status, :success?
    assert_equal "zr #{Zr::VERSION} (ruby #{Zr::RUBY})\n", out
  end

  def test_cache_prints_its_path
    Dir.mktmpdir("zr-cache-") do |dir|
      out, _, status = zr("cache", env: { "ZR_CACHE" => dir })

      assert_predicate status, :success?
      assert_equal "#{dir}\n", out
    end
  end

  def test_run_emit_wasm_without_wasmtime_stops_before_the_build
    Dir.mktmpdir("zr-no-wasmtime-") do |dir|
      program = File.join(dir, "app.rb")
      File.write(program, "p 1\n")

      _, err, status = zr("run", "--emit", "wasm", program, env: { "PATH" => dir })

      assert_equal 1, status.exitstatus
      assert_includes err, "wasmtime is not installed"
    end
  end
end
