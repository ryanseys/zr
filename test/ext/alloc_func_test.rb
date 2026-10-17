# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# An allocator that C defines (rb_define_alloc_func) gets the class that
# `new` or `allocate` was called on, which C compares with the class it
# keeps, and may raise, as digest's abstract Digest::Base does: the
# format of its message runs with no frame of its own above the program's.
# C's rb_undef_method of initialize warns nothing, as io/console's does not.
class CExtAllocFuncTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>

    static VALUE cBase;
    static const rb_data_type_t thing_type = { "thing", { 0, RUBY_TYPED_DEFAULT_FREE, 0 }, 0, 0, RUBY_TYPED_FREE_IMMEDIATELY };

    static VALUE thing_alloc(VALUE klass) {
      if (klass == cBase) rb_raise(rb_eNotImpError, "Base is an abstract class");
      return TypedData_Wrap_Struct(klass, &thing_type, 0);
    }

    static VALUE boom(VALUE self) { rb_raise(rb_eArgError, "boom %d", 7); return Qnil; }

    void Init_allocfunc(void) {
      VALUE m = rb_define_module("AllocFunc");
      cBase = rb_define_class_under(m, "Base", rb_cObject);
      rb_define_alloc_func(cBase, thing_alloc);
      rb_define_module_function(m, "boom", boom, 0);
      rb_undef_method(rb_define_class_under(m, "Mode", rb_cObject), "initialize");
    }
  C

  PROGRAM = <<~'RUBY'
    require "allocfunc"

    class Leaf < AllocFunc::Base; end
    p((AllocFunc.boom rescue $!))
    [-> { AllocFunc::Base.new }, -> { AllocFunc::Base.allocate }, -> { Leaf.new.class }, -> { Class.new(Leaf).new.class.superclass }].each do |make|
      p make.call
    rescue NotImplementedError => e
      p e
    end
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("allocfunc", SOURCE)
  end

  def test_an_allocator_gets_its_class_and_may_raise
    ruby, (plain,) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.stderr, ruby.status], [plain.stdout, plain.stderr, plain.status]
  end
end
