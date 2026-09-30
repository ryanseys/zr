# frozen_string_literal: true

require "test_helper"
require "zr/runtime"
require "zr/native/link/darwin"

# The contract of the OS layer: runtime/kernel/os.rb lists every `zr_os_*`
# call and its signature. Each OS layer under runtime/kernel/os/ defines
# exactly those calls, and no other part of the kernel defines them.
class OsApiTest < Minitest::Test
  SPEC = File.join(ROOT, "runtime/kernel/os.rb")
  ROW = /\A#\s+(zr_(?:os|arch)_\w+)\s+\[([^\]]*)\]\s*=>\s*(\w+)\s*\z/

  # `{ name => [[param types], return type] }` from the comment lines.
  def spec
    File.readlines(SPEC, chomp: true).filter_map do |line|
      m = ROW.match(line) or next
      [m[1], [m[2].split(",").map(&:strip), m[3]]]
    end.to_h
  end

  def layers
    Dir[File.join(ROOT, "runtime/kernel/os/*")].select { |dir| File.directory?(dir) }.map { |dir| File.basename(dir) }.sort
  end

  # The constants the spec says each OS defines.
  def constants
    lines = File.readlines(SPEC, chomp: true)
    start = lines.index { |line| line.start_with?("# The constants each OS defines") }
    lines.drop(start + 1).take_while { |line| line.start_with?("#   ") }.flat_map { |line| line.delete_prefix("#").split }
  end

  def test_spec_lists_os_calls
    assert_operator spec.size, :>, 20
  end

  # The OS layer sets RUBY_PLATFORM to the platform string of the target.
  def test_os_layer_sets_target_ruby_platform
    Zr::Target.all.select { |target| target.os_layer == target.os.to_s }.each do |target|
      text = File.read(File.join(ROOT, "runtime/kernel/os/#{target.os}/env.rb"))
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
      assert File.directory?(File.join(ROOT, "runtime/kernel/arch", target.arch_layer)), target.triple
    end
  end

  def test_each_layer_defines_the_spec_and_nothing_else_does
    expected = spec
    Zr::Target.all.map { |target| [target.os_layer, target] }.uniq(&:first).each do |layer, target|
      unit = Zr::Machine.unit(Zr::RuntimeSources.for(target).kernel_files)
      calls = unit.declared_defs.select { |name, _| name.start_with?("zr_os_", "zr_arch_") }
      got = calls.transform_values { |d| [d.params.map(&:last), d.ret] }
      assert_equal expected.keys.sort, got.keys.sort, "#{layer}: the zr_os_ and zr_arch_ defs"
      expected.each { |name, sig| assert_equal sig, got[name], "#{layer}: #{name}" }
      calls.each do |name, d|
        dir = name.start_with?("zr_os_") ? "runtime/kernel/os/#{layer}/" : "runtime/kernel/arch/#{target.arch_layer}/"
        assert d.file.start_with?(File.join(ROOT, dir)), "#{name} is in #{d.file}, not #{dir}"
      end
      constants.each do |name|
        assert_includes unit.declared_consts, name, "#{layer}: #{name}"
        assert unit.const_file(name).start_with?(File.join(ROOT, "runtime/kernel/os/#{layer}/")), "#{layer}: #{name} is in #{unit.const_file(name)}"
      end
    end
  end
end
