module Zr::Kern
  # The C API's Hashes. C reads a Hash only through these functions.

  # rb_hash_new: a new empty Hash.
  #: () -> value
  def rb_hash_new
    Machine.gates_enter
    zr_c_entered()
    zr_hash_new()
  end

  # rb_hash_new_capa: the same; the table grows as it needs.
  #: (word) -> value
  def rb_hash_new_capa(capa)
    Machine.gates_enter
    zr_c_entered()
    zr_hash_new()
  end

  # rb_hash_dup: a copy with the pairs, the default and the ivars, as
  # rb_scan_args copies the keywords.
  #: (value) -> value
  def rb_hash_dup(h)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_hash_dup_m(h))
  end

  # rb_hash_aref: `h[key]`, with the default for a missing key.
  #: (value, value) -> value
  def rb_hash_aref(h, key)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_hash_aref_m(h, key))
  end

  # rb_hash_aset: `h[key] = value`.
  #: (value, value, value) -> value
  def rb_hash_aset(h, key, value)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_hash_aset_m(h, key, value))
  end

  # rb_hash_lookup2: the value for `key`, or `missing` with no default.
  #: (value, value, value) -> value
  def rb_hash_lookup2(h, key, missing)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_hash_lookup(h, key, missing)
  end

  # rb_hash_lookup: the value for `key`, or nil.
  #: (value, value) -> value
  def rb_hash_lookup(h, key)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_hash_lookup(h, key, Machine.value(QNIL))
  end

  # rb_hash_delete: removes `key`, and gives its value or nil.
  #: (value, value) -> value
  def rb_hash_delete(h, key)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_hash_delete_m(h, key))
  end

  # rb_hash_size: the number of pairs, as an Integer.
  #: (value) -> value
  def rb_hash_size(h)
    Machine.gates_enter
    zr_c_entered()
    zr_fix(RHash[h].live)
  end

  # rb_hash_size_num: the number of pairs.
  #: (value) -> word
  def rb_hash_size_num(h)
    Machine.gates_enter
    zr_c_entered()
    RHash[h].live
  end

  #: (value, value, value) -> value
  def zr_capi_hash_lookup(h, key, missing)
    e = zr_hash_entry(h, key)
    if e == HASH_RAISED
      zr_c_unwind()
    end
    e == 0 ? missing : HEntry[e].value
  end

  # rb_hash_clear: removes every pair, and returns the Hash.
  #: (value) -> value
  def rb_hash_clear(h)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_hash_clear(h))
  end

  # rb_hash_freeze: freezes the Hash, and returns it.
  #: (value) -> value
  def rb_hash_freeze(h)
    Machine.gates_enter
    zr_c_entered()
    zr_obj_freeze(h, 0, Machine.ptr(0), Machine.value(QNIL), Machine.value(QNIL))
  end

  # rb_hash_foreach's answers from the C function (st.h).
  ST_CONTINUE = 0
  ST_STOP = 1
  ST_DELETE = 2
  ST_CHECK = 3

  # rb_hash_foreach: calls `fn(key, value, arg)` for each pair, in order.
  # The function's answer goes on, stops, or deletes the pair. While it
  # runs, a new key raises, as in `each`. `arg` is the C caller's word
  # (st_data_t), often the address of its own struct, so it is no root.
  #: (value, ptr, word) -> void
  def rb_hash_foreach(h, fn, arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_hash_foreach(h, fn, arg)
  end

  #: (value, ptr, word) -> void
  def zr_capi_hash_foreach(h, fn, arg)
    argv = Machine.slot(64)
    Machine.store64(argv, 16, arg)
    RHash[h].iter = RHash[h].iter + 1
    i = 0
    while i < RHash[h].len
      e = RHash[h].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        Machine.store64(argv, 0, Machine.word(HEntry[e].key))
        Machine.store64(argv, 8, Machine.word(HEntry[e].value))
        r = zr_call_c(fn, argv, 3)
        if r == QUNDEF
          RHash[h].iter = RHash[h].iter - 1
          zr_c_unwind()
        end
        answer = Machine.sword(Machine.i32(r))
        if answer == ST_STOP
          break
        end
        if answer == ST_DELETE
          zr_capi_hash_kill(h, RHash[h].entries + (i * HEntry.size))
        end
      end
      i += 1
    end
    RHash[h].iter = RHash[h].iter - 1
  end

  # Removes entry `e` of `h`, as a delete during a walk does: the entry
  # stays in its place, dead.
  #: (value, ptr) -> void
  def zr_capi_hash_kill(h, e)
    if HEntry[e].live == 0
      return
    end
    HEntry[e].live = 0
    HEntry[e].key = Machine.value(QNIL)
    HEntry[e].value = Machine.value(QNIL)
    RHash[h].live = RHash[h].live - 1
  end

  # rb_hash_set_ifnone: the Hash's default value, which `[]` gives for a
  # missing key; returns the Hash.
  #: (value, value) -> value
  def rb_hash_set_ifnone(hash, ifnone)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(hash, Machine.id(:default=), ifnone)
    hash
  end

  # rb_hash_fetch: `hash.fetch(key)`, KeyError for a missing key.
  #: (value, value) -> value
  def rb_hash_fetch(hash, key)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(hash, Machine.id(:fetch), key)
  end

  # rb_hash_bulk_insert: stores the `argc / 2` pairs of keys and values at
  # `argv`.
  #: (word, ptr, value) -> void
  def rb_hash_bulk_insert(argc, argv, hash)
    Machine.gates_enter
    zr_c_entered()
    i = 0
    while i + 1 < argc
      args = argv + (i * 8)
      zr_c_result(zr_send(hash, Machine.id(:[]=), 2, args))
      i += 2
    end
  end

  # rb_hash_start: the first step of a hash value from the seed `h`, which
  # rb_hash_uint and rb_hash_end go on from.
  #: (word) -> word
  def rb_hash_start(h)
    Machine.gates_enter
    zr_c_entered()
    h ^ Machine.word(0x9e3779b97f4a7c15)
  end
end
