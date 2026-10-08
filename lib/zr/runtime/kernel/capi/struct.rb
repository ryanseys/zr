module Zr::Kern
  # The C API's Structs, through Struct's own methods: a Struct here is
  # not CRuby's RStruct, so C reaches its members only through calls.

  # rb_struct_define: a new Struct class with the members whose C names
  # follow, up to a NULL; named Struct::<name>, or anonymous for NULL.
  #: (ptr) -> value
  def rb_struct_define(name)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    args = zr_ary_new(4)
    if name != 0
      zr_ary_push(args, zr_str_new(name, zr_cstr_len(name)))
    end
    zr_capi_struct_members(args, list)
    zr_c_result(zr_send(zr_core_class(Machine.id(:Struct)), Machine.id(:new), RArray[args].len, RArray[args].ptr))
  end

  # rb_struct_define_under: the same, as the constant `name` of `outer`.
  #: (value, ptr) -> value
  def rb_struct_define_under(outer, name)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    args = zr_ary_new(4)
    zr_capi_struct_members(args, list)
    klass = zr_c_result(zr_send(zr_core_class(Machine.id(:Struct)), Machine.id(:new), RArray[args].len, RArray[args].ptr))
    zr_c_result(zr_const_set(outer, zr_intern(name, zr_cstr_len(name)), klass))
  end

  # Appends the Symbol of each C string in `list`, up to a NULL.
  #: (value, ptr) -> void
  def zr_capi_struct_members(args, list)
    member = Machine.ptr(zr_va_next_word(list))
    while member != 0
      zr_ary_push(args, zr_sym(zr_intern(member, zr_cstr_len(member))))
      member = Machine.ptr(zr_va_next_word(list))
    end
  end

  # rb_struct_new: `klass.new(*values)`, with one Value for each member.
  #: (value) -> value
  def rb_struct_new(klass)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    members = zr_c_result(zr_send(klass, Machine.id(:members), 0, Machine.ptr(0)))
    n = RArray[members].len
    room = Machine.slot(CAPI_ARGS * 8)
    values = zr_capi_va_values(list, n, room)
    zr_c_result(zr_send(klass, Machine.id(:new), n, zr_capi_args_at(values, room)))
  end

  # rb_struct_aref and rb_struct_aset: `s[i]` and `s[i] = v`.
  #: (value, value) -> value
  def rb_struct_aref(s, i)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(s, Machine.id(:[]), i)
  end

  #: (value, value, value) -> value
  def rb_struct_aset(s, i, v)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(i))
    Machine.store64(args, 8, Machine.word(v))
    zr_c_result(zr_send(s, Machine.id(:[]=), 2, args))
  end

  # rb_struct_size: the member count, as an Integer.
  #: (value) -> value
  def rb_struct_size(s)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(s, Machine.id(:size), 0, Machine.ptr(0)))
  end

  # rb_struct_s_members: the member names of the Struct class `klass`, as
  # Symbols.
  #: (value) -> value
  def rb_struct_s_members(klass)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(klass, Machine.id(:members), 0, Machine.ptr(0)))
  end

  # rb_struct_alloc_noinit: a Struct of `klass` with no member set.
  #: (value) -> value
  def rb_struct_alloc_noinit(klass)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(klass, Machine.id(:allocate), 0, Machine.ptr(0)))
  end
end
