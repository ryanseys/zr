# frozen_string_literal: true

require "test_helper"
require "open3"
require_relative "../../lib/zr/compiled_compiler"

# exe/zr gives a build to the compiled compiler only when no source file
# of the compiled compiler has changed. Here a shell script is in place
# of the compiled compiler. Thus the test builds nothing and changes no
# file under lib, runtime or vendor.
class CompiledCompilerTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")

  # Yields a directory with a stand-in compiled compiler, and the path of
  # its manifest.
  def with_binary
    Dir.mktmpdir("zr-self-host-") do |dir|
      binary = File.join(dir, "zr")
      File.write(binary, "#!/bin/sh\necho compiled \"$@\"\n")
      File.chmod(0o755, binary)
      yield dir, "#{binary}.manifest"
    end
  end

  def zr(dir, *args, self_env: nil)
    env = { "ZR_CACHE" => File.join(dir, "cache"), "ZR_BINARY" => File.join(dir, "zr"), "ZR_COMPILED" => self_env,
            "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
    out, status = Open3.capture2e(env, RbConfig.ruby, EXE, *args, chdir: ROOT)
    [out, status]
  end

  def test_a_current_compiled_compiler_takes_the_build
    with_binary do |dir, manifest|
      File.binwrite(manifest, Marshal.dump(Zr::CompiledCompiler.stamps))
      out, status = zr(dir, "build", "missing.rb", "-o", "out")
      assert status.success?, out
      assert_equal "compiled build missing.rb -o out\n", out
    end
  end

  def test_changed_source_file_builds_with_ruby
    with_binary do |dir, manifest|
      stamps = Zr::CompiledCompiler.stamps
      file = stamps.keys.first
      stamps[file] = stamps[file].dup.tap { |s| s[0] += 1 }
      File.binwrite(manifest, Marshal.dump(stamps))
      out, = zr(dir, "build", "missing.rb", "-o", "out")
      refute_includes out, "compiled"
    end
  end

  def test_a_file_the_build_did_not_read_leaves_the_build_to_ruby
    with_binary do |dir, manifest|
      stamps = Zr::CompiledCompiler.stamps
      stamps.delete(stamps.keys.last)
      File.binwrite(manifest, Marshal.dump(stamps))
      out, = zr(dir, "build", "missing.rb", "-o", "out")
      refute_includes out, "compiled"
    end
  end

  def test_zr_self_0_and_other_commands_stay_with_ruby
    with_binary do |dir, manifest|
      File.binwrite(manifest, Marshal.dump(Zr::CompiledCompiler.stamps))
      out, = zr(dir, "build", "missing.rb", "-o", "out", self_env: "0")
      refute_includes out, "compiled"
      out, status = zr(dir, "version")
      assert status.success?, out
      refute_includes out, "compiled"
    end
  end

  # In a checkout, a build does not make a compiled compiler when there
  # is none. `ZR_COMPILED=1` or `rake build:self` makes one.
  def test_a_checkout_with_no_compiled_compiler_stays_with_ruby
    skip "not a checkout" unless Zr::Paths.checkout?
    Dir.mktmpdir("zr-self-host-") do |dir|
      out, = zr(dir, "build", "missing.rb", "-o", "out")
      refute_includes out, "building the compiler with itself"
      refute File.exist?(File.join(dir, "zr"))
    end
  end

  def test_the_compiled_compiler_of_a_checkout_is_bin_zr
    skip "not a checkout" unless Zr::Paths.checkout?
    binary = ENV.delete("ZR_BINARY")

    assert_equal File.join(ROOT, "bin/zr"), Zr::CompiledCompiler.binary
    assert_equal File.join(ROOT, "bin/zr.manifest"), Zr::CompiledCompiler.manifest
  ensure
    ENV["ZR_BINARY"] = binary if binary
  end
end
