# frozen_string_literal: true

require "test_helper"
require "ze0/zr"

# The kernel description a program carries for its evals, one per OS
# layer. A stale one is a miscompile, so the check writes each again and
# demands the same bytes. `ZE0_BLESS=1` rewrites them.
class DescriptionTest < Minitest::Test
  # One target per OS layer that is its own.
  TARGETS = Ze0::Target.all.select { |target| target.os_layer == target.os.to_s }.uniq(&:os_layer)

  def path(target) = File.join(ROOT, "rt/ext/os", target.os_layer, "zr_description.rb")

  TARGETS.each do |target|
    define_method("test_the_#{target.os_layer}_description_matches_its_kernel") do
      text = IO.popen([RbConfig.ruby, "-I#{File.join(ROOT, "lib")}", File.join(ROOT, "test/support/oracle/description.rb"), target.triple], &:read)
      assert $?.success?, "test/support/oracle/description.rb failed"

      if ENV["ZE0_BLESS"] == "1"
        File.write(path(target), text)
        skip "blessed #{path(target)}"
      end
      assert_equal File.read(path(target)), text, "#{path(target)} is stale (ZE0_BLESS=1 to accept)"
    end

    define_method("test_the_#{target.os_layer}_description_answers_as_its_kernel_unit_does") do
      unit = Ze0::Zr.runtime(target).unit
      carried = Ze0::Machine::Description.parse(File.read(path(target))[/<<~ROWS\n(.*?)^\s*ROWS$/m, 1].gsub(/^ +/, ""))
      live = Ze0::Machine::Description.of(unit)

      assert_equal live.defs.keys.sort, carried.defs.keys.sort
      live.defs.each { |name, d| assert_equal [d.params, d.ret], [carried.def_for(name).params, carried.def_for(name).ret], name }
      live.consts.each { |name, value| assert_equal value, carried.const_for(name), name }
      live.structs.each do |name, layout|
        assert_equal [layout.fields, layout.size, layout.align],
                     [carried.struct_for(name).fields, carried.struct_for(name).size, carried.struct_for(name).align], name
      end
    end
  end
end
