# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# A C extension that the build cannot take is a refusal, as an
# unsupported form of Ruby is: one line that says what is missing, and
# status 3, never zr's report of a defect.
class CExtRefusalsTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>

    /* No ruby has it: zr's C API cannot either. */
    VALUE rb_zr_no_such_function(VALUE);

    static VALUE call(VALUE self, VALUE v) { return rb_zr_no_such_function(v); }

    void Init_refused(void) {
      rb_define_module_function(rb_define_module("Refused"), "call", call, 1);
    }
  C

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("refused", SOURCE)
  end

  def test_a_function_that_the_c_api_lacks_refuses_the_build
    _, zr = Zr::Test::CExt.outputs(@ext, "require 'refused'\n")

    assert_equal 3, zr.status
    assert_match(/\Azr: refused\.bundle: zr's C API has no rb_zr_no_such_function yet/, zr.stderr)
    refute_match(/internal error/, zr.stderr)
  end
end
