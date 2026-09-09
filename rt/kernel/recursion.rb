# A guard against a method re-entering itself on the same object, as
# `inspect` on an Array that holds itself would: CRuby's
# rb_exec_recursive. The task keeps the (object, method) pairs in
# flight as one flat Array.

# Whether `mid` on `obj` is already in flight; when it is not, the
# pair is recorded until `zr_guard_leave`.
sig [Value, Word] => Bool
machine def zr_guard_enter(obj, mid)
  t = zr_task()
  list = Task.guards(t)
  if list == QNIL
    list = zr_ary_new(8)
    Task.set_guards(t, list)
  end
  name = zr_sym(mid)
  i = 0
  while i < RArray.len(list)
    if zr_ary_at(list, i) == obj && zr_ary_at(list, i + 1) == name
      return true
    end
    i += 2
  end
  zr_ary_push(list, obj)
  zr_ary_push(list, name)
  false
end

sig [Value, Word] => Void
machine def zr_guard_leave(obj, mid)
  list = Task.guards(zr_task())
  RArray.set_len(list, RArray.len(list) - 2)
end

# The two as core primitives: `Primitive.zr_recursive_enter(self, :inspect)`
# answers true inside a recursion.
sig [Value, Value] => Value
machine def zr_recursive_enter(obj, name)
  zr_bool(zr_guard_enter(obj, zr_sym2id(name)))
end

sig [Value, Value] => Value
machine def zr_recursive_leave(obj, name)
  zr_guard_leave(obj, zr_sym2id(name))
  Machine.value(QNIL)
end
