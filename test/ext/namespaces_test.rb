# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# Two C extensions in one binary, each with globals of the same names, as
# two bundles that ruby loads on macOS keep their names apart: each
# extension's calls reach its own definitions. One links from its objects
# (static) and the other embeds its bundle, so the two ways also mix in
# one build.
#
# Ruby on Linux loads each extension RTLD_GLOBAL, and ELF lets the first
# definition of a name stand for every later one: right's `bump` and
# `label` are left's there, and ruby prints left's four times. A zr
# binary keeps each extension's names its own on every target
# (Obj::Elf::Localize), so on Linux it gives the macOS answer, OWN_NAMES.
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
  OWN_NAMES = %(["left", 11]\n["right", 21]\n["left", 12]\n["right", 22]\n)

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @left = Zr::Test::CExt.build("left", self.class.source("left", 10))
    @right = Zr::Test::CExt.build("right", self.class.source("right", 20))
  end

  def test_each_extension_reaches_its_own_names
    ruby, zr = Zr::Test::CExt.outputs_together([@left, @right], PROGRAM, static: [@left, @right])
    assert_equal [OWN_NAMES, 0], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
    assert_equal [OWN_NAMES, 0], [ruby.stdout, ruby.status] if Zr::Target::AARCH64_DARWIN.native?
  end

  def test_a_static_and_an_embedded_extension_share_a_binary
    skip "embed mode loads a Mach-O bundle: it needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    ruby, zr = Zr::Test::CExt.outputs_together([@left, @right], PROGRAM, static: [@left])
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
  end
end
