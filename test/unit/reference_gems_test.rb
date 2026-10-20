# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/library/ports"
require_relative "../support/c_ext"

# The reference ruby's gems for test/ext (test/support/c_ext.rb): a port's
# gem is at zr's version of the port, so ruby and zr load the same code.
class ReferenceGemsTest < Minitest::Test
  def test_a_ports_gem_is_at_the_ports_version
    Zr::Test::CExt::REFERENCE_GEMS.each do |name, version|
      port = Zr::Library::Ports::ALL[name] or next

      assert_equal port.version, version, name
    end
  end
end
