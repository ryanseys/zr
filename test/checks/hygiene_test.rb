# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/machine/lower"
require_relative "../../lib/ze0/native/build"
require_relative "../../lib/ze0/obj/exe"
require_relative "../../lib/ze0/obj/jit/fiddle"
require_relative "../../lib/ze0/ir/interp"
require_relative "../../lib/ze0/backend/aarch64/listing"
require_relative "../../lib/ze0/harness/sweep"
require_relative "../../lib/ze0/deps"

# One limit on ze0's Ruby: no method it defines may share a name with an
# `Object` or `Kernel` method. `Lower#send` did, for a while: a private
# method on `Lower`, it overrode `Object#send` for every instance of the
# class, silently and only inside ze0.
# It loads the library itself rather than inspecting whatever an earlier
# check happened to require: what this covers must not depend on the
# order minitest loads files in.
class HygieneTest < Minitest::Test
  DELIBERATE = %i[initialize to_s inspect].freeze

  def under(mod, seen)
    mod.constants(false).each do |c|
      value = mod.const_get(c)
      next unless value.is_a?(Module) && value.name.to_s.start_with?("Ze0")
      next if seen.key?(value)

      seen[value] = true
      under(value, seen)
    end
    seen
  end

  def test_no_ze0_method_shadows_an_object_method
    inherited = Object.instance_methods + Object.private_instance_methods
    shadows = under(Ze0, { Ze0 => true }).each_key.flat_map do |mod|
      own = mod.instance_methods(false) + mod.private_instance_methods(false)
      (own & inherited - DELIBERATE).map { |name| "#{mod}##{name}" }
    end
    assert_empty shadows.sort, "ze0 shadows Object/Kernel methods"
  end
end
