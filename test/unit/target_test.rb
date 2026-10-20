# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/runtime"

# The targets that zr builds for. Every built form depends on the digest
# of a runtime, so two targets must never have the same digest. A cache
# that mixed them would give the object of one target to another.
class TargetTest < Minitest::Test
  def test_every_target_is_found_by_its_triple
    Zr::Target.all.each { |target| assert_same target, Zr::Target.fetch(target.triple) }
    assert_nil Zr::Target.fetch("sparc-sun-solaris")
  end

  def test_two_targets_never_share_a_digest
    digests = Zr::Target.all.map { |target| Zr::Runtime.allocate.tap { |rt| rt.instance_variable_set(:@target, target) }.digest }
    assert_equal digests.uniq.size, digests.size
  end

  # Each target says how far CI checks it, and only WASI takes no C
  # extension.
  def test_each_target_has_a_support_level
    assert_equal Zr::Target.all.map(&:triple).sort, Zr::Target::SUPPORT.keys.sort
    assert_equal [Zr::Target::WASM32_WASI], Zr::Target.all.reject(&:native_ext?)
  end

  # An x86_64 ruby that Rosetta runs on an Apple Silicon Mac is on an
  # aarch64 host; one on an Intel Mac is not.
  def test_rosetta_runs_on_an_aarch64_host
    config = RbConfig::CONFIG.merge("host_cpu" => "x86_64", "host_os" => "darwin23")
    stub_const_config(config) do
      stub_method(Zr::Target, :rosetta?, true) { assert_equal "aarch64-apple-darwin", Zr::Target.host_triple }
      stub_method(Zr::Target, :rosetta?, false) { assert_equal "x86_64-apple-darwin", Zr::Target.host_triple }
    end
  end

  # A glibc host is the gnu target whether ruby names its libc or not,
  # so it never falls to the musl target that also runs there.
  def test_a_glibc_host_is_the_gnu_target
    { "linux" => "x86_64-linux-gnu", "linux-gnu" => "x86_64-linux-gnu", "linux-musl" => "x86_64-linux-musl" }.each do |os, triple|
      stub_const_config(RbConfig::CONFIG.merge("host_cpu" => "x86_64", "host_os" => os)) do
        assert_equal triple, Zr::Target.host_triple, os
        assert_equal triple, Zr::Target.host.triple, os
      end
    end
  end

  def test_the_default_is_the_host_or_darwin
    assert_equal Zr::Target.host || Zr::Target::AARCH64_DARWIN, Zr::Target.default
  end

  def test_refusal_gives_the_unsupported_output_kind
    assert_match(/does not build a native binary for wasm32-wasi/, Zr::Target::WASM32_WASI.refusal(nil))
    assert_match(/does not build --emit obj for wasm32-wasi/, Zr::Target::WASM32_WASI.refusal("obj"))
    assert_nil Zr::Target::WASM32_WASI.refusal("wasm")
  end

  # A target that is not the host uses a cross toolchain, found by the
  # triple. The host's own tool is used only for the host's target.
  def test_a_tool_is_the_host_s_or_a_cross_toolchain_s
    Zr::Target.all.each do |target|
      tool = target.tool("cc") or next
      next if target.musl_on_linux?

      assert(target.native? ? tool == "cc" : tool.start_with?("#{target.triple}-"), "#{target.triple}: #{tool}")
    end
  end

  # zr's own linker writes a Mach-O binary, so every host can build one.
  # An ELF binary needs the target's own cc.
  def test_a_darwin_binary_needs_no_toolchain
    darwin = Zr::Target::AARCH64_DARWIN
    assert_nil darwin.refusal("obj")
    assert_nil darwin.refusal(nil) unless ENV["ZR_LINKER"] == "cc"
  end

  # A glibc host builds its own dynamic target by default. A static musl
  # binary runs on any Linux of the same machine, so it runs there too.
  def test_a_glibc_host_builds_its_own_target_and_runs_the_musl_one
    Checks.with_host("aarch64-linux-gnu") do
      gnu = Zr::Target::AARCH64_LINUX_GNU
      musl = Zr::Target::AARCH64_LINUX_MUSL
      assert_same gnu, Zr::Target.host
      assert_same gnu, Zr::Target.default
      assert_predicate gnu, :native?
      assert_predicate musl, :runs_here?
      refute_predicate musl, :native?
      refute_predicate Zr::Target::AARCH64_DARWIN, :runs_here?
    end
    Checks.with_host("x86_64-linux-gnu") do
      assert_same Zr::Target::X86_64_LINUX_GNU, Zr::Target.host
      assert_predicate Zr::Target::X86_64_LINUX_MUSL, :runs_here?
      refute_predicate Zr::Target::AARCH64_LINUX_MUSL, :runs_here?
    end
  end

  # ruby names a glibc platform with no C library.
  def test_a_glibc_target_s_platform_has_no_libc
    assert_equal "x86_64-linux", Zr::Target::X86_64_LINUX_GNU.ruby_platform
    assert_equal "aarch64-linux", Zr::Target::AARCH64_LINUX_GNU.ruby_platform
    assert_equal :dynamic, Zr::Target::X86_64_LINUX_GNU.link
  end

  # There, musl's wrapper links, or the compiler that CC names.
  def test_a_glibc_host_links_musl_with_cc_or_musl_gcc
    Checks.with_host("aarch64-linux-gnu") do
      musl = Zr::Target::AARCH64_LINUX_MUSL
      old = ENV.fetch("CC", nil)
      ENV["CC"] = RbConfig.ruby
      assert_equal RbConfig.ruby, musl.tool("cc")
      ENV["CC"] = "/no/such/cc"
      assert_includes [nil, "aarch64-linux-musl-cc", "aarch64-linux-musl-gcc", "musl-gcc"], musl.tool("cc")
    ensure
      ENV["CC"] = old
    end
  end

  # The hint for a missing cc names the host's own package.
  def test_the_cc_hint_follows_the_host
    Dir.mktmpdir do |dir|
      release = File.join(dir, "os-release")
      Checks.with_host("aarch64-linux-gnu") do
        File.write(release, %(NAME="Alpine Linux"\nID=alpine\n))
        assert_equal "apk add build-base", Zr::Target.cc_hint(os_release: release)
        File.write(release, %(NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\n))
        assert_equal "apt install musl-tools", Zr::Target.cc_hint(os_release: release)
        assert_equal "apt install build-essential", Zr::Target.cc_hint(os_release: release, libc: :glibc)
        assert_match(/musl-gcc/, Zr::Target.cc_hint(os_release: File.join(dir, "none")))
      end
      Checks.with_host("aarch64-apple-darwin") do
        assert_equal "xcode-select --install", Zr::Target.cc_hint(os_release: release)
      end
    end
  end

  # A platform gem's name is the one that RubyGems reports for the host:
  # `arm64-darwin`, never `aarch64-darwin`, and a Linux one keeps its libc.
  def test_each_host_target_names_the_gem_platform_that_rubygems_picks
    names = Zr::Target.all.to_h { |target| [target.triple, target.gem_platform] }

    assert_equal({ "aarch64-apple-darwin" => "arm64-darwin", "aarch64-linux-musl" => "aarch64-linux-musl",
                   "x86_64-linux-musl" => "x86_64-linux-musl", "x86_64-linux-gnu" => "x86_64-linux-gnu",
                   "aarch64-linux-gnu" => "aarch64-linux-gnu", "wasm32-wasi" => nil }, names)
    assert_operator(Gem::Platform.new("arm64-darwin"), :===, Gem::Platform.new("arm64-darwin-27"), "an Apple-silicon host picks it")
    refute_operator(Gem::Platform.new("aarch64-linux-musl"), :===, Gem::Platform.new("aarch64-linux"), "a glibc host does not")
  end

  private

  # Runs the block while RbConfig::CONFIG is `config`.
  def stub_const_config(config)
    was = RbConfig::CONFIG
    RbConfig.send(:remove_const, :CONFIG)
    RbConfig.const_set(:CONFIG, config)
    yield
  ensure
    RbConfig.send(:remove_const, :CONFIG)
    RbConfig.const_set(:CONFIG, was)
  end
end
