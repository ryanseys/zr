# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C functions that return nothing (kernel/capi/entry.rb,
# data_object.rb): an extension's Init, a T_DATA's free function and an
# end proc. Each leaves in its result register the word of the last
# function that it called; bindex's Init ends with rb_tracepoint_enable,
# whose answer is Qundef. Only an unwind says that such a function
# raised, as in ruby.
class CExtVoidCallbacksTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>

    /* Each one is void to its caller; the Qundef stands for the word
       that a tail call leaves. */
    static VALUE free_leaving_undef(void *p) {
      xfree(p);
      return Qundef;
    }

    static VALUE end_leaving_undef(VALUE data) {
      printf("end proc %ld\n", NUM2LONG(data));
      fflush(stdout);
      return Qundef;
    }

    static const rb_data_type_t box_type = {"box", {NULL, (void (*)(void *))free_leaving_undef, NULL}, 0, 0, 0};

    static VALUE vc_box(VALUE self) {
      return TypedData_Wrap_Struct(rb_cObject, &box_type, xmalloc(16));
    }

    static VALUE vc_raise(VALUE self) {
      rb_raise(rb_eArgError, "raised from C");
      return Qnil;
    }

    VALUE Init_voids(void) {
      VALUE m = rb_define_module("Voids");
      rb_define_module_function(m, "box", vc_box, 0);
      rb_define_module_function(m, "raise", vc_raise, 0);
      rb_set_end_proc((void (*)(VALUE))end_leaving_undef, LONG2NUM(7));
      return Qundef;
    }
  C

  PROGRAM = <<~'RUBY'
    p require("voids")
    50.times { Voids.box }
    GC.start
    begin
      Voids.raise
    rescue ArgumentError => e
      p [e.class, e.message, $!]
    end
    p :done
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("voids", SOURCE)
  end

  def test_a_void_function_that_leaves_undef_has_not_raised
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
