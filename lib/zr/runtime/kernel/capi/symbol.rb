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

  # rb_intern3: the ID of the `len` bytes at `name` in `enc`. A name is
  # its bytes here, so the encoding only matters past ASCII, as a Symbol
  # of those bytes.
  #: (ptr, word, ptr) -> word
  def rb_intern3(name, len, enc)
    Machine.gates_enter
    zr_c_entered()
    if enc == 0 || zr_bytes_ascii_only_p(name, len)
      return zr_capi_id(zr_intern(name, len))
    end
    zr_capi_id(zr_sym2id(zr_c_result(zr_send(zr_capi_str(name, len, zr_capi_enc_index(enc)), Machine.id(:to_sym), 0, Machine.ptr(0)))))
  end

  # rb_id2name: the name of an ID as a C string, which stays valid for
  # the program: a NUL-terminated copy for each symbol, made once.
  #: (word) -> ptr
  def rb_id2name(mid)
    Machine.gates_enter
    zr_c_entered()
    id = zr_capi_mid(mid)
    table = Machine.static(:capi_id_names, 16)
    cap = Machine.load64(table, 8)
    if id >= cap
      grown = (id + 1) * 2
      rows = zr_xmalloc(grown * 8)
      Libc.memset(rows, Machine.i32(0), grown * 8)
      if cap > 0
        old = Machine.ptr(Machine.load64(table, 0))
        zr_memcpy(rows, old, cap * 8)
        zr_xfree(old)
      end
      Machine.store64(table, 0, Machine.word(rows))
      Machine.store64(table, 8, grown)
    end
    row = Machine.ptr(Machine.load64(table, 0)) + (id * 8)
    name = Machine.ptr(Machine.load64(row, 0))
    if name == 0
      len = zr_symbol_name_len(id)
      name = zr_xmalloc(len + 1)
      zr_memcpy(name, zr_symbol_name_ptr(id), len)
      Machine.store8(name + len, 0, Machine.i8(0))
      Machine.store64(row, 0, Machine.word(name))
    end
    name
  end

  # rb_id2str: the name of an ID, a frozen String.
  #: (word) -> value
  def rb_id2str(mid)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_sym(zr_capi_mid(mid)), Machine.id(:name), 0, Machine.ptr(0)))
  end

  # rb_check_symbol_cstr: the Symbol of the `len` bytes at `name` in
  # `enc` when one exists, else nil: it makes none.
  #: (ptr, word, ptr) -> value
  def rb_check_symbol_cstr(name, len, enc)
    Machine.gates_enter
    zr_c_entered()
    index = zr_capi_enc_index(enc)
    tag = zr_bytes_ascii_only_p(name, len) ? 0 : (index < 2 ? 1 - index : index)
    id = zr_symbol_index_find(name, len, tag)
    id < 0 ? Machine.value(QNIL) : zr_sym(id)
  end
end
