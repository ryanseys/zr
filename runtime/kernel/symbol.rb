# Symbols. The tagged word contains the id, and a table contains the
# name. The compiler puts each static name in `zr_symbol_names`, a table
# of `zr_symbol_count` entries of (bytes, length). Names interned at run
# time go in a table of the same shape outside the arena.
Machine.struct :Symtab, rows: Ptr, len: Word, capa: Word, bins: Ptr, nbins: Word

sig [] => Ptr
machine def zr_symtab
  Machine.static(:symtab, Symtab.size)
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

# The second word of an entry is the name length, with the encoding tag
# in its top byte. The tag is the same as in a String's flags, so 0 is
# UTF-8, which all static names use. An ASCII-only name always has 0.
sig [Word] => Word
machine def zr_symbol_name_len(id)
  Machine.load64(zr_symbol_row(id), 8) & ((1 << SYM_TAG_SHIFT) - 1)
end

sig [Word] => Word
machine def zr_symbol_tag(id)
  Machine.load64(zr_symbol_row(id), 8) >> SYM_TAG_SHIFT
end

# The encoding index of a symbol's name.
sig [Word] => Word
machine def zr_symbol_encoding_index(id)
  tag = zr_symbol_tag(id)
  tag < 2 ? 1 - tag : tag
end

# Whether the `alen` bytes at `a` are equal to the `blen` bytes at `b`.
# It compares eight bytes at a time, then the rest one at a time.
sig [Ptr, Word, Ptr, Word] => Bool
machine def zr_bytes_eq(a, alen, b, blen)
  if alen != blen
    return false
  end
  i = 0
  while i + 8 <= alen
    if Machine.load64(a + i, 0) != Machine.load64(b + i, 0)
      return false
    end
    i += 8
  end
  while i < alen
    if Machine.load8(a + i, 0) != Machine.load8(b + i, 0)
      return false
    end
    i += 1
  end
  true
end

# The id of the symbol whose name is `n` bytes in UTF-8. It interns the
# name if it is new.
sig [Ptr, Word] => Word
machine def zr_intern(p, n)
  zr_intern_tagged(p, n, 0)
end

# A lookup finds a symbol through a hash index of all names, static and
# interned. The first lookup that needs the index builds it. Without the
# index, each intern compares bytes with all symbols. A compiler interns
# names very frequently, so that is too slow.
#
# A bin contains the id plus one, or zero when empty. The key is the
# name together with its encoding tag, because `rb_str_intern` uses
# both as the key of a symbol.
sig [Ptr, Word, Word] => Word
machine def zr_symbol_hash(p, n, tag)
  zr_hash_mix(zr_bytes_hash(p, n) ^ tag)
end

# Discards the index. The next lookup that needs it builds it again.
sig [] => Void
machine def zr_symbol_index_drop
  t = zr_symtab()
  if Symtab.bins(t) != 0
    zr_xfree(Symtab.bins(t))
    Symtab.set_bins(t, 0)
  end
end

sig [Word] => Void
machine def zr_symbol_index_put(id)
  t = zr_symtab()
  mask = Symtab.nbins(t) - 1
  h = zr_symbol_hash(zr_symbol_name_ptr(id), zr_symbol_name_len(id), zr_symbol_tag(id)) & mask
  while Machine.load64(Symtab.bins(t) + (h * 8), 0) != 0
    h = (h + 1) & mask
  end
  Machine.store64(Symtab.bins(t) + (h * 8), 0, id + 1)
end

# Adds all symbols to a new index with at least four bins for each
# symbol.
sig [] => Void
machine def zr_symbol_index_build
  zr_symbol_index_drop()
  t = zr_symtab()
  total = zr_static_symbol_count() + Symtab.len(t)
  bins = 1024
  while bins < total * 4
    bins = bins * 2
  end
  Symtab.set_bins(t, zr_xmalloc(bins * 8))
  memset(Symtab.bins(t), Machine.i32(0), bins * 8)
  Symtab.set_nbins(t, bins)
  id = 0
  while id < total
    zr_symbol_index_put(id)
    id += 1
  end
end

# Adds a newly interned symbol to the index while less than half the
# bins are full. Else it discards the index, and the next lookup builds
# a larger one.
sig [Word] => Void
machine def zr_symbol_index_add(id)
  t = zr_symtab()
  if Symtab.bins(t) == 0
    return
  end
  if (id + 1) * 2 > Symtab.nbins(t)
    zr_symbol_index_drop()
    return
  end
  zr_symbol_index_put(id)
