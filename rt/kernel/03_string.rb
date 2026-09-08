# Strings: a length, a capacity and a buffer outside the arena.
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr

sig [Ptr, Word] => Value
machine def zr_str_new(bytes, len)
  s = zr_alloc(T_STRING, zr_global(G_STRING))
  buf = malloc(len + 1)
  zr_memcpy(buf, bytes, len)
  Machine.store8(buf + len, 0, Machine.i8(0))
  RString.set_ptr(s, buf)
  RString.set_len(s, len)
  RString.set_capa(s, len)
  s
end

# The name of the symbol `id`: the compiler lays every name out in
# `zr_symbol_names`, a table of (bytes, length) rows.
sig [Word] => Ptr
machine def zr_symbol_name_ptr(id)
  Machine.load64(Machine.extern(:zr_symbol_names) + (id * 16), 0)
end

sig [Word] => Word
machine def zr_symbol_name_len(id)
  Machine.load64(Machine.extern(:zr_symbol_names) + (id * 16), 8)
end

sig [Value, Word, Ptr] => Value
machine def zr_str_to_s(recv, argc, argv)
  recv
end

sig [Value, Word, Ptr] => Value
machine def zr_sym_to_s(recv, argc, argv)
  id = zr_sym2id(recv)
  zr_str_new(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
end
