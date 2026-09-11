# A guard against a method re-entering itself on the same object, as
# `inspect` on an Array that holds itself would: CRuby's
# rb_exec_recursive. A paired guard, rb_exec_recursive_paired, is for a
# comparison: it is a recursion only when the same two objects meet
# again. The task keeps the guards in flight as one flat Array of
# GUARD_ROW words each: the object, the method, and the object paired
# with it (undef for an unpaired guard).
GUARD_ROW = 3

# Whether `mid` on `obj` is already in flight, paired or not; when it is
# not, the guard is recorded until `zr_guard_leave`.
sig [Value, Word] => Bool
machine def zr_guard_enter(obj, mid)
  zr_guard_enter_paired(obj, Machine.value(QUNDEF), mid)
end

# Whether `mid` on `obj` against `other` is already in flight; an
# unpaired query (`other` undef) matches any guard on `obj`.
sig [Value, Value, Word] => Bool
machine def zr_guard_enter_paired(obj, other, mid)
  t = zr_task()
  list = Task.guards(t)
  if list == QNIL
    list = zr_ary_new(GUARD_ROW * 4)
    Task.set_guards(t, list)
  end
  name = zr_sym(mid)
  i = 0
  while i < RArray.len(list)
    if zr_ary_at(list, i) == obj && zr_ary_at(list, i + 1) == name && (other == QUNDEF || zr_ary_at(list, i + 2) == other)
      return true
    end
    i += GUARD_ROW
  end
  zr_ary_push(list, obj)
  zr_ary_push(list, name)
  zr_ary_push(list, other)
  false
end

# The last guard entered goes: guards nest.
sig [Value, Word] => Void
machine def zr_guard_leave(obj, mid)
  list = Task.guards(zr_task())
  RArray.set_len(list, RArray.len(list) - GUARD_ROW)
end

# The guards as core primitives: `Primitive.zr_recursive_enter(self,
# :inspect)` answers true inside a recursion, and
# `zr_recursive_enter_paired(self, other, :eql?)` inside one on the same
# pair.
sig [Value, Value] => Value
machine def zr_recursive_enter(obj, name)
  zr_bool(zr_guard_enter(obj, zr_sym2id(name)))
end

sig [Value, Value, Value] => Value
machine def zr_recursive_enter_paired(obj, other, name)
  zr_bool(zr_guard_enter_paired(obj, other, zr_sym2id(name)))
end

sig [Value, Value] => Value
machine def zr_recursive_leave(obj, name)
  zr_guard_leave(obj, zr_sym2id(name))
  Machine.value(QNIL)
end
