# Boot and the C entry point. The program supplies `zr_toplevel`.
Machine.import "zr_toplevel", [] => Value


sig [] => Void
machine def zr_boot
  zr_heap_init()
  Task.set_top(zr_task(), 0)
  # The four that form a cycle come first, with no class; then each
  # gets Class as its class.
  zr_set_global(G_BASIC_OBJECT, zr_class_new(Machine.id(:BasicObject), Machine.value(QNIL)))
  zr_set_global(G_OBJECT, zr_class_new(Machine.id(:Object), zr_global(G_BASIC_OBJECT)))
  zr_set_global(G_MODULE, zr_class_new(Machine.id(:Module), zr_global(G_OBJECT)))
  zr_set_global(G_CLASS, zr_class_new(Machine.id(:Class), zr_global(G_MODULE)))
  i = G_BASIC_OBJECT
  while i <= G_CLASS
    RBasic.set_klass(zr_global(i), zr_global(G_CLASS))
    i += 1
  end
  zr_set_global(G_INTEGER, zr_class_new(Machine.id(:Integer), zr_global(G_OBJECT)))
  zr_set_global(G_STRING, zr_class_new(Machine.id(:String), zr_global(G_OBJECT)))
  zr_set_global(G_SYMBOL, zr_class_new(Machine.id(:Symbol), zr_global(G_OBJECT)))
  zr_set_global(G_NIL, zr_class_new(Machine.id(:NilClass), zr_global(G_OBJECT)))
  zr_set_global(G_TRUE, zr_class_new(Machine.id(:TrueClass), zr_global(G_OBJECT)))
  zr_set_global(G_FALSE, zr_class_new(Machine.id(:FalseClass), zr_global(G_OBJECT)))
  zr_set_global(G_MAIN, zr_alloc(T_OBJECT, zr_global(G_OBJECT)))
  # Kernel's methods sit on Object until modules arrive.
  zr_define_method(zr_global(G_OBJECT), Machine.id(:puts), Machine.addr(:zr_puts), 0 - 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:to_s), Machine.addr(:zr_int_to_s), 0)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:+), Machine.addr(:zr_int_plus), 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:-), Machine.addr(:zr_int_minus), 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:*), Machine.addr(:zr_int_mul), 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:/), Machine.addr(:zr_int_div), 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:%), Machine.addr(:zr_int_mod), 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:<), Machine.addr(:zr_int_lt), 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:<=), Machine.addr(:zr_int_le), 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:>), Machine.addr(:zr_int_gt), 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:>=), Machine.addr(:zr_int_ge), 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:==), Machine.addr(:zr_int_eq), 1)
  zr_define_method(zr_global(G_INTEGER), Machine.id(:!=), Machine.addr(:zr_int_ne), 1)
  zr_define_method(zr_global(G_STRING), Machine.id(:to_s), Machine.addr(:zr_str_to_s), 0)
  zr_define_method(zr_global(G_SYMBOL), Machine.id(:to_s), Machine.addr(:zr_sym_to_s), 0)
  zr_define_method(zr_global(G_NIL), Machine.id(:to_s), Machine.addr(:zr_nil_to_s), 0)
  zr_define_method(zr_global(G_TRUE), Machine.id(:to_s), Machine.addr(:zr_true_to_s), 0)
  zr_define_method(zr_global(G_FALSE), Machine.id(:to_s), Machine.addr(:zr_false_to_s), 0)
  zr_define_method(zr_global(G_OBJECT), Machine.id(:to_s), Machine.addr(:zr_obj_to_s), 0)
  zr_define_method(zr_global(G_BASIC_OBJECT), Machine.id(:!), Machine.addr(:zr_obj_not), 0)
end

sig [I32, Ptr] => I32
machine def main(argc, argv)
  zr_boot()
  zr_toplevel()
  0
end
