module Zr::Kern
  # A guard that stops a method from entering itself again on the same
  # object, as `inspect` does on an Array that contains itself. This is
  # CRuby's rb_exec_recursive. A paired guard (rb_exec_recursive_paired)
  # is for a comparison: it finds a recursion only when the same two
  # objects come together again. The task keeps the active guards in one
  # flat Array. Each guard record is GUARD_ROW words: the object, the
  # method, and the paired object (undef for an unpaired guard).
  GUARD_ROW = 3

  # Whether `mid` on `obj` is already active, paired or not. If it is not,
  # this adds a guard record, which stays until `zr_guard_leave`.
  #: (value, word) -> bool
  def zr_guard_enter(obj, mid)
    zr_guard_enter_paired(obj, Machine.value(QUNDEF), mid)
  end

  # Whether `mid` on `obj` and `other` is already active. An unpaired
  # query (`other` undef) matches each guard on `obj`.
  #: (value, value, word) -> bool
  def zr_guard_enter_paired(obj, other, mid)
    t = zr_task()
    list = Task[t].guards
    if list == QNIL
      list = zr_ary_new(GUARD_ROW * 4)
      # Its rows hold undef for a guard with no pair, which no program can
      # read, so ObjectSpace does not give it out (a hidden object).
      RBasic[list].flags = RBasic[list].flags | FL_CONCEALED
      Task[t].guards = list
    end
    name = zr_sym(mid)
    i = 0
    while i < RArray[list].len
      if zr_ary_at(list, i) == obj && zr_ary_at(list, i + 1) == name && (other == QUNDEF || zr_ary_at(list, i + 2) == other)
        return true
      end
      i += GUARD_ROW
    end
    if other == QUNDEF && zr_guard_listed(Task[t].recursive, name, obj)
      return true
    end
    zr_ary_push(list, obj)
    zr_ary_push(list, name)
    zr_ary_push(list, other)
    false
  end

  # Whether the program listed `obj` under the method `name` in the
  # fiber's `:__recursive_key__` Hash, as pp's push_inspect_key does:
  # `hash[name][obj]`, which CRuby's recursive_check reads. Only an
  # identity Hash counts, so the lookup runs no Ruby code.
  #: (value, value, value) -> bool
  def zr_guard_listed(hash, name, obj)
    if zr_special_p(hash) || zr_type(hash) != T_HASH || (RBasic[hash].flags & FL_IDENTITY) == 0
      return false
    end
    list = zr_hash_lookup(hash, name)
    if zr_special_p(list) || zr_type(list) != T_HASH || (RBasic[list].flags & FL_IDENTITY) == 0
      return false
    end
    zr_hash_lookup(list, obj) != QUNDEF
  end

  # Removes the last guard record. Guards nest.
  #: (value, word) -> void
  def zr_guard_leave(obj, mid)
    list = Task[zr_task()].guards
    RArray[list].len = RArray[list].len - GUARD_ROW
  end

  # The guards as core primitives. `Primitive.zr_recursive_enter(self,
  # :inspect)` returns true inside a recursion.
  # `zr_recursive_enter_paired(self, other, :eql?)` returns true inside a
  # recursion on the same pair.
  #: (value, value) -> value
  def zr_recursive_enter(obj, name)
    zr_bool(zr_guard_enter(obj, zr_sym2id(name)))
  end

  #: (value, value, value) -> value
  def zr_recursive_enter_paired(obj, other, name)
    zr_bool(zr_guard_enter_paired(obj, other, zr_sym2id(name)))
  end

  #: (value, value) -> value
  def zr_recursive_leave(obj, name)
    zr_guard_leave(obj, zr_sym2id(name))
    Machine.value(QNIL)
  end

  # The fiber's `:__recursive_key__`, and its writer (threadptr_local_aset).
  #: () -> value
  def zr_recursive_hash
    Task[zr_task()].recursive
  end

  #: (value) -> value
  def zr_recursive_hash_set(hash)
    Task[zr_task()].recursive = hash
    hash
  end
end
