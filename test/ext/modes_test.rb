# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# One C extension in each of the ways that a build runs one (`ZR_EXT`):
# static (its object linked in), embed (its bundle relinked into the
# binary by zr's own linker) and dynamic (its bundle loaded with
# dlopen). The extension has a constructor that must run before its Init,
# pointers to its own data, calls of libSystem and of ruby's C API, and
# a C API data word.
class CExtModesTest < Minitest::Test
  SOURCE = <<~C
    #include <ruby.h>
    #include <string.h>

    static const char *greeting = "set by the constructor";
    static const char *table[] = { "zero", "one", "two" };
    // A store that the compiler cannot fold into the variable's first
    // value: the constructor must run.
    static volatile int constructed;

    __attribute__((constructor)) static void construct(void) { constructed = 42; }

    static VALUE status(VALUE self) {
      return rb_ary_new_from_args(3, INT2FIX(constructed), rb_str_new_cstr(greeting), INT2FIX((long)strlen(table[2])));
    }
    static VALUE pick(VALUE self, VALUE i) { return rb_str_new_cstr(table[NUM2INT(i) % 3]); }
    static VALUE object_class(VALUE self) { return rb_cObject; }

    void Init_modes(void) {
      VALUE m = rb_define_module("Modes");
      rb_define_module_function(m, "status", status, 0);
      rb_define_module_function(m, "pick", pick, 1);
      rb_define_module_function(m, "object_class", object_class, 0);
      rb_define_const(m, "AT_INIT", INT2FIX(constructed));
    }
  C

  PROGRAM = <<~RUBY
    require "modes"
    p Modes.status, Modes::AT_INIT
    p (0..4).map { |i| Modes.pick(i) }
    p Modes.object_class, $LOADED_FEATURES.grep(/modes/).map { File.basename(_1) }
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("modes", SOURCE)
  end

  %w[static embed dynamic].each do |mode|
    define_method(:"test_the_extension_runs_as_in_ruby_#{mode}") do
      ruby, (zr,) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}], mode: mode)
      assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr's output differs from ruby's (#{mode})\nzr stderr:\n#{zr.stderr}"
    end
  end
end
