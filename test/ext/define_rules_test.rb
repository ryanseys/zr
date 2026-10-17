# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The rules that CRuby applies to what C defines and reads, which the own
# C of stringio, date, etc and io/console meets: rb_f_notimplement's
# methods are not defined, initialize and its kin are private, a define
# over a constant of another kind names it, make_shareable refuses data
# whose type is not frozen-shareable, rb_io_puts marks what it walks,
# rb_io_gets ends a line at "\n" whatever $/ is, and a chilled String has
# ruby's STR_CHILLED bit.
class CExtDefineRulesTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>

    static const rb_data_type_t plain_type = { "plain", { 0, 0, 0 }, 0, 0, 0 };
    static const rb_data_type_t shared_type = { "shared", { 0, 0, 0 }, 0, 0, RUBY_TYPED_FROZEN_SHAREABLE };

    static VALUE r_plain(VALUE self) { return TypedData_Wrap_Struct(rb_cObject, &plain_type, 0); }
    static VALUE r_shared(VALUE self) { return TypedData_Wrap_Struct(rb_cObject, &shared_type, 0); }
    static VALUE r_init(VALUE self) { return self; }
    static VALUE r_define(VALUE self, VALUE name, VALUE module) {
      return RTEST(module) ? rb_define_module(StringValueCStr(name)) : rb_define_class(StringValueCStr(name), rb_cObject);
    }
    static VALUE r_puts(VALUE self, VALUE out, VALUE obj) { return rb_io_puts(1, &obj, out); }
    static VALUE r_gets(VALUE self, VALUE io) { return rb_io_gets(io); }
    static VALUE r_chilled(VALUE self, VALUE str) { return RB_FL_TEST_RAW(str, RUBY_FL_USER2) ? Qtrue : Qfalse; }

    void Init_definerules(void) {
      VALUE m = rb_define_module("DefineRules");
      VALUE k = rb_define_class_under(m, "Thing", rb_cObject);
      rb_define_method(k, "initialize", r_init, 0);
      rb_define_method(k, "initialize_copy", r_init, 0);
      rb_define_method(k, "respond_to_missing?", r_init, 0);
      rb_define_method(k, "missing", rb_f_notimplement, -1);
      rb_define_singleton_method(k, "initialize", r_init, 0);
      rb_define_module_function(m, "plain", r_plain, 0);
      rb_define_module_function(m, "shared", r_shared, 0);
      rb_define_module_function(m, "define", r_define, 2);
      rb_define_module_function(m, "puts", r_puts, 2);
      rb_define_module_function(m, "gets", r_gets, 1);
      rb_define_module_function(m, "chilled", r_chilled, 1);
    }
  C

  PROGRAM = <<~'RUBY'
    require "definerules"

    k = DefineRules::Thing
    p k.private_instance_methods(false).sort, k.public_instance_methods(false).sort, k.singleton_methods(false)
    p k.method_defined?(:missing), k.new.respond_to?(:missing)
    begin
      k.new.missing
    rescue NotImplementedError => e
      p [e.class, e.message]
    end
    Cell = Object.new
    Box = 1
    [["Cell", true], ["Box", false], ["Comparable", false], ["Kernel", true]].each do |name, mod|
      p DefineRules.define(name, mod)
    rescue TypeError => e
      p e.message
    end
    p (Ractor.make_shareable(DefineRules.plain) rescue $!.class), Ractor.shareable?(Ractor.make_shareable(DefineRules.shared))
    out = Object.new
    def out.write(*parts) = (@got ||= []) << parts
    def out.got = @got
    a = Object.new
    def a.to_ary = [1, [self, 2]]
    DefineRules.puts(out, a)
    DefineRules.puts(out, [])
    DefineRules.puts(out, "x\n")
    p out.got
    r, w = IO.pipe
    w.write("one.two\nthree")
    w.close
    $/ = "."
    p DefineRules.gets(r), DefineRules.gets(r), DefineRules.gets(r)
    $/ = "\n"
    p DefineRules.chilled("lit"), DefineRules.chilled(+"lit"), DefineRules.chilled("lit".dup)
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("definerules", SOURCE)
  end

  def test_each_rule_gives_rubys_answer
    ruby, (plain,) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
  end
end
