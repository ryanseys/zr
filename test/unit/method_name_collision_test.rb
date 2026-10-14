# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/machine/lower"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/obj/macho/executable"
require_relative "../../lib/zr/obj/jit/fiddle"

# No method that zr defines can have the name of an `Object` or `Kernel`
# method. For example, a private `Lower#send` overrode `Object#send` for
# each instance of `Lower`, with no error.
# The test loads the library itself. It does not examine what earlier
# tests loaded, so the result does not depend on the load order.
class MethodNameCollisionTest < Minitest::Test
  # A Struct or Data record is equal by value.
  DELIBERATE = %i[initialize to_s inspect == eql? hash].freeze

  # Examine only the library. The tests also put modules in `Zr`, so the
  # test must not examine everything that is loaded.
  LIB = File.join(ROOT, "lib")

  def under(mod, seen)
    mod.constants(false).each do |c|
      value = mod.const_get(c)
      next unless value.is_a?(Module) && value.name.to_s.start_with?("Zr")
      next if seen.key?(value) || !library?(mod, c)

      seen[value] = true
      under(value, seen)
    end
    seen
  end

  # Returns true if the constant is defined in `lib`. A module built at
  # run time gives the file that built it. A module with no source
  # location is left out.
  def library?(mod, name)
    mod.const_source_location(name)&.first&.start_with?(LIB)
  end

  def test_no_zr_method_shadows_an_object_method
    inherited = Object.instance_methods + Object.private_instance_methods
    shadows = under(Zr, { Zr => true }).each_key.flat_map do |mod|
      own = mod.instance_methods(false) + mod.private_instance_methods(false)
      (own & inherited - DELIBERATE).map { |name| "#{mod}##{name}" }
    end
    assert_empty shadows.sort, "zr shadows Object/Kernel methods"
  end

  # The compiler parses with prism through lib/zr/parse.rb, which puts the
  # Ruby port in place of the C extension. If a file required prism
  # directly, the C extension would load first, and the port would not
  # load. The harness that checks the port against the C extension loads
  # the C extension on purpose, and so does `zr-dev fuzz`, which edits and
  # reduces programs on prism's tree in a process that never compiles
  # (fuzz/builder.rb compiles in a process of its own).
  C_PRISM = %w[tool/lib/zr/dev/fuzz/metamorphic.rb tool/lib/zr/dev/fuzz/mutator.rb tool/lib/zr/dev/fuzz/reducer.rb].freeze

  def test_the_compiler_requires_prism_only_through_zr_prism
    direct = (Dir[File.join(ROOT, "{lib,tool,exe}/**/*.rb")] - Dir[File.join(ROOT, "lib/zr/runtime/**/*.rb")]).select do |file|
      File.read(file).match?(/^\s*require ["']prism["']/) && !file.end_with?("/lib/zr/parse.rb") &&
        !C_PRISM.include?(file.delete_prefix("#{ROOT}/"))
    end
    assert_empty direct.map { |file| file.delete_prefix("#{ROOT}/") }
  end
end
