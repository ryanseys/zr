# Symbols: the id sits in the tagged word, the name in a table. The
# compiler lays every static name out in `zr_symbol_names`, a table of
# (bytes, length) rows, `zr_symbol_count` of them; names interned at run
# time follow in a table of the same shape outside the arena.
Machine.struct :Symtab, rows: Ptr, len: Word, capa: Word

sig [] => Ptr
machine def zr_symtab
  Machine.static(:symtab, 32)
end

sig [] => Word
machine def zr_static_symbol_count
  Machine.load64(Machine.extern(:zr_symbol_count), 0)
end

sig [Word] => Ptr
machine def zr_symbol_row(id)
  n = zr_static_symbol_count()
  if id < n
    Machine.extern(:zr_symbol_names) + (id * 16)
  else
    Symtab.rows(zr_symtab()) + ((id - n) * 16)
  end
end

sig [Word] => Ptr
machine def zr_symbol_name_ptr(id)
  Machine.load64(zr_symbol_row(id), 0)
end

sig [Word] => Word
machine def zr_symbol_name_len(id)
  Machine.load64(zr_symbol_row(id), 8)
end

sig [Ptr, Word, Ptr, Word] => Bool
machine def zr_bytes_eq(a, alen, b, blen)
  if alen != blen
    return false
  end
  i = 0
  while i < alen
    if Machine.load8(a + i, 0) != Machine.load8(b + i, 0)
      return false
    end
    i += 1
  end
  true
end

# The id of the symbol named by `n` bytes, interning it when new.
sig [Ptr, Word] => Word
machine def zr_intern(p, n)
  t = zr_symtab()
  total = zr_static_symbol_count() + Symtab.len(t)
  id = 0
  while id < total
    if zr_bytes_eq(p, n, zr_symbol_name_ptr(id), zr_symbol_name_len(id))
      return id
    end
    id += 1
  end
  k = Symtab.len(t)
  if k == Symtab.capa(t)
    cap = k * 2
    if cap < 64
      cap = 64
    end
    rows = malloc(cap * 16)
    if Symtab.rows(t) != 0
      zr_memcpy(rows, Symtab.rows(t), k * 16)
      free(Symtab.rows(t))
    end
    Symtab.set_rows(t, rows)
    Symtab.set_capa(t, cap)
  end
  copy = malloc(n + 1)
  zr_memcpy(copy, p, n)
  Machine.store8(copy + n, 0, Machine.i8(0))
  row = Symtab.rows(t) + (k * 16)
  Machine.store64(row, 0, copy)
  Machine.store64(row, 8, n)
  Symtab.set_len(t, k + 1)
  total
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_sym_to_s(recv, argc, argv, cref, blk)
  id = zr_sym2id(recv)
  zr_str_new(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
end

# `Symbol#<=>`: the names bytewise, nil against anything else.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_sym_cmp(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if !zr_symbol_p(other)
    return Machine.value(QNIL)
  end
  a = zr_sym2id(recv)
  b = zr_sym2id(other)
  zr_fix(zr_bytes_cmp(zr_symbol_name_ptr(a), zr_symbol_name_len(a), zr_symbol_name_ptr(b), zr_symbol_name_len(b)))
end
