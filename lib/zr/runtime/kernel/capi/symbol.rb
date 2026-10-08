module Zr::Kern
  # CRuby's ID, as C code holds it. An ID is zr's symbol id plus
  # C_ID_BASE: so 0 stays "no ID", as rb_check_id answers it, and the
  # codes below the base are free for an operator that C writes as its
  # character (`rb_funcall(x, '+', 1, y)`), as CRuby's operator IDs are.
  C_ID_BASE = 1024

  # The C ID of zr's symbol id `id`.
  #: (word) -> word
  def zr_capi_id(id)
    id + C_ID_BASE
  end

  # zr's symbol id of the C ID `id`: an ID that this API gave, or a
  # character, which names the operator of that one character.
  #: (word) -> word
  def zr_capi_mid(id)
    if id >= C_ID_BASE
      return id - C_ID_BASE
    end
    if id > 0 && id < 128
      ch = Machine.slot(8)
      Machine.store8(ch, 0, Machine.i8(id))
      return zr_intern(ch, 1)
    end
    zr_bug(Machine.bytes("[BUG] a C extension gave an ID that no rb_intern made\n"), 54)
    0
  end

  # rb_intern: the ID of the C string `name`.
  #: (ptr) -> word
  def rb_intern(name)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_id(zr_intern(name, zr_cstr_len(name)))
  end

  # rb_intern2: the ID of the `len` bytes at `name`. The rb_intern macro
  # calls this with a literal's length.
  #: (ptr, word) -> word
  def rb_intern2(name, len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_id(zr_intern(name, len))
  end

  # rb_id2sym: the Symbol of an ID.
  #: (word) -> value
  def rb_id2sym(id)
    Machine.gates_enter
    zr_c_entered()
    zr_sym(zr_capi_mid(id))
  end

  # rb_sym2id: the ID of a Symbol.
  #: (value) -> word
  def rb_sym2id(sym)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_id(zr_sym2id(sym))
  end
end
