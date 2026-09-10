# frozen_string_literal: true

require_relative "helper"
require "ze0/zr"

# The kernel description a program carries for its evals. A stale one is
# a miscompile, so the check writes it again and demands the same bytes.
# `ZE0_BLESS=1` rewrites it.
class DescriptionTest < Minitest::Test
  PATH = File.join(ROOT, "rt/ext/zr_description.rb")

  def test_the_description_matches_the_kernel
    text = IO.popen([RbConfig.ruby, "-I#{File.join(ROOT, "lib")}", File.join(ROOT, "tools/description.rb")], &:read)
    assert $?.success?, "tools/description.rb failed"

    if ENV["ZE0_BLESS"] == "1"
      File.write(PATH, text)
      skip "blessed #{PATH}"
    end
    assert_equal File.read(PATH), text, "#{PATH} is stale (ZE0_BLESS=1 to accept)"
  end

  def test_the_description_answers_as_the_kernel_unit_does
    require_relative "../../rt/ext/zr_description"
    unit = Ze0::Zr.runtime.unit
    carried = Ze0::Machine::Description.parse(Ze0::Machine::Description::KERNEL)
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
