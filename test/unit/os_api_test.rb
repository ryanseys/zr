# frozen_string_literal: true

require "test_helper"
require "ze0/zr"

# The OS layer's contract: rt/kernel/os.rb names every `zr_os_*` call and
# its signature, and each OS layer under rt/kernel/os/ defines exactly
# those, where the rest of the kernel defines none of them.
class OsApiTest < Minitest::Test
  SPEC = File.join(ROOT, "rt/kernel/os.rb")
  ROW = /\A#\s+(zr_(?:os|arch)_\w+)\s+\[([^\]]*)\]\s*=>\s*(\w+)\s*\z/

  # `{ name => [[param types], return type] }` from the comment rows.
  def spec
    File.readlines(SPEC, chomp: true).filter_map do |line|
      m = ROW.match(line) or next
      [m[1], [m[2].split(",").map(&:strip), m[3]]]
    end.to_h
  end

  def layers
    Dir[File.join(ROOT, "rt/kernel/os/*")].select { |dir| File.directory?(dir) }.map { |dir| File.basename(dir) }.sort
  end

  # The constants the spec says each OS defines.
  def constants
    lines = File.readlines(SPEC, chomp: true)
    start = lines.index { |line| line.start_with?("# The constants each OS defines") }
    lines.drop(start + 1).take_while { |line| line.start_with?("#   ") }.flat_map { |line| line.delete_prefix("#").split }
  end

  def test_the_spec_names_calls
    assert_operator spec.size, :>, 20
  end

  # RUBY_PLATFORM comes from the layer, and says what the target does.
  def test_the_layer_names_the_target_s_platform
    Ze0::Target.all.select { |target| target.os_layer == target.os.to_s }.each do |target|
      text = File.read(File.join(ROOT, "rt/kernel/os/#{target.os}/env.rb"))
      assert_includes text, %(zr_str_new(Machine.bytes("#{target.ruby_platform}"), #{target.ruby_platform.bytesize})), target.triple
    end
  end

  def test_every_core_layer_file_exists
    Ze0::Target.all.each do |target|
      Ze0::Zr.core_files(target).each { |path| assert File.file?(path), "#{target.triple}: #{path}" }
    end
  end

  def test_every_target_takes_a_layer_that_exists
    Ze0::Target.all.each do |target|
      assert_includes layers, target.os_layer, target.triple
      assert File.directory?(File.join(ROOT, "rt/kernel/arch", target.arch_layer)), target.triple
    end
  end

  def test_each_layer_defines_the_spec_and_nothing_else_does
    expected = spec
    Ze0::Target.all.map { |target| [target.os_layer, target] }.uniq(&:first).each do |layer, target|
      unit = Ze0::Machine.unit(Ze0::Zr.kernel_files(target))
      calls = unit.declared_defs.select { |name, _| name.start_with?("zr_os_", "zr_arch_") }
      got = calls.transform_values { |d| [d.params.map(&:last), d.ret] }
      assert_equal expected.keys.sort, got.keys.sort, "#{layer}: the zr_os_ and zr_arch_ defs"
      expected.each { |name, sig| assert_equal sig, got[name], "#{layer}: #{name}" }
      calls.each do |name, d|
        dir = name.start_with?("zr_os_") ? "rt/kernel/os/#{layer}/" : "rt/kernel/arch/#{target.arch_layer}/"
        assert d.file.start_with?(File.join(ROOT, dir)), "#{name} is in #{d.file}, not #{dir}"
      end
      constants.each do |name|
        assert_includes unit.declared_consts, name, "#{layer}: #{name}"
        assert unit.const_file(name).start_with?(File.join(ROOT, "rt/kernel/os/#{layer}/")), "#{layer}: #{name} is in #{unit.const_file(name)}"
      end
    end
  end
end