end

# The id of the symbol whose name is `n` bytes in the encoding `tag`, or
# -1 if the table does not contain it.
sig [Ptr, Word, Word] => Word
machine def zr_symbol_index_find(p, n, tag)
  t = zr_symtab()
  if Symtab.bins(t) == 0
    zr_symbol_index_build()
  end
  mask = Symtab.nbins(t) - 1
  h = zr_symbol_hash(p, n, tag) & mask
  slot = Machine.load64(Symtab.bins(t) + (h * 8), 0)
  while slot != 0
    id = slot - 1
    if zr_symbol_tag(id) == tag && zr_bytes_eq(p, n, zr_symbol_name_ptr(id), zr_symbol_name_len(id))
      return id
    end
    h = (h + 1) & mask
    slot = Machine.load64(Symtab.bins(t) + (h * 8), 0)
  end
  0 - 1
end

# The id of the symbol whose name is `n` bytes in the encoding `tag`. It
# interns the name if it is new. rb_str_intern uses both the bytes and
# the encoding as the key.
sig [Ptr, Word, Word] => Word
machine def zr_intern_tagged(p, n, tag)
  found = zr_symbol_index_find(p, n, tag)
  if found >= 0
    return found
  end
  t = zr_symtab()
  total = zr_static_symbol_count() + Symtab.len(t)
  k = Symtab.len(t)
  if k == Symtab.capa(t)
    cap = k * 2
    if cap < 64
      cap = 64
    end
    rows = zr_xmalloc(cap * 16)
    if Symtab.rows(t) != 0
      zr_memcpy(rows, Symtab.rows(t), k * 16)
      zr_xfree(Symtab.rows(t))
    end
    Symtab.set_rows(t, rows)
    Symtab.set_capa(t, cap)
  end
  copy = zr_xmalloc(n + 1)
  zr_memcpy(copy, p, n)
  Machine.store8(copy + n, 0, Machine.i8(0))
  row = Symtab.rows(t) + (k * 16)
  Machine.store64(row, 0, copy)
  Machine.store64(row, 8, n | (tag << SYM_TAG_SHIFT))
  Symtab.set_len(t, k + 1)
  zr_symbol_index_add(total)
  total
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_sym_to_s(recv, argc, argv, cref, blk)
  id = zr_sym2id(recv)
  s = zr_str_new(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
  # An ASCII-only name is US-ASCII, as in ruby.
  zr_str_set_index(s, zr_str_ascii_only(s) ? ENC_USASCII : zr_symbol_encoding_index(id))
  RBasic.set_flags(s, RBasic.flags(s) | FL_CHILLED_SYMBOL)
  s
end

# `Symbol#<=>`: compares the names byte by byte, and returns nil for a
# non-Symbol. The same bytes in two encodings sort by encoding index, as
# in rb_str_cmp.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_sym_cmp(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if !zr_symbol_p(other)
    return Machine.value(QNIL)
  end
  a = zr_sym2id(recv)
  b = zr_sym2id(other)
  order = zr_bytes_cmp(zr_symbol_name_ptr(a), zr_symbol_name_len(a), zr_symbol_name_ptr(b), zr_symbol_name_len(b))
  if order == 0 && a != b
    return zr_fix(zr_symbol_encoding_index(a) > zr_symbol_encoding_index(b) ? 1 : 0 - 1)
  end
  zr_fix(order)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_sym_to_proc_m(recv, argc, argv, cref, blk)
  zr_sym_to_proc_here(recv)
end

# All symbols interned until now, static names first.
sig [] => Value
machine def zr_all_symbols
  total = zr_static_symbol_count() + Symtab.len(zr_symtab())
  out = zr_ary_new(total)
  id = 0
  while id < total
    zr_ary_push(out, zr_sym(id))
    id += 1
  end
  out
end

# The id of a name, interned if it is new. An eval uses it so that the
# ids in its compiled code agree with the ids of this program.
sig [Value] => Value
machine def zr_intern_id(name)
  zr_fix(zr_intern(RString.ptr(name), RString.len(name)))
end

# The number of regexp literal sites in the program, so that the sites
# of an eval start after them.
sig [] => Value
machine def zr_static_sites
  zr_fix(Machine.load64(Machine.extern(:zr_site_count), 0))
end
