module Zr::Kern
  # T_DATA: an object that wraps a C extension's struct, in CRuby's
  # RTypedData layout, so the extension's inline DATA_PTR and
  # RTYPEDDATA_* read it as they read ruby's. Every T_DATA is typed: it
  # points at its type, a rb_data_type_t (DataType) in the extension's
  # data, whose functions mark, free and size the struct. The collector
  # calls them (zr_mark_data, zr_release_data) through zr_call_c_in_gc.
  T_DATA = 12
  # A T_DATA or an Array whose stores C makes without the write barrier
  # (zr_unprotected_add). It is on the unprotected list.
  FL_UNPROTECTED = 1 << 38

  class RTypedData < Layout
    attr_reader :basic #: RBasic
    # CRuby keeps a T_DATA's ivars in this object; zr keeps them in the
    # generic table, as for a String, so it is always 0.
    attr_accessor :fields_obj #: value
    # The type's address, with TYPED_DATA_EMBEDDED in its low bit when
    # the struct is in the cell at `data`.
    attr_accessor :type #: word
    attr_accessor :data #: ptr
  end

  # rb_data_type_t, which the extension defines. Its function table ends
  # with handle_weak_references and seven reserved words, which must be
  # zero; the header's inline type check reads `parent` past them.
  class DataType < Layout
    attr_accessor :wrap_struct_name #: ptr
    attr_accessor :dmark #: ptr
    attr_accessor :dfree #: ptr
    attr_accessor :dsize #: ptr
    attr_accessor :dcompact #: ptr
    attr_accessor :handle_weak_references #: ptr
    attr_accessor :reserved1 #: ptr
    attr_accessor :reserved2 #: ptr
    attr_accessor :reserved3 #: ptr
    attr_accessor :reserved4 #: ptr
    attr_accessor :reserved5 #: ptr
    attr_accessor :reserved6 #: ptr
    attr_accessor :reserved7 #: ptr
    attr_accessor :parent #: ptr
    attr_accessor :data #: ptr
    attr_accessor :flags #: word
  end

  TYPED_DATA_EMBEDDED = 1
  # DataType#flags: RUBY_TYPED_FREE_IMMEDIATELY, RUBY_TYPED_EMBEDDABLE,
  # RUBY_TYPED_THREAD_SAFE_FREE (ruby 4.1: a dfree that any thread may
  # run, which implies RUBY_TYPED_FREE_IMMEDIATELY),
  # RUBY_TYPED_WB_PROTECTED (RUBY_FL_WB_PROTECTED) and
  # RUBY_TYPED_DECL_MARKING (RUBY_FL_USER2).
  TYPED_FREE_IMMEDIATELY = 1
  TYPED_EMBEDDABLE = 2
  TYPED_THREAD_SAFE_FREE = 4
  # The flags with which dfree runs as the collector sweeps the object.
  TYPED_FREES_NOW = 5
  TYPED_WB_PROTECTED = 1 << 5
  TYPED_DECL_MARKING = 1 << 14
  # RUBY_DEFAULT_FREE, a free function that is ruby_xfree, and
  # RUBY_REF_END, the end of a declarative mark's offset list.
  DATA_DEFAULT_FREE = 0 - 1
  DATA_REF_END = 0 - 1

  # The type of the typed T_DATA `v` (RTYPEDDATA_TYPE).
  #: (value) -> ptr
  def zr_data_type(v)
    Machine.ptr(RTypedData[v].type & (0 - 2))
  end

  # The struct of T_DATA `v` (RTYPEDDATA_GET_DATA, DATA_PTR).
  #: (value) -> ptr
  def zr_data_ptr(v)
    if (RTypedData[v].type & TYPED_DATA_EMBEDDED) != 0
      return Machine.ptr(v) + 32
    end
    RTypedData[v].data
  end

  # Marks what T_DATA `v`'s struct refers to, as rb_gc_mark_children
  # does: through the offsets that a declarative type lists, or through
  # its mark function, which calls rb_gc_mark.
  #: (value) -> void
  def zr_mark_data(v)
    data = zr_data_ptr(v)
    if data == 0
      return
    end
    type = zr_data_type(v)
    if (DataType[type].flags & TYPED_DECL_MARKING) != 0
      zr_mark_data_refs(data, DataType[type].dmark)
      return
    end
    mark = DataType[type].dmark
    if mark != 0
      zr_call_c_in_gc(mark, data, Machine.ptr(0))
    end
  end

  # Marks the Value at each offset in `data` that the list at `offsets`
  # gives, up to RUBY_REF_END.
  #: (ptr, ptr) -> void
  def zr_mark_data_refs(data, offsets)
    offset = Machine.load64(offsets, 0)
    while offset != DATA_REF_END
      zr_mark(Machine.value(Machine.load64(data + offset, 0)))
      offsets += 8
      offset = Machine.load64(offsets, 0)
    end
  end

  # Frees T_DATA `v`'s struct as the sweep frees `v`, as CRuby's
  # rb_data_free does: RUBY_DEFAULT_FREE is ruby_xfree, a type that frees
  # immediately runs its free function now, and any other free function
  # runs at the next safe point (zr_data_frees_run), where it may call
  # ruby, as CRuby runs a zombie's.
  #: (value) -> void
  def zr_release_data(v)
    data = zr_data_ptr(v)
    if data == 0
      return
    end
    type = zr_data_type(v)
    free = DataType[type].dfree
    embedded = (RTypedData[v].type & TYPED_DATA_EMBEDDED) != 0
    now = (DataType[type].flags & TYPED_FREES_NOW) != 0
    # An embeddable type that did not fit in the cell owns its malloc'd
    # struct too.
    owned = (DataType[type].flags & TYPED_EMBEDDABLE) != 0 && !embedded
    if embedded && free == Machine.ptr(DATA_DEFAULT_FREE)
      return
    end
    if free == 0
      return
    end
    if free == Machine.ptr(DATA_DEFAULT_FREE)
      zr_xfree(data)
    elsif now
      zr_call_c_in_gc(free, data, Machine.ptr(0))
      if owned
        zr_xfree(data)
      end
    else
      zr_data_free_later(free, data)
    end
  end

  # The free functions that wait for a safe point: pairs of words, the
  # function and its struct.
  #: () -> ptr
  def zr_data_frees
    Machine.static(:data_frees, WeakList.size)
  end

  #: (ptr, ptr) -> void
  def zr_data_free_later(free, data)
    q = zr_data_frees()
    zr_weak_list_push(q, Machine.value(Machine.word(free)))
    zr_weak_list_push(q, Machine.value(Machine.word(data)))
    zr_poll_set()
  end

  # Runs the free functions that the sweeps queued. Each one comes off the
  # queue before it runs, because one that runs Ruby can collect and queue
  # more, or reach a safe point that runs the queue. An error that one
  # raises is dropped, as CRuby drops a zombie's.
  #: () -> void
  def zr_data_frees_run
    q = zr_data_frees()
    argv = Machine.slot(64)
    while WeakList[q].len > 0
      n = WeakList[q].len - 2
      WeakList[q].len = n
      free = Machine.ptr(Machine.load64(WeakList[q].ptr + (n * 8), 0))
      Machine.store64(argv, 0, Machine.load64(WeakList[q].ptr + ((n + 1) * 8), 0))
      if !zr_call_c_returned(free, argv, 1)
        Task[zr_task()].pending = Machine.value(QNIL)
      end
    end
  end

  # At the end of the program, each T_DATA that is still live frees its
  # struct, as CRuby's rb_objspace_call_finalizer frees them.
  #: () -> void
  def zr_data_free_all
    zr_data_frees_run()
    # The free functions that run now run as in a sweep: they may not
    # allocate or raise.
    h = zr_heap()
    Heap[h].collecting = 1
    Heap[h].slow = 1
    n = Heap[h].arenas
    a = 0
    while a < n
      base = zr_arena_at(a)
      first = zr_arena_first(base)
      bytes = ArenaHead[base].cell
      i = zr_arena_next_allocated(base, 0)
      while i < ARENA_CELLS
        v = Machine.value(first + (i * bytes))
        if (RBasic[v].flags & T_MASK) == T_DATA
          zr_data_free_now(v)
        end
        i = zr_arena_next_allocated(base, i + 1)
      end
      a += 1
    end
    Heap[h].collecting = 0
    zr_heap_slow_update()
    zr_data_frees_run()
  end

  # Frees `v`'s struct now and forgets it, so nothing frees it again.
  #: (value) -> void
  def zr_data_free_now(v)
    zr_release_data(v)
    if (RTypedData[v].type & TYPED_DATA_EMBEDDED) != 0
      RTypedData[v].type = RTypedData[v].type & (0 - 2)
    end
    RTypedData[v].data = 0
  end

  # The objects whose stores of Values C makes without the write barrier:
  # a T_DATA whose type is not RUBY_TYPED_WB_PROTECTED and that has a mark
  # function, and any object that rb_gc_writebarrier_unprotect names
  # (an Array whose RARRAY_PTR C took). A minor collection traces each old
  # one again, as if the barrier had remembered it (zr_mark_unprotected).
  # The list does not keep them alive.
  #: () -> ptr
  def zr_unprotected
    Machine.static(:unprotected, WeakList.size)
  end

  #: (value) -> void
  def zr_unprotected_add(v)
    if (RBasic[v].flags & FL_UNPROTECTED) == 0
      RBasic[v].flags = RBasic[v].flags | FL_UNPROTECTED
      zr_weak_list_push(zr_unprotected(), v)
    end
  end

  # Traces each old unprotected object: a minor collection marked it from
  # its age and does not trace it otherwise.
  #: () -> void
  def zr_mark_unprotected
    l = zr_unprotected()
    i = 0
    while i < WeakList[l].len
      v = Machine.value(Machine.load64(WeakList[l].ptr + (i * 8), 0))
      if zr_aged_p(v)
        Machine.store64(zr_marking(), 0, Machine.word(v))
        zr_mark(RBasic[v].klass)
        zr_mark_children(v)
        if (RBasic[v].flags & FL_EXIVAR) != 0
          zr_mark_ivtab(zr_exivar_tab(v))
        end
      end
      i += 1
    end
  end

  # Drops the unprotected objects that this collection did not mark,
  # before the sweep frees them.
  #: () -> void
  def zr_unprotected_prune
    l = zr_unprotected()
    kept = 0
    i = 0
    while i < WeakList[l].len
      w = Machine.load64(WeakList[l].ptr + (i * 8), 0)
      if zr_marked_p(Machine.value(w))
        Machine.store64(WeakList[l].ptr + (kept * 8), 0, w)
        kept += 1
      end
      i += 1
    end
    WeakList[l].len = kept
  end

  # The most functions that ruby_vm_at_exit keeps.
  CAPI_VM_AT_EXIT = 64

  # Runs the end proc `pair` of rb_set_end_proc: undef when it raised,
  # else nil.
  #: (value) -> value
  def zr_c_end_proc(pair)
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(zr_ary_at(pair, 1)))
    returned = zr_call_c_returned(Machine.ptr(zr_fix2long(zr_ary_at(pair, 0))), argv, 1)
    Machine.value(returned ? QNIL : QUNDEF)
  end

  # Runs the functions of ruby_vm_at_exit, the last first.
  #: () -> void
  def zr_c_vm_at_exit
    list = Machine.static(:capi_vm_at_exit, CAPI_VM_AT_EXIT * 8 + 8)
    argv = Machine.slot(64)
    Machine.store64(argv, 0, 0)
    n = Machine.load64(list, 0)
    while n > 0
      zr_call_c(Machine.ptr(Machine.load64(list + (n * 8), 0)), argv, 1)
      n -= 1
    end
    Machine.store64(list, 0, 0)
  end
end
