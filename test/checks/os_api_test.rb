# frozen_string_literal: true

require_relative "helper"
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

  def test_the_spec_names_calls
    assert_operator spec.size, :>, 20
  end

  def test_every_target_takes_a_layer_that_exists
    Ze0::Target.all.each do |target|
      assert_includes layers, Ze0::Zr.os_layer(target), target.triple
      assert File.directory?(File.join(ROOT, "rt/kernel/arch", Ze0::Zr.arch_layer(target))), target.triple
    end
  end

  def test_each_layer_defines_the_spec_and_nothing_else_does
    expected = spec
    Ze0::Target.all.map { |target| [Ze0::Zr.os_layer(target), target] }.uniq(&:first).each do |layer, target|
      unit = Ze0::Machine.unit(Ze0::Zr.kernel_files(target))
      calls = unit.declared_defs.select { |name, _| name.start_with?("zr_os_", "zr_arch_") }
      got = calls.transform_values { |d| [d.params.map(&:last), d.ret] }
      assert_equal expected.keys.sort, got.keys.sort, "#{layer}: the zr_os_ and zr_arch_ defs"
      expected.each { |name, sig| assert_equal sig, got[name], "#{layer}: #{name}" }
      calls.each do |name, d|
        dir = name.start_with?("zr_os_") ? "rt/kernel/os/#{layer}/" : "rt/kernel/arch/#{Ze0::Zr.arch_layer(target)}/"
        assert d.file.start_with?(File.join(ROOT, dir)), "#{name} is in #{d.file}, not #{dir}"
      end
    end
  end
end
