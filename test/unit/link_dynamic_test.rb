# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/native/link/dynamic"

# The dynamic link of a glibc binary: its flags, and the list of C API
# names that its dynamic symbol table exports to C extensions.
class LinkDynamicTest < Minitest::Test
  Dynamic = Zr::Native::Link::Dynamic

  def test_the_export_list_is_the_sorted_c_api
    list = Dynamic.exports
    names = list.scan(/^  (\S+);$/).flatten
    assert list.start_with?("{\n")
    assert list.end_with?("};\n")
    assert_includes names, "rb_define_method"
    assert_includes names, "rb_cObject"
    assert_equal names.sort, names
    assert_equal Zr::Ext::CApi.names.size, names.size
  end

  def test_the_link_is_a_fixed_address_executable_bound_at_start
    assert_includes Dynamic::FLAGS, "-no-pie"
    assert_includes Dynamic::FLAGS, "-Wl,-z,now"
    assert_includes Dynamic::FLAGS, "-Wl,--build-id=none"
    refute_includes Dynamic::FLAGS, "-static"
    assert_equal ["-lm", "-lcrypt"], Dynamic::LIBRARIES
  end
end
