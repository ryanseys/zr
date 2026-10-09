# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API's objects, classes, IDs, Arrays, Hashes, Strings, numbers and
# Times that google-protobuf, rbtree, thrift, cgi, rugged and oj call
# (`zr-dev ext rank`), each against ruby's answer.
class CExtObjectsAndClassesTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/encoding.h>
    #include <ruby/util.h>
    #include <time.h>

    static VALUE equal(VALUE self, VALUE a, VALUE b) { return rb_equal(a, b); }
    static VALUE frozen_error(VALUE self, VALUE obj) { rb_error_frozen_object(obj); return Qnil; }
    static VALUE obj_dup(VALUE self, VALUE obj) { return rb_obj_dup(obj); }
    static VALUE alloc(VALUE self, VALUE klass) { return rb_obj_alloc(klass); }
    static VALUE hide(VALUE self, VALUE obj) { return rb_obj_hide(obj) == obj ? Qtrue : Qfalse; }
    static VALUE freeze_inline(VALUE self, VALUE obj) { rb_obj_freeze_inline(obj); return obj; }
    static VALUE encoding(VALUE self, VALUE obj) { return rb_obj_encoding(obj); }
    static VALUE ivars(VALUE self, VALUE obj) {
      return rb_ary_new_from_args(3, rb_ivar_defined(obj, rb_intern("@a")), rb_ivar_defined(obj, rb_intern("@zz")),
                                  ULONG2NUM(rb_ivar_count(obj)));
    }
    static int each_ivar(ID key, VALUE val, st_data_t arg) {
      rb_ary_push((VALUE)arg, rb_assoc_new(ID2SYM(key), val));
      return RARRAY_LEN((VALUE)arg) >= 2 ? ST_STOP : ST_CONTINUE;
    }
    static VALUE ivar_foreach(VALUE self, VALUE obj) {
      VALUE out = rb_ary_new();
      rb_ivar_foreach(obj, each_ivar, (st_data_t)out);
      return out;
    }
    static VALUE cvar(VALUE self, VALUE klass) { return rb_cvar_get(klass, rb_intern("@@count")); }
    static VALUE extend(VALUE self, VALUE obj, VALUE mod) { rb_extend_object(obj, mod); return obj; }
    static VALUE singleton(VALUE self, VALUE obj) { return rb_singleton_class(obj); }
    static VALUE boundp(VALUE self, VALUE klass, VALUE name, VALUE ex) {
      return INT2FIX(rb_method_boundp(klass, rb_intern(StringValueCStr(name)), NUM2INT(ex)));
    }
    static VALUE arity(VALUE self, VALUE obj, VALUE name) { return INT2FIX(rb_obj_method_arity(obj, rb_intern(StringValueCStr(name)))); }
    static VALUE apply(VALUE self, VALUE recv, VALUE name, VALUE args) { return rb_apply(recv, rb_intern(StringValueCStr(name)), args); }
    static VALUE check_type(VALUE self, VALUE v) { Check_Type(v, T_STRING); return Qtrue; }
    static VALUE gv(VALUE self, VALUE v) {
      rb_gv_set("$from_c", v);
      return rb_ary_new_from_args(2, rb_gv_get("from_c"), rb_gv_get("$from_c"));
    }
    static VALUE marshal(VALUE self, VALUE obj) { return rb_marshal_load(rb_marshal_dump(obj, Qnil)); }
    static VALUE cmpint(VALUE self, VALUE a, VALUE b) { return INT2FIX(rb_cmpint(rb_funcall(a, rb_intern("<=>"), 1, b), a, b)); }

    static VALUE class_id(VALUE self, VALUE super) {
      VALUE k = rb_define_class_id(rb_intern("Anon"), super);
      VALUE m = rb_define_module_id(rb_intern("AnonMod"));
      return rb_ary_new_from_args(4, rb_class_superclass(k), rb_obj_class(m), rb_mod_name(k), rb_mod_name(m));
    }
    static VALUE path2class(VALUE self, VALUE path) { return rb_path2class(StringValueCStr(path)); }
    static VALUE class_name(VALUE self, VALUE klass) { return rb_class_name(klass); }
    static VALUE prepend(VALUE self, VALUE klass, VALUE mod) { rb_prepend_module(klass, mod); return rb_mod_ancestors(klass); }
    static VALUE attrs(VALUE self, VALUE klass) { rb_define_attr(klass, "both", 1, 1); rb_define_attr(klass, "reader", 1, 0); return Qnil; }
    static VALUE const_defined(VALUE self, VALUE klass, VALUE name) {
      ID id = rb_intern(StringValueCStr(name));
      return rb_ary_new_from_args(2, INT2FIX(rb_const_defined(klass, id)), INT2FIX(rb_const_defined_at(klass, id)));
    }
    static VALUE alloc_func(VALUE self, VALUE klass) { return rb_get_alloc_func(klass) ? Qtrue : Qfalse; }
    static VALUE c_alloc(VALUE klass) { return rb_obj_alloc(rb_cObject); }
    // Ruby's members Array is hidden from Ruby: C copies what it holds.
    static VALUE members(VALUE self, VALUE klass) {
      VALUE names = rb_struct_s_members(klass), out = rb_ary_new();
      for (long i = 0; i < RARRAY_LEN(names); i++) rb_ary_push(out, RARRAY_AREF(names, i));
      return out;
    }

    static VALUE id_names(VALUE self) {
      ID id = rb_intern("some_name");
      const char *a = rb_id2name(id), *b = rb_id2name(id);
      return rb_ary_new_from_args(4, rb_str_new_cstr(a), a == b ? Qtrue : Qfalse, rb_id2str(id), rb_id2str(id) == rb_id2str(id) ? Qtrue : Qfalse);
    }
    static VALUE check_symbol(VALUE self, VALUE s) { return rb_check_symbol_cstr(RSTRING_PTR(s), RSTRING_LEN(s), rb_enc_get(s)); }

    static VALUE arrays(VALUE self, VALUE ary) {
      VALUE copy = rb_ary_dup(ary);
      VALUE out = rb_ary_new();
      rb_ary_push(out, rb_ary_includes(ary, INT2FIX(2)));
      rb_ary_push(out, rb_ary_includes(ary, INT2FIX(9)));
      rb_ary_push(out, rb_ary_join(ary, rb_str_new_cstr("-")));
      rb_ary_push(out, rb_ary_subseq(ary, 1, 2));
      rb_ary_push(out, rb_ary_to_ary(INT2FIX(5)));
      rb_ary_push(out, rb_ary_to_ary(ary) == ary ? Qtrue : Qfalse);
      VALUE idx[2] = { INT2FIX(0), INT2FIX(2) };
      rb_ary_push(out, rb_ary_aref(2, idx, ary));
      rb_ary_push(out, rb_ary_shift(copy));
      rb_ary_resize(copy, 5);
      rb_ary_push(out, rb_ary_dup(copy));
      rb_ary_resize(copy, 1);
      rb_ary_push(out, copy);
      return out;
    }
    static VALUE hashes(VALUE self) {
      VALUE h = rb_hash_new();
      VALUE pairs[4] = { ID2SYM(rb_intern("a")), INT2FIX(1), ID2SYM(rb_intern("b")), INT2FIX(2) };
      rb_hash_bulk_insert(4, pairs, h);
      rb_hash_set_ifnone(h, rb_str_new_cstr("none"));
      return rb_ary_new_from_args(4, h, rb_hash_aref(h, INT2FIX(99)), rb_hash_fetch(h, ID2SYM(rb_intern("b"))),
                                  rb_hash_start(1) == rb_hash_start(1) ? Qtrue : Qfalse);
    }
    static VALUE fetch_missing(VALUE self, VALUE h) { return rb_hash_fetch(h, INT2FIX(1)); }
    static VALUE strings(VALUE self, VALUE s) {
      char *end;
      double d = ruby_strtod("2.5rest", &end);
      return rb_ary_new_from_args(6, rb_str_subseq(s, 1, 3), rb_external_str_new("ext", 3), rb_float_new(rb_cstr_to_dbl("1.25", 1)),
                                  rb_float_new(rb_cstr_to_dbl("3.5abc", 0)), rb_ary_new_from_args(2, rb_float_new(d), rb_str_new_cstr(end)),
                                  rb_cstr_to_inum("ff", 16, 0));
    }
    static VALUE fs_encoding(VALUE self) { return rb_enc_from_encoding(rb_filesystem_encoding()); }
    static VALUE numbers(VALUE self) {
      return rb_ary_new_from_args(3, rb_big2str(rb_int2big(255), 16), rb_complex_new(INT2FIX(1), INT2FIX(2)),
                                  rb_rational_new(INT2FIX(6), INT2FIX(4)));
    }
    static VALUE gc_toggle(VALUE self) {
      VALUE was = rb_gc_disable();
      VALUE again = rb_gc_disable();
      rb_gc_enable();
      return rb_ary_new_from_args(2, was, again);
    }
    static VALUE times(VALUE self) {
      struct timespec ts = { 1700000000, 123456789 };
      return rb_ary_new_from_args(4, rb_funcall(rb_time_new(1700000000, 250000), rb_intern("usec"), 0),
                                  rb_funcall(rb_time_nano_new(1700000000, 5), rb_intern("nsec"), 0),
                                  rb_funcall(rb_time_timespec_new(&ts, INT_MAX - 1), rb_intern("inspect"), 0),
                                  rb_funcall(rb_time_timespec_new(&ts, 3600), rb_intern("inspect"), 0));
    }
    static VALUE reopen(VALUE self, VALUE outer) {
      return rb_assoc_new(rb_define_class_under(outer, "Hidden", rb_cObject), rb_define_module_under(outer, "HiddenMod"));
    }
    static VALUE substr(VALUE self, VALUE s, VALUE beg, VALUE len) { return rb_str_substr(s, NUM2LONG(beg), NUM2LONG(len)); }
    static VALUE timespec(VALUE self, VALUE t) {
      struct timespec ts = rb_time_timespec(t);
      return rb_ary_new_from_args(2, LONG2NUM(ts.tv_sec), LONG2NUM(ts.tv_nsec));
    }
    static VALUE globals(VALUE self) {
      return rb_ary_new_from_args(5, rb_cThread, rb_mErrno, rb_eSysStackError, rb_eSignal, rb_mProcess);
    }

    void Init_objs(void) {
      VALUE m = rb_define_module("Objs");
      rb_define_module_function(m, "equal", equal, 2);
      rb_define_module_function(m, "frozen_error", frozen_error, 1);
      rb_define_module_function(m, "dup", obj_dup, 1);
      rb_define_module_function(m, "alloc", alloc, 1);
      rb_define_module_function(m, "hide", hide, 1);
      rb_define_module_function(m, "freeze_inline", freeze_inline, 1);
      rb_define_module_function(m, "encoding", encoding, 1);
      rb_define_module_function(m, "ivars", ivars, 1);
      rb_define_module_function(m, "ivar_foreach", ivar_foreach, 1);
      rb_define_module_function(m, "cvar", cvar, 1);
      rb_define_module_function(m, "extend", extend, 2);
      rb_define_module_function(m, "singleton", singleton, 1);
      rb_define_module_function(m, "boundp", boundp, 3);
      rb_define_module_function(m, "arity", arity, 2);
      rb_define_module_function(m, "apply", apply, 3);
      rb_define_module_function(m, "check_type", check_type, 1);
      rb_define_module_function(m, "gv", gv, 1);
      rb_define_module_function(m, "marshal", marshal, 1);
      rb_define_module_function(m, "cmpint", cmpint, 2);
      rb_define_module_function(m, "class_id", class_id, 1);
      rb_define_module_function(m, "path2class", path2class, 1);
      rb_define_module_function(m, "class_name", class_name, 1);
      rb_define_module_function(m, "prepend", prepend, 2);
      rb_define_module_function(m, "attrs", attrs, 1);
      rb_define_module_function(m, "const_defined", const_defined, 2);
      rb_define_module_function(m, "alloc_func", alloc_func, 1);
      rb_define_module_function(m, "members", members, 1);
      rb_define_module_function(m, "id_names", id_names, 0);
      rb_define_module_function(m, "check_symbol", check_symbol, 1);
      rb_define_module_function(m, "arrays", arrays, 1);
      rb_define_module_function(m, "hashes", hashes, 0);
      rb_define_module_function(m, "fetch_missing", fetch_missing, 1);
      rb_define_module_function(m, "strings", strings, 1);
      rb_define_module_function(m, "fs_encoding", fs_encoding, 0);
      rb_define_module_function(m, "numbers", numbers, 0);
      rb_define_module_function(m, "gc_toggle", gc_toggle, 0);
      rb_define_module_function(m, "times", times, 0);
      rb_define_module_function(m, "reopen", reopen, 1);
      rb_define_module_function(m, "substr", substr, 3);
      rb_define_module_function(m, "timespec", timespec, 1);
      rb_define_module_function(m, "globals", globals, 0);
      VALUE allocated = rb_define_class_under(m, "Allocated", rb_cObject);
      rb_define_alloc_func(allocated, c_alloc);
    }
  C

  PROGRAM = <<~'RUBY'
    require "objs"

    def show(label)
      p [label, yield]
    rescue => e
      p [label, e.class, e.message]
    end

    Point = Struct.new(:x, :y)
    class Counter
      @@count = 3
      def initialize = (@a = 1; @b = "two"; @c = :three)
      def two(a, b = 1) = a
    end
    module Mixin
      def mixed = :mixed
    end
    module Front
      def greet = "front #{super}"
    end
    class Greeter
      def greet = "hello"
      private def secret = 1
    end

    show(:equal) { [Objs.equal(1, 1.0), Objs.equal("a", "a"), Objs.equal(:a, "a"), Objs.equal(nil, nil)] }
    show(:frozen_error) { Objs.frozen_error([1, 2]) }
    show(:frozen_error_string) { Objs.frozen_error("str") }
    show(:dup) { a = [1, [2]]; d = Objs.dup(a); [d, d.equal?(a), d[1].equal?(a[1])] }
    show(:alloc) { o = Objs.alloc(Counter); [o.class, o.instance_variables] }
    show(:alloc_none) { Objs.alloc(Integer) }
    show(:hide) { Objs.hide(Object.new) }
    show(:freeze_inline) { Objs.freeze_inline(+"x").frozen? }
    show(:encoding) { [Objs.encoding("a"), Objs.encoding("a".b), Objs.encoding(:sym)] }
    show(:encoding_none) { Objs.encoding(1) }
    show(:ivars) { Objs.ivars(Counter.new) }
    show(:ivar_foreach) { Objs.ivar_foreach(Counter.new) }
    show(:cvar) { Objs.cvar(Counter) }
    show(:cvar_missing) { Objs.cvar(Greeter) }
    show(:extend) { o = Objs.extend(Object.new, Mixin); [o.mixed, o.singleton_class.include?(Mixin)] }
    show(:singleton) { o = Object.new; [Objs.singleton(o) == o.singleton_class, Objs.singleton(Greeter) == Greeter.singleton_class] }
    show(:boundp) { [Objs.boundp(Greeter, "greet", 1), Objs.boundp(Greeter, "secret", 1), Objs.boundp(Greeter, "secret", 0), Objs.boundp(Greeter, "nope", 0)] }
    show(:arity) { [Objs.arity(Counter.new, "two"), Objs.arity("s", "upcase"), Objs.arity([], "push")] }
    show(:apply) { args = [3, 4]; [Objs.apply(1, "+", [2]), Objs.apply(Greeter.new, "secret", []), Objs.apply([1, 2], "push", args), args] }
    show(:check_type) { Objs.check_type("s") }
    show(:check_type_bad) { Objs.check_type(1) }
    show(:gv) { Objs.gv(42) }
    show(:marshal) { Objs.marshal([1, "two", { three: 3.0 }, Point.new(1, 2)]) }
    show(:cmpint) { [Objs.cmpint(1, 2), Objs.cmpint(2, 2), Objs.cmpint("b", "a"), Objs.cmpint(2**70, 1)] }
    show(:cmpint_nil) { Objs.cmpint(1, "a") }

    show(:class_id) { Objs.class_id(Counter) }
    show(:class_id_object) { Objs.class_id(Object)[0] }
    show(:path2class) { [Objs.path2class("Counter"), Objs.path2class("Objs::Allocated"), Objs.path2class("Comparable")] }
    show(:path2class_missing) { Objs.path2class("No::Such") }
    show(:path2class_missing_last) { Objs.path2class("Counter::Nope") }
    show(:path2class_missing_one) { Objs.path2class("Nope") }
    show(:path2class_through_value) { Objs.path2class("RUBY_VERSION::X") }
    show(:path2class_not_class) { Objs.path2class("RUBY_VERSION") }
    show(:class_name) { [Objs.class_name(Counter), Objs.class_name(Objs::Allocated), Objs.class_name(Counter.new.singleton_class)] }
    show(:prepend) { Objs.prepend(Greeter, Front).first(3).push(Greeter.new.greet) }
    show(:attrs) do
      k = Class.new
      Objs.attrs(k)
      o = k.new
      o.both = 5
      [o.both, o.respond_to?(:reader), o.respond_to?(:reader=)]
    end
    show(:const_defined) { [Objs.const_defined(Counter, "Comparable"), Objs.const_defined(Objs, "Allocated"), Objs.const_defined(Objs, "Nope")] }
    show(:alloc_func) { [Objs.alloc_func(Objs::Allocated), Objs.alloc_func(Class.new(Objs::Allocated)), Objs.alloc_func(Counter)] }
    show(:members) { Objs.members(Point) }

    show(:id_names) { Objs.id_names }
    show(:check_symbol) { [Objs.check_symbol("zq_never_named_" + "x"), Objs.check_symbol("café_zq_" + "y"), Objs.check_symbol("puts"), Objs.check_symbol("zq_named"), :zq_named] }
    show(:arrays) { Objs.arrays([1, 2, 3, 4]) }
    show(:hashes) { Objs.hashes }
    show(:fetch_missing) { Objs.fetch_missing({}) }
    show(:strings) { Objs.strings("héllo") }
    show(:fs_encoding) { Objs.fs_encoding }
    show(:numbers) { Objs.numbers }
    show(:gc_toggle) { Objs.gc_toggle }
    show(:times) { Objs.times }
    show(:timespec) { [Objs.timespec(Time.at(1_700_000_000, 123_456_789, :nsec)), Objs.timespec(42), Objs.timespec(1.5), Objs.timespec(Time.at(-1, 5, :nsec))] }
    show(:timespec_bad) { Objs.timespec("x") }
    show(:reopen_private) do
      outer = Module.new
      outer.const_set(:Hidden, Class.new)
      outer.const_set(:HiddenMod, Module.new)
      outer.send(:private_constant, :Hidden, :HiddenMod)
      Objs.reopen(outer) == [outer.const_get(:Hidden), outer.const_get(:HiddenMod)]
    end
    show(:substr) { [Objs.substr("héllo", 1, 3), Objs.substr("abc", -2, 5), Objs.substr("abc", 4, 1), Objs.substr("abc", 0, -1)] }
    show(:globals) { Objs.globals }
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("objs", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
