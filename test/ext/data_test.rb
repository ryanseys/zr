# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# A C extension's T_DATA objects and the collector: structs that hold
# Values and mark them, allocation functions, type checks, free functions
# during the run and at its end, roots that C registers, and Values that
# only C's stack holds. Each program also runs under ZR_GC_STRESS, where
# each allocation collects, and with ZR_GC_VERIFY, which checks each
# minor collection against a full trace: a Value that the collector
# cannot see from C dies there and shows as a freed cell.
class CExtDataTest < Minitest::Test
  SOURCE = <<~C
    #include <ruby.h>
    #include <stddef.h>
    #include <stdint.h>
    #include <unistd.h>

    /* A box keeps a Value, and its stores skip the write barrier. */
    struct box { VALUE held; };
    static void box_mark(void *p) { rb_gc_mark(((struct box *)p)->held); }
    static size_t box_size(const void *p) { return sizeof(struct box); }
    static const rb_data_type_t box_type = {
      "box", { box_mark, RUBY_TYPED_DEFAULT_FREE, box_size, }, 0, 0, RUBY_TYPED_FREE_IMMEDIATELY
    };
    static VALUE box_alloc(VALUE klass) {
      struct box *b;
      VALUE obj = TypedData_Make_Struct(klass, struct box, &box_type, b);
      b->held = Qnil;
      return obj;
    }
    static struct box *box_of(VALUE self) {
      struct box *b;
      TypedData_Get_Struct(self, struct box, &box_type, b);
      return b;
    }
    static VALUE box_init(VALUE self, VALUE v) { box_of(self)->held = v; return self; }
    static VALUE box_get(VALUE self) { return box_of(self)->held; }
    static VALUE box_fill(VALUE self, VALUE n) {
      VALUE digits = rb_funcallv(n, rb_intern("to_s"), 0, NULL);
      VALUE fresh = rb_str_new_cstr("fresh ");
      box_of(self)->held = rb_funcallv(fresh, rb_intern("+"), 1, &digits);
      return self;
    }

    /* A cell's stores go through the barrier, and a pair's references are
       an offset list that the collector reads itself. */
    struct cell { VALUE held; };
    static void cell_mark(void *p) { rb_gc_mark(((struct cell *)p)->held); }
    static const rb_data_type_t cell_type = {
      "cell", { cell_mark, RUBY_TYPED_DEFAULT_FREE, 0, }, 0, 0,
      RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
    };
    static VALUE cell_alloc(VALUE klass) {
      struct cell *c;
      VALUE obj = TypedData_Make_Struct(klass, struct cell, &cell_type, c);
      c->held = Qnil;
      return obj;
    }
    static VALUE cell_set(VALUE self, VALUE v) {
      struct cell *c;
      TypedData_Get_Struct(self, struct cell, &cell_type, c);
      RB_OBJ_WRITE(self, &c->held, v);
      return v;
    }
    static VALUE cell_get(VALUE self) {
      struct cell *c;
      TypedData_Get_Struct(self, struct cell, &cell_type, c);
      return c->held;
    }

    struct pair { long tag; VALUE left; VALUE right; };
    static const size_t pair_refs[] = { offsetof(struct pair, left), offsetof(struct pair, right), SIZE_MAX };
    static const rb_data_type_t pair_type = {
      "pair", { (RUBY_DATA_FUNC)(uintptr_t)pair_refs, RUBY_TYPED_DEFAULT_FREE, 0, }, 0, 0,
      RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_DECL_MARKING
    };
    static VALUE pair_new(VALUE klass, VALUE l, VALUE r) {
      struct pair *p;
      VALUE obj = TypedData_Make_Struct(klass, struct pair, &pair_type, p);
      RB_OBJ_WRITE(obj, &p->left, l);
      RB_OBJ_WRITE(obj, &p->right, r);
      return obj;
    }
    static VALUE pair_left(VALUE self) {
      struct pair *p;
      TypedData_Get_Struct(self, struct pair, &pair_type, p);
      return p->left;
    }
    static VALUE pair_right(VALUE self) {
      struct pair *p;
      TypedData_Get_Struct(self, struct pair, &pair_type, p);
      return p->right;
    }

    /* A loud object says when its free function runs. Its type does not
       free immediately, so ruby runs the function after the sweep. */
    static void loud_free(void *p) { write(1, "freed\\n", 6); ruby_xfree(p); }
    static const rb_data_type_t loud_type = { "loud", { 0, loud_free, 0, }, 0, 0, 0 };
    static VALUE loud_alloc(VALUE klass) {
      long *n;
      return TypedData_Make_Struct(klass, long, &loud_type, n);
    }

    /* An untyped one, made the old way. */
    struct legacy { VALUE held; };
    static void legacy_mark(void *p) { rb_gc_mark(((struct legacy *)p)->held); }
    static VALUE legacy_new(VALUE self, VALUE v) {
      struct legacy *l = ALLOC(struct legacy);
      l->held = v;
      return rb_data_object_wrap(rb_cObject, l, legacy_mark, RUBY_DEFAULT_FREE);
    }
    static VALUE legacy_get(VALUE self, VALUE obj) { return ((struct legacy *)DATA_PTR(obj))->held; }

    static VALUE registered;
    static VALUE kept_forever;
    static VALUE get_registered(VALUE self) { return registered; }
    static VALUE get_kept(VALUE self) { return kept_forever; }

    /* `first` lives only in this frame or a register while the loop
       makes garbage. */
    static VALUE keep_on_stack(VALUE self, VALUE n) {
      VALUE first = rb_str_new_cstr("kept on the C stack");
      for (long i = 0; i < NUM2LONG(n); i++) rb_str_new_cstr("garbage garbage garbage garbage garbage");
      VALUE copy = rb_str_new(RSTRING_PTR(first), RSTRING_LEN(first));
      RB_GC_GUARD(first);
      return copy;
    }

    static VALUE wrap_plain(VALUE self, VALUE klass) {
      return rb_data_typed_object_wrap(klass, 0, &cell_type);
    }
    static VALUE define_alloc_on(VALUE self, VALUE mod) {
      rb_define_alloc_func(mod, box_alloc);
      return Qnil;
    }
    static VALUE is_box(VALUE self, VALUE obj) { return rb_typeddata_is_kind_of(obj, &box_type) ? Qtrue : Qfalse; }

    void Init_store(void) {
      VALUE m = rb_define_module("Store");
      VALUE box = rb_define_class_under(m, "Box", rb_cObject);
      rb_define_alloc_func(box, box_alloc);
      rb_define_method(box, "initialize", box_init, 1);
      rb_define_method(box, "get", box_get, 0);
      rb_define_method(box, "fill", box_fill, 1);
      VALUE cell = rb_define_class_under(m, "Cell", rb_cObject);
      rb_define_alloc_func(cell, cell_alloc);
      rb_define_method(cell, "set", cell_set, 1);
      rb_define_method(cell, "get", cell_get, 0);
      VALUE pair = rb_define_class_under(m, "Pair", rb_cObject);
      rb_undef_alloc_func(pair);
      rb_define_singleton_method(pair, "new", pair_new, 2);
      rb_define_method(pair, "left", pair_left, 0);
      rb_define_method(pair, "right", pair_right, 0);
      VALUE loud = rb_define_class_under(m, "Loud", rb_cObject);
      rb_define_alloc_func(loud, loud_alloc);
      rb_define_module_function(m, "legacy", legacy_new, 1);
      rb_define_module_function(m, "legacy_get", legacy_get, 1);
      rb_define_module_function(m, "registered", get_registered, 0);
      rb_define_module_function(m, "kept", get_kept, 0);
      rb_define_module_function(m, "keep_on_stack", keep_on_stack, 1);
      rb_define_module_function(m, "wrap_plain", wrap_plain, 1);
      rb_define_module_function(m, "define_alloc_on", define_alloc_on, 1);
      rb_define_module_function(m, "box?", is_box, 1);
      registered = rb_str_new_cstr("registered address");
      rb_gc_register_address(&registered);
      kept_forever = rb_str_new_cstr("marked forever");
      rb_gc_register_mark_object(kept_forever);
    }
  C

  # Plain, under stress, and under stress with each minor checked.
  RUNS = [{}, { "ZR_GC_STRESS" => "1" }, { "ZR_GC_STRESS" => "1", "ZR_GC_VERIFY" => "1" }].freeze

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("store", SOURCE)
  end

  # `lines` compares the lines in any order, for output whose order
  # depends on when a collection runs.
  def assert_same_as_ruby(program, lines: false)
    ruby, runs = Zr::Test::CExt.outputs_under(@ext, program, RUNS)
    shown = lines ? ->(out) { out.lines.sort } : :itself.to_proc
    RUNS.zip(runs).each do |env, zr|
      assert_equal [shown.(ruby.stdout), ruby.status], [shown.(zr.stdout), zr.status],
                   "zr's output differs from ruby's under #{env}\nzr stderr:\n#{zr.stderr}"
    end
  end

  def test_a_struct_keeps_the_values_that_its_mark_function_marks
    assert_same_as_ruby(<<~RUBY)
      require "store"
      boxes = Array.new(20) { |i| Store::Box.new("box \#{i}" * 3) }
      GC.start
      200.times { |i| "garbage \#{i}" * 4 }
      p boxes.map(&:get).first(3), boxes.last.get
      cell = Store::Cell.new
      cell.set("set once")
      GC.start
      p cell.get, Store::Pair.new("left", [:right]).then { [_1.left, _1.right] }
      p Store.legacy_get(Store.legacy("legacy" * 2))
      p Store.registered, Store.kept
      GC.start
      p Store.registered, Store.kept
    RUBY
  end

  # An old struct that C stores a new Value into, with no barrier: a
  # minor collection must trace the struct again.
  def test_an_old_struct_without_the_barrier_keeps_a_young_value
    assert_same_as_ruby(<<~RUBY)
      require "store"
      box = Store::Box.new(nil)
      cell = Store::Cell.new
      4.times { GC.start }
      results = []
      10.times do |i|
        box.fill(i)
        cell.set("cell \#{i}")
        300.times { |j| [j, j.to_s] }
        results << box.get << cell.get
      end
      p results.last(4)
    RUBY
  end

  def test_a_value_that_only_c_holds_lives
    assert_same_as_ruby(<<~RUBY)
      require "store"
      p Store.keep_on_stack(2000)
      p (1..3).map { Store.keep_on_stack(500) }.uniq
    RUBY
  end

  def test_types_and_allocators_are_checked_as_ruby_checks_them
    assert_same_as_ruby(<<~RUBY)
      require "store"
      def show
        p yield
      rescue => e
        p [e.class, e.message]
      end
      show { Store::Box.instance_method(:get).bind_call(Object.new) }
      show { Store::Box.instance_method(:get).bind_call(Store::Cell.new) }
      show { Store::Box.instance_method(:get).bind_call(nil) }
      show { Store.box?(Store::Box.new(1)) }
      show { Store.box?(Store::Cell.new) }
      show { Store.box?(1) }
      show { Store::Pair.allocate }
      show { Store.define_alloc_on(Comparable) }
      class Plain; end
      show { Store.wrap_plain(Plain).class }
      show { Plain.new }
      show { Store::Box.new(:orig).dup.get }
      show { Store::Box.new(:orig).clone.get }
      class Sub < Store::Box
        def initialize(v) = super(v.to_s * 2)
      end
      show { Sub.new(:ab).get }
      show { Store::Box.new(1).frozen? }
    RUBY
  end

  # Which free functions run at the collection and which at the end
  # depends on what ruby's conservative scan of its own stack keeps, so
  # only the number of them must match.
  def test_free_functions_run_after_the_sweep_and_at_the_end
    assert_same_as_ruby(<<~RUBY, lines: true)
      require "store"
      $stdout.sync = true
      def make = Store::Loud.new
      3.times { make }
      kept = make
      puts "made"
      GC.start
      100.times { "x" * 10 }
      puts "end"
    RUBY
  end
end
