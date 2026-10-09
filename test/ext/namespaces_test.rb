# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# Two C extensions in one binary, each with globals of the same names, as
# two bundles that ruby loads keep their names apart: each extension's
# calls reach its own definitions. One links from its objects (static) and
# the other embeds its bundle, so the two ways also mix in one build.
class CExtNamespacesTest < Minitest::Test
  def self.source(name, value)
    <<~C
      #include <ruby.h>

      int counter = #{value};
      const char *label(void) { return "#{name}"; }
      int bump(void) { return ++counter; }

      static VALUE status(VALUE self) {
        bump();
        return rb_ary_new_from_args(2, rb_str_new_cstr(label()), INT2FIX(counter));
      }

      void Init_#{name}(void) {
        rb_define_module_function(rb_define_module("#{name.capitalize}"), "status", status, 0);
      }
    C
  end

  PROGRAM = <<~RUBY
    require "left"
    require "right"
    p Left.status, Right.status, Left.status, Right.status
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @left = Zr::Test::CExt.build("left", self.class.source("left", 10))
    @right = Zr::Test::CExt.build("right", self.class.source("right", 20))
  end

  def test_each_extension_reaches_its_own_names
    ruby, zr = Zr::Test::CExt.outputs_together([@left, @right], PROGRAM, static: [@left, @right])
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
  end

  def test_a_static_and_an_embedded_extension_share_a_binary
    ruby, zr = Zr::Test::CExt.outputs_together([@left, @right], PROGRAM, static: [@left])
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
  end
end
