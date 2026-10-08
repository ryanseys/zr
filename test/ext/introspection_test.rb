# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API that looks into ruby itself, as the rank's last lacking
# gems use it: a Hash's st table (rbtree3), the caller's Binding
# (binding_ninja), the caller's file and line, a walk of the heap, and
# the thread event hooks with their per-thread words (gvltools), each
# against ruby's answer.
class CExtIntrospectionTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/st.h>
    #include <ruby/thread.h>

    /* Not in the public headers: the gems that call them declare them. */
    void rb_objspace_each_objects(int (*callback)(void *, void *, size_t, void *), void *data);
    int rb_objspace_internal_object_p(VALUE obj);

    static int it_drop_odd(st_data_t key, st_data_t value, st_data_t arg) {
      return FIXNUM_P((VALUE)value) && (FIX2LONG((VALUE)value) & 1) ? ST_DELETE : ST_CONTINUE;
    }
    static int it_collect(st_data_t key, st_data_t value, st_data_t arg) {
      rb_ary_push((VALUE)arg, rb_assoc_new((VALUE)key, (VALUE)value));
      return ST_CONTINUE;
    }
    static int it_bump(st_data_t *key, st_data_t *value, st_data_t arg, int existing) {
      *value = existing ? (st_data_t)LONG2FIX(FIX2LONG((VALUE)*value) + 100) : (st_data_t)INT2FIX(-1);
      return ST_CONTINUE;
    }
    static VALUE it_table(VALUE self, VALUE hash) {
      st_table *t = RHASH_TBL(hash);
      VALUE out = rb_ary_new(), pairs = rb_ary_new();
      st_data_t value = 0, key;
      rb_ary_push(out, LONG2NUM(t->num_entries));
      rb_ary_push(out, INT2FIX(st_insert(t, (st_data_t)rb_str_new_cstr("new"), (st_data_t)INT2FIX(3))));
      rb_ary_push(out, INT2FIX(st_insert(t, (st_data_t)ID2SYM(rb_intern("a")), (st_data_t)INT2FIX(5))));
      rb_ary_push(out, st_lookup(t, (st_data_t)rb_str_new_cstr("new"), &value) ? (VALUE)value : Qfalse);
      rb_ary_push(out, st_lookup(t, (st_data_t)ID2SYM(rb_intern("missing")), &value) ? Qtrue : Qfalse);
      st_foreach(t, it_drop_odd, 0);
      rb_ary_push(out, INT2FIX(st_update(t, (st_data_t)ID2SYM(rb_intern("b")), it_bump, 0)));
      rb_ary_push(out, INT2FIX(st_update(t, (st_data_t)ID2SYM(rb_intern("z")), it_bump, 0)));
      key = (st_data_t)ID2SYM(rb_intern("z"));
      rb_ary_push(out, st_delete(t, &key, &value) ? (VALUE)value : Qfalse);
      st_foreach(t, it_collect, (st_data_t)pairs);
      rb_ary_push(out, pairs);
      rb_ary_push(out, LONG2NUM(t->num_entries));
      rb_ary_push(out, RHASH_TBL(hash) == t ? Qtrue : Qfalse);
      return out;
    }

    static VALUE it_binding(VALUE self) { return rb_binding_new(); }
    static VALUE it_where(VALUE self) {
      const char *file = rb_sourcefile();
      return rb_ary_new_from_args(2, file ? rb_str_new_cstr(file) : Qnil, INT2FIX(rb_sourceline()));
    }

    struct it_walk { VALUE probe; int seen; long stop_after; long visited; };
    static int it_visit(void *start, void *end, size_t stride, void *data) {
      struct it_walk *walk = data;
      for (VALUE v = (VALUE)start; v != (VALUE)end; v += stride) {
        if (RBASIC(v)->flags == 0 || rb_objspace_internal_object_p(v)) continue;
        if (v == walk->probe) walk->seen = 1;
        walk->visited++;
      }
      return walk->stop_after > 0 && walk->visited >= walk->stop_after;
    }
    static VALUE it_objects(VALUE self, VALUE probe, VALUE stop_after) {
      struct it_walk walk = { probe, 0, NUM2LONG(stop_after), 0 };
      rb_objspace_each_objects(it_visit, &walk);
      return rb_ary_new_from_args(2, walk.seen ? Qtrue : Qfalse, LONG2NUM(walk.visited));
    }

    static int it_counts[5];
    static rb_internal_thread_event_hook_t *it_hook;
    static rb_internal_thread_specific_key_t it_key;
    static void it_on_event(rb_event_flag_t event, const rb_internal_thread_event_data_t *data, void *counts) {
      for (int i = 0; i < 5; i++) if (event == (1u << i)) ((int *)counts)[i]++;
      if (event == RUBY_INTERNAL_THREAD_EVENT_RESUMED) {
        long n = (long)rb_internal_thread_specific_get(data->thread, it_key);
        rb_internal_thread_specific_set(data->thread, it_key, (void *)(n + 1));
      }
    }
    static VALUE it_hook_on(VALUE self) {
      it_hook = rb_internal_thread_add_event_hook(it_on_event, RUBY_INTERNAL_THREAD_EVENT_MASK, it_counts);
      return Qnil;
    }
    static VALUE it_hook_off(VALUE self) { return rb_internal_thread_remove_event_hook(it_hook) ? Qtrue : Qfalse; }
    static VALUE it_counts_of(VALUE self) {
      VALUE out = rb_ary_new();
      for (int i = 0; i < 5; i++) rb_ary_push(out, INT2FIX(it_counts[i]));
      return out;
    }
    static VALUE it_resumed(VALUE self, VALUE thread) {
      return LONG2NUM((long)rb_internal_thread_specific_get(thread, it_key));
    }

    void Init_introspection(void) {
      VALUE m = rb_define_module("Introspection");
      it_key = rb_internal_thread_specific_key_create();
      rb_define_module_function(m, "table", it_table, 1);
      rb_define_module_function(m, "binding", it_binding, 0);
      rb_define_module_function(m, "where", it_where, 0);
      rb_define_module_function(m, "objects", it_objects, 2);
      rb_define_module_function(m, "hook_on", it_hook_on, 0);
      rb_define_module_function(m, "hook_off", it_hook_off, 0);
      rb_define_module_function(m, "counts", it_counts_of, 0);
      rb_define_module_function(m, "resumed", it_resumed, 1);
    }
  C

  PROGRAM = <<~'RUBY'
    require "introspection"

    def show(label)
      p [label, yield]
    rescue StandardError => e
      p [label, e.class, e.message]
    end

    show(:table) do
      hash = { a: 1, b: 2, c: 3 }
      [Introspection.table(hash), hash]
    end
    show(:table_empty) do
      hash = {}
      [Introspection.table(hash), hash]
    end
    show(:table_frozen) { Introspection.table({ a: 1 }.freeze) }

    class Probe
      def look
        Introspection.binding
      end

      def where = Introspection.where

      def local
        x = 41
        b = Introspection.binding
        b.local_variable_set(:x, b.local_variable_get(:x) + 1)
        [x, b.local_variables]
      end
    end
    show(:binding) do
      probe = Probe.new
      b = probe.look
      [b.class, b.receiver.equal?(probe), File.basename(b.source_location[0]), b.source_location[1]]
    end
    show(:binding_eval) { Probe.new.look.receiver.class }
    show(:binding_local) { Probe.new.local }
    show(:where) do
      file, line = Probe.new.where
      [File.basename(file), line]
    end

    show(:objects) do
      probe = Object.new
      seen, all = Introspection.objects(probe, 0)
      # CRuby stops after the page where the callback said so: past three,
      # short of the whole heap.
      _, some = Introspection.objects(probe, 3)
      [seen, Introspection.objects(Object.new.freeze, 0)[0], some >= 3, some < all]
    end

    show(:hooks) do
      Introspection.hook_on
      threads = 2.times.map { |i| Thread.new { 3.times { Thread.pass }; i } }
      values = threads.map(&:value)
      resumed = threads.map { |thread| Introspection.resumed(thread) >= 1 }
      off = Introspection.hook_off
      started, ready, running, stopped, exited = Introspection.counts
      Thread.new {}.join
      [values, resumed, off, started, exited, ready >= 2, running >= 2, stopped >= 2, Introspection.counts[0]]
    end
    show(:gc) { 20.times.map { Introspection.table({ x: 1, y: 2 }) }.uniq }
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("introspection", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
