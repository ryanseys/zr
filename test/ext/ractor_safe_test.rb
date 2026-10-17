# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# A C method that its extension defined while RB_EXT_RACTOR_SAFE was
# false raises Ractor::UnsafeError in any Ractor but main, as etc's
# Etc.passwd does; one defined after RB_EXT_RACTOR_SAFE(true) runs there.
class CExtRactorSafeTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>

    static VALUE answer(VALUE self) { return INT2FIX(42); }

    void Init_ractorsafe(void) {
      VALUE m = rb_define_module("RactorSafe");
      rb_define_module_function(m, "before", answer, 0);
      rb_ext_ractor_safe(true);
      rb_define_module_function(m, "safe", answer, 0);
      rb_ext_ractor_safe(false);
      rb_define_module_function(m, "unsafe", answer, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "ractorsafe"

    p RactorSafe.before, RactorSafe.safe, RactorSafe.unsafe
    p(Ractor.new do
      %i[before safe unsafe].map do |name|
        RactorSafe.public_send(name)
      rescue Ractor::UnsafeError => e
        [e.class, e.message]
      end
    end.value)
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("ractorsafe", SOURCE)
  end

  def test_an_unsafe_c_method_raises_outside_the_main_ractor
    ruby, (plain,) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
  end
end
