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
end
