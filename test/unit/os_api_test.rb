# frozen_string_literal: true

require "test_helper"
require "zr/runtime"
require "zr/native/link/darwin"

# The OS and architecture layers of each target: their files exist, and
# the OS layer gives the target's RUBY_PLATFORM. A call to a `zr_os_*`
# function that a layer does not define stops the build of that
# target's runtime, so no list of the functions is kept.
class OsApiTest < Minitest::Test
  def layers
    Dir[File.join(ROOT, "lib/zr/runtime/kernel/os/*")].filter_map { |dir| File.basename(dir) if File.directory?(dir) }.sort
  end

  # The OS layer sets RUBY_PLATFORM to the platform string of the target.
  def test_os_layer_sets_target_ruby_platform
    Zr::Target.all.select { |target| target.os_layer == target.os.to_s }.each do |target|
      text = File.read(File.join(ROOT, "lib/zr/runtime/kernel/os/#{target.os}/env.rb"))
      assert_includes text, %(zr_str_new(Machine.bytes("#{target.ruby_platform}"), #{target.ruby_platform.bytesize})), target.triple
    end
  end

  # A darwin binary gives the platform of the oldest macOS that it loads
  # on, and both Mach-O writers record that macOS.
  def test_darwin_platform_follows_min_os
    target = Zr::Target::AARCH64_DARWIN
    assert_equal "arm64-darwin23", target.ruby_platform
    assert_equal Zr::Target.darwin_platform(target.min_os), target.ruby_platform
    assert_equal [14, 0, 0], target.min_os_parts
    assert_equal 14 << 16, Zr::Obj::MachO::Executable::MIN_MACOS
    assert_includes Zr::Native::Link::Darwin::MIN_OS_FLAGS, "-mmacosx-version-min=14.0"
  end

  def test_every_core_layer_file_exists
    Zr::Target.all.each do |target|
      Zr::RuntimeSources.for(target).core_files.each { |path| assert File.file?(path), "#{target.triple}: #{path}" }
    end
  end

  def test_every_target_takes_a_layer_that_exists
    Zr::Target.all.each do |target|
      assert_includes layers, target.os_layer, target.triple
      assert File.directory?(File.join(ROOT, "lib/zr/runtime/kernel/arch", target.arch_layer)), target.triple
    end
  end
end
