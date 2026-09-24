# frozen_string_literal: true

require "test_helper"
require "open3"
require_relative "../../lib/zr/self_host"

# exe/zr hands a build to the compiled compiler only while every file it
# was built from is as it was. A shell script stands in for the compiled
# compiler here, so the check builds nothing and changes no file under
# lib, rt or vendor.
class SelfHostTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")

  def with_cache
    Dir.mktmpdir("zr-self-host-") do |cache|
      self_dir = File.join(cache, "self")
      FileUtils.mkdir_p(self_dir)
      File.write(File.join(self_dir, "zr"), "#!/bin/sh\necho compiled \"$@\"\n")
      File.chmod(0o755, File.join(self_dir, "zr"))
      yield cache, File.join(self_dir, "manifest.marshal")
    end
  end

  def zr(cache, *args, self_env: nil)
    env = { "ZR_CACHE" => cache, "ZR_SELF" => self_env, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
    out, status = Open3.capture2e(env, RbConfig.ruby, EXE, *args, chdir: ROOT)
    [out, status]
  end

  def test_a_current_compiled_compiler_takes_the_build
    with_cache do |cache, manifest|
      File.binwrite(manifest, Marshal.dump(Zr::SelfHost.stamps))
      out, status = zr(cache, "build", "missing.rb", "-o", "out")
      assert status.success?, out
      assert_equal "compiled build missing.rb -o out\n", out
    end
  end

  def test_a_moved_file_leaves_the_build_to_ruby
    with_cache do |cache, manifest|
      stamps = Zr::SelfHost.stamps
      file = stamps.keys.first
      stamps[file] = stamps[file].dup.tap { |s| s[0] += 1 }
      File.binwrite(manifest, Marshal.dump(stamps))
      out, = zr(cache, "build", "missing.rb", "-o", "out")
      refute_includes out, "compiled"
    end
  end

  def test_a_file_the_build_did_not_read_leaves_the_build_to_ruby
    with_cache do |cache, manifest|
      stamps = Zr::SelfHost.stamps
      stamps.delete(stamps.keys.last)
      File.binwrite(manifest, Marshal.dump(stamps))
      out, = zr(cache, "build", "missing.rb", "-o", "out")
      refute_includes out, "compiled"
    end
  end

  def test_zr_self_0_and_other_commands_stay_with_ruby
    with_cache do |cache, manifest|
      File.binwrite(manifest, Marshal.dump(Zr::SelfHost.stamps))
      out, = zr(cache, "build", "missing.rb", "-o", "out", self_env: "0")
      refute_includes out, "compiled"
      out, status = zr(cache, "version")
      assert status.success?, out
      refute_includes out, "compiled"
    end
  end

  # A checkout builds no compiled compiler for a build that finds none;
  # `ZR_SELF=1` or `rake build:self` does.
  def test_a_checkout_with_no_compiled_compiler_stays_with_ruby
    skip "not a checkout" unless Zr::Paths.checkout?
    Dir.mktmpdir("zr-self-host-") do |cache|
      out, = zr(cache, "build", "missing.rb", "-o", "out")
      refute_includes out, "building the compiler with itself"
      refute File.exist?(File.join(cache, "self", "zr"))
    end
  end
end
