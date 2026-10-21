# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The private functions of CRuby's instruction sequences that debuggers
# and coverage tools declare for themselves (kernel/capi/iseq.rb), as
# debug and datadog-ci call them: a RubyVM::InstructionSequence to its
# code and back, and the code's path, label, lines, type and parameters,
# against ruby's answers. zr keeps no columns, so the test reads lines.
class CExtIseqTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>

    typedef struct rb_iseq_struct rb_iseq_t;
    const rb_iseq_t *rb_iseqw_to_iseq(VALUE iseqw);
    VALUE rb_iseqw_new(const rb_iseq_t *iseq);
    void rb_iseq_code_location(const rb_iseq_t *iseq, int *first_lineno, int *first_column, int *last_lineno, int *last_column);
    VALUE rb_iseq_path(const rb_iseq_t *iseq);
    VALUE rb_iseq_realpath(const rb_iseq_t *iseq);
    VALUE rb_iseq_label(const rb_iseq_t *iseq);
    VALUE rb_iseq_first_lineno(const rb_iseq_t *iseq);
    VALUE rb_iseq_type(const rb_iseq_t *iseq);
    VALUE rb_iseq_parameters(const rb_iseq_t *iseq, int is_proc);

    static VALUE base_name(VALUE path) {
      return NIL_P(path) ? Qnil : rb_funcall(rb_cFile, rb_intern("basename"), 1, path);
    }

    static VALUE is_describe(VALUE self, VALUE iseqw) {
      const rb_iseq_t *iseq = rb_iseqw_to_iseq(iseqw);
      int first = -1, last = -1;
      rb_iseq_code_location(iseq, &first, NULL, &last, NULL);
      VALUE again = rb_iseqw_new(iseq);
      VALUE row = rb_ary_new_from_args(6, base_name(rb_iseq_path(iseq)), base_name(rb_iseq_realpath(iseq)), rb_iseq_label(iseq),
                                       rb_iseq_first_lineno(iseq), INT2NUM(first), INT2NUM(last));
      rb_ary_push(row, rb_iseq_type(iseq));
      rb_ary_push(row, rb_iseq_parameters(iseq, 0));
      rb_ary_push(row, rb_iseq_parameters(iseq, 1));
      rb_ary_push(row, rb_funcall(again, rb_intern("label"), 0));
      rb_ary_push(row, rb_obj_class(again));
      return row;
    }

    void Init_iseqs(void) {
      VALUE m = rb_define_module("Iseqs");
      rb_define_module_function(m, "describe", is_describe, 1);
    }
  C

  PROGRAM = <<~'RUBY'
    require "iseqs"

    class Shape
      def area(w, h = 1, *rest, scale:, **opts, &blk)
        w * h
      end

      def self.unit = new
    end

    adder = proc { |a, b = 2|
      a + b
    }
    lam = ->(x, y) do
      x * y
    end

    [Shape.instance_method(:area), Shape.method(:unit), adder, lam].each do |code|
      p Iseqs.describe(RubyVM::InstructionSequence.of(code))
    end
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("iseqs", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
