# frozen_string_literal: true

require "test_helper"
require "open3"
require_relative "../../lib/ze0/self_host"

# exe/ze0 hands a build to the compiled compiler only while every file it
# was built from is as it was. A shell script stands in for the compiled
# compiler here, so the check builds nothing and changes no file under
# lib, rt or vendor.
class SelfHostTest < Minitest::Test
  EXE = File.join(ROOT, "exe/ze0")

  def with_cache
    Dir.mktmpdir("ze0-self-host-") do |cache|
      self_dir = File.join(cache, "self")
      FileUtils.mkdir_p(self_dir)
      File.write(File.join(self_dir, "ze0"), "#!/bin/sh\necho compiled \"$@\"\n")
      File.chmod(0o755, File.join(self_dir, "ze0"))
      yield cache, File.join(self_dir, "manifest.marshal")
    end
  end

  def ze0(cache, *args, self_env: nil)
    env = { "ZE0_CACHE" => cache, "ZE0_SELF" => self_env, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
    out, status = Open3.capture2e(env, RbConfig.ruby, EXE, *args, chdir: ROOT)
    [out, status]
  end

  def test_a_current_compiled_compiler_takes_the_build
    with_cache do |cache, manifest|
      File.binwrite(manifest, Marshal.dump(Ze0::SelfHost.stamps))
      out, status = ze0(cache, "build", "missing.rb", "-o", "out")
      assert status.success?, out
      assert_equal "compiled build missing.rb -o out\n", out
    end
  end

  def test_a_moved_file_leaves_the_build_to_ruby
    with_cache do |cache, manifest|
      stamps = Ze0::SelfHost.stamps
      file = stamps.keys.first
      stamps[file] = stamps[file].dup.tap { |s| s[0] += 1 }
      File.binwrite(manifest, Marshal.dump(stamps))
      out, = ze0(cache, "build", "missing.rb", "-o", "out")
      refute_includes out, "compiled"
    end
  end

  def test_a_file_the_build_did_not_read_leaves_the_build_to_ruby
    with_cache do |cache, manifest|
      stamps = Ze0::SelfHost.stamps
      stamps.delete(stamps.keys.last)
      File.binwrite(manifest, Marshal.dump(stamps))
      out, = ze0(cache, "build", "missing.rb", "-o", "out")
      refute_includes out, "compiled"
    end
  end

  def test_ze0_self_0_and_other_commands_stay_with_ruby
    with_cache do |cache, manifest|
      File.binwrite(manifest, Marshal.dump(Ze0::SelfHost.stamps))
      out, = ze0(cache, "build", "missing.rb", "-o", "out", self_env: "0")
      refute_includes out, "compiled"
      out, status = ze0(cache, "version")
      assert status.success?, out
      refute_includes out, "compiled"
    end
  end

  # A checkout builds no compiled compiler for a build that finds none;
  # `ZE0_SELF=1` or `rake build:self` does.
  def test_a_checkout_with_no_compiled_compiler_stays_with_ruby
    skip "not a checkout" unless Ze0::Paths.checkout?
    Dir.mktmpdir("ze0-self-host-") do |cache|
      out, = ze0(cache, "build", "missing.rb", "-o", "out")
      refute_includes out, "building the compiler with itself"
      refute File.exist?(File.join(cache, "self", "ze0"))
    end
  end
end
