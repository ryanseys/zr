# Hashes: entries in insertion order outside the arena, each a key, a
# value and whether it is live (a deleted entry stays until the table
# grows). Lookup walks the entries; a bin table comes when the corpus
# asks for one. A String key is kept as a frozen copy, as CRuby keeps it.
Machine.struct :RHash, basic: RBasic, entries: Ptr, len: Word, live: Word, cap: Word, default: Value, default_proc: Value
Machine.struct :HEntry, key: Value, value: Value, live: Word
T_HASH = 8
G_HASH = 30
G_KEY_ERROR = 31

sig [] => Value
machine def zr_hash_new
  h = zr_alloc(T_HASH, zr_global(G_HASH))
  RHash.set_entries(h, 0)
  RHash.set_len(h, 0)
  RHash.set_live(h, 0)
  RHash.set_cap(h, 0)
  RHash.set_default(h, Machine.value(QNIL))
  RHash.set_default_proc(h, Machine.value(QNIL))
  h
end

sig [Value] => Void
machine def zr_mark_hash(h)
  zr_mark(RHash.default(h))
  zr_mark(RHash.default_proc(h))
  n = RHash.len(h)
  i = 0
  while i < n
    e = RHash.entries(h) + (i * HEntry.size)
    if HEntry.live(e) != 0
      zr_mark(HEntry.key(e))
      zr_mark(HEntry.value(e))
    end
    i += 1
  end
end

# Whether two keys are the same key: `eql?` for the builtin kinds, and
# identity for everything else.
sig [Value, Value] => Bool
machine def zr_key_eql(a, b)
  if a == b
    return true
  end
  if zr_special_p(a) || zr_special_p(b)
    return false
  end
  t = zr_type(a)
  if t != zr_type(b)
    return false
  end
  if t == T_STRING
    return zr_bytes_eq(RString.ptr(a), RString.len(a), RString.ptr(b), RString.len(b))
  end
  if t == T_ARRAY
    if RArray.len(a) != RArray.len(b)
      return false
    end
    i = 0
    while i < RArray.len(a)
      unless zr_key_eql(zr_ary_at(a, i), zr_ary_at(b, i))
        return false
      end
      i += 1
    end
    return true
  end
  false
end

# The live entry for `key`, or 0.
sig [Value, Value] => Ptr
machine def zr_hash_entry(h, key)
  n = RHash.len(h)
  i = 0
  while i < n
    e = RHash.entries(h) + (i * HEntry.size)
    if HEntry.live(e) != 0 && zr_key_eql(HEntry.key(e), key)
      return e
    end
    i += 1
  end
  0
end

sig [Value, Value] => Value
machine def zr_hash_lookup(h, key)
  e = zr_hash_entry(h, key)
  if e == 0
    return Machine.value(QUNDEF)
  end
  HEntry.value(e)
end

# Room for one more entry: the table doubles, dropping deleted entries
# on the way.
sig [Value] => Void
machine def zr_hash_reserve(h)
  n = RHash.len(h)
  if n < RHash.cap(h)
    return
  end
  cap = RHash.live(h) * 2
  if cap < 8
    cap = 8
  end
  entries = malloc(cap * HEntry.size)
  j = 0
  i = 0
  while i < n
    e = RHash.entries(h) + (i * HEntry.size)
    if HEntry.live(e) != 0
      zr_memcpy(entries + (j * HEntry.size), e, HEntry.size)
      j += 1
    end
    i += 1
  end
  if RHash.entries(h) != 0
    free(RHash.entries(h))
  end
  RHash.set_entries(h, entries)
  RHash.set_len(h, j)
  RHash.set_cap(h, cap)
end

sig [Value, Value, Value] => Void
machine def zr_hash_store(h, key, value)
  e = zr_hash_entry(h, key)
  if e != 0
    HEntry.set_value(e, value)
    return
  end
  if !zr_special_p(key) && zr_type(key) == T_STRING && !zr_frozen_p(key)
    key = zr_str_new(RString.ptr(key), RString.len(key))
    RBasic.set_flags(key, RBasic.flags(key) | FL_FREEZE)
  end
  zr_hash_reserve(h)
  n = RHash.len(h)
  e = RHash.entries(h) + (n * HEntry.size)
  HEntry.set_key(e, key)
  HEntry.set_value(e, value)
  HEntry.set_live(e, 1)
  RHash.set_len(h, n + 1)
  RHash.set_live(h, RHash.live(h) + 1)
end

# The value for a missing key: the default proc's answer, or the default.
sig [Value, Value] => Value
machine def zr_hash_default(h, key)
  if RHash.default_proc(h) != QNIL
    return zr_yield2(RHash.default_proc(h), h, key)
  end
  RHash.default(h)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_aref(recv, argc, argv, cref, blk)
  key = Machine.value(Machine.load64(argv, 0))
  v = zr_hash_lookup(recv, key)
  if v == QUNDEF
    return zr_hash_default(recv, key)
  end
  v
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_aset(recv, argc, argv, cref, blk)
  value = Machine.value(Machine.load64(argv, 8))
  zr_hash_store(recv, Machine.value(Machine.load64(argv, 0)), value)
  value
end

# `fetch(key)`, `fetch(key, default)`, `fetch(key) { |key| }`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_fetch(recv, argc, argv, cref, blk)
  if argc < 1 || argc > 2
    return zr_wrong_arity_range(argc, 1, 2)
  end
  key = Machine.value(Machine.load64(argv, 0))
  v = zr_hash_lookup(recv, key)
  if v != QUNDEF
    return v
  end
  if blk != QNIL
    return zr_yield1(blk, key)
  end
  if argc == 2
    return Machine.value(Machine.load64(argv, 8))
  end
  s = zr_send(key, Machine.id(:inspect), 0, 0)
  return s if s == QUNDEF
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("key not found: "), 15)
  zr_buf_str(b, s)
  zr_raise_buf(zr_global(G_KEY_ERROR), b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_key_p(recv, argc, argv, cref, blk)
  zr_bool(zr_hash_entry(recv, Machine.value(Machine.load64(argv, 0))) != 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_delete(recv, argc, argv, cref, blk)
  e = zr_hash_entry(recv, Machine.value(Machine.load64(argv, 0)))
  if e == 0
    return Machine.value(QNIL)
  end
  v = HEntry.value(e)
  HEntry.set_live(e, 0)
  HEntry.set_key(e, Machine.value(QNIL))
  HEntry.set_value(e, Machine.value(QNIL))
  RHash.set_live(recv, RHash.live(recv) - 1)
  v
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_size(recv, argc, argv, cref, blk)
  zr_fix(RHash.live(recv))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_empty_p(recv, argc, argv, cref, blk)
  zr_bool(RHash.live(recv) == 0)
end

# The live entry at or after index `i`, or 0.
sig [Value, Word] => Ptr
machine def zr_hash_next(h, i)
  while i < RHash.len(h)
    e = RHash.entries(h) + (i * HEntry.size)
    if HEntry.live(e) != 0
      return e
    end
    i += 1
  end
  0
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_keys(recv, argc, argv, cref, blk)
  out = zr_ary_new(RHash.live(recv))
  i = 0
  while i < RHash.len(recv)
    e = RHash.entries(recv) + (i * HEntry.size)
    if HEntry.live(e) != 0
      zr_ary_push(out, HEntry.key(e))
    end
    i += 1
  end
  out
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_values(recv, argc, argv, cref, blk)
  out = zr_ary_new(RHash.live(recv))
  i = 0
  while i < RHash.len(recv)
    e = RHash.entries(recv) + (i * HEntry.size)
    if HEntry.live(e) != 0
      zr_ary_push(out, HEntry.value(e))
    end
    i += 1
  end
  out
end

# `[key, value]`.
sig [Ptr] => Value
machine def zr_hash_assoc(e)
  pair = zr_ary_new(2)
  zr_ary_push(pair, HEntry.key(e))
  zr_ary_push(pair, HEntry.value(e))
  pair
end

# `each`: one `[key, value]` per entry, re-reading the table after every
# yield, since the block may change it.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_each(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("Hash#each without a block needs Enumerator\n"), 43)
  end
  i = 0
  while i < RHash.len(recv)
    e = RHash.entries(recv) + (i * HEntry.size)
    if HEntry.live(e) != 0
      r = zr_yield1(blk, zr_hash_assoc(e))
      return r if r == QUNDEF
    end
    i += 1
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_to_a(recv, argc, argv, cref, blk)
  out = zr_ary_new(RHash.live(recv))
  i = 0
  while i < RHash.len(recv)
    e = RHash.entries(recv) + (i * HEntry.size)
    if HEntry.live(e) != 0
      zr_ary_push(out, zr_hash_assoc(e))
    end
    i += 1
  end
  out
end

# A Symbol key prints as `key: value`, quoted when its name is not a
# plain identifier; any other key as `key => value`.
sig [Value] => Bool
machine def zr_symbol_key_simple_p(key)
  if !zr_symbol_p(key)
    return false
  end
  id = zr_sym2id(key)
  p = zr_symbol_name_ptr(id)
  n = zr_symbol_name_len(id)
  if n == 0
    return false
  end
  c = Machine.word(Machine.load8(p, 0))
  unless (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95
    return false
  end
  i = 1
  while i < n
    c = Machine.word(Machine.load8(p + i, 0))
    unless zr_alnum_p(c) || c == 95
      if i == n - 1 && (c == 63 || c == 33)
        return true
      end
      return false
    end
    i += 1
  end
  true
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_inspect(recv, argc, argv, cref, blk)
  if RHash.live(recv) == 0
    return zr_str_new(Machine.bytes("{}"), 2)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_byte(b, 123)
  first = true
  i = 0
  while i < RHash.len(recv)
    e = RHash.entries(recv) + (i * HEntry.size)
    if HEntry.live(e) != 0
      unless first
        zr_buf_push(b, Machine.bytes(", "), 2)
      end
      first = false
      key = HEntry.key(e)
      if zr_symbol_p(key)
        if zr_symbol_key_simple_p(key)
          zr_buf_sym(b, zr_sym2id(key))
        else
          zr_buf_str_escaped(b, zr_symbol_name_ptr(zr_sym2id(key)), zr_symbol_name_len(zr_sym2id(key)))
        end
        zr_buf_push(b, Machine.bytes(": "), 2)
      else
        s = zr_send(key, Machine.id(:inspect), 0, 0)
        if s == QUNDEF
          free(Buf.ptr(b))
          return s
        end
        zr_buf_str(b, s)
        zr_buf_push(b, Machine.bytes(" => "), 4)
      end
      e = RHash.entries(recv) + (i * HEntry.size)
      s = zr_send(HEntry.value(e), Machine.id(:inspect), 0, 0)
      if s == QUNDEF
        free(Buf.ptr(b))
        return s
      end
      zr_buf_str(b, s)
    end
    i += 1
  end
  zr_buf_byte(b, 125)
  zr_buf_take(b)
end

# `==`: the same keys, each with `==` values.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_eq(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_HASH
    return Machine.value(QFALSE)
  end
  if RHash.live(recv) != RHash.live(other)
    return Machine.value(QFALSE)
  end
  i = 0
  while i < RHash.len(recv)
    e = RHash.entries(recv) + (i * HEntry.size)
    if HEntry.live(e) != 0
      v = zr_hash_lookup(other, HEntry.key(e))
      if v == QUNDEF
        return Machine.value(QFALSE)
      end
      slot = Machine.slot(8)
      Machine.store64(slot, 0, Machine.word(v))
      r = zr_send(HEntry.value(RHash.entries(recv) + (i * HEntry.size)), Machine.id(:==), 1, slot)
      return r if r == QUNDEF
      if r == QNIL || r == QFALSE
        return Machine.value(QFALSE)
      end
    end
    i += 1
  end
  Machine.value(QTRUE)
end

# `Hash.new`, `Hash.new(default)`, `Hash.new { |hash, key| }`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_s_new(recv, argc, argv, cref, blk)
  if argc > 1
    return zr_wrong_arity_range(argc, 0, 1)
  end
  h = zr_hash_new()
  if argc == 1
    if blk != QNIL
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("wrong number of arguments (given 1, expected 0)"), 47)
    end
    RHash.set_default(h, Machine.value(Machine.load64(argv, 0)))
  end
  RHash.set_default_proc(h, blk)
  h
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_default_m(recv, argc, argv, cref, blk)
  RHash.default(recv)
end

# `{k => v, ...}` from `n` pairs staged in `argv`.
sig [Word, Ptr] => Value
machine def zr_hash_of(n, argv)
  h = zr_hash_new()
  i = 0
  while i < n
    zr_hash_store(h, Machine.value(Machine.load64(argv + (i * 16), 0)), Machine.value(Machine.load64(argv + (i * 16), 8)))
    i += 1
  end
  h
end

# The keywords a method declares come as `n` symbol ids at `ids`; the
# call's keywords are `hash`, or nil when none were passed.
sig [Value, Word] => Value
machine def zr_kw_get(hash, id)
  if hash == QNIL
    return Machine.value(QUNDEF)
  end
  zr_hash_lookup(hash, zr_sym(id))
end

sig [Ptr, Word, Word] => Bool
machine def zr_kw_declared(ids, n, id)
  i = 0
  while i < n
    if Machine.load64(ids + (i * 8), 0) == id
      return true
    end
    i += 1
  end
  false
end

# `missing keyword: :a` or `missing keywords: :a, :b` for the required
# keywords `hash` lacks; nil when it has them all.
sig [Value, Ptr, Word] => Value
machine def zr_kw_missing(hash, ids, n)
  count = 0
  i = 0
  while i < n
    if zr_kw_get(hash, Machine.load64(ids + (i * 8), 0)) == QUNDEF
      count += 1
    end
    i += 1
  end
  if count == 0
    return Machine.value(QNIL)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, count == 1 ? Machine.bytes("missing keyword: ") : Machine.bytes("missing keywords: "), count == 1 ? 17 : 18)
  seen = 0
  i = 0
  while i < n
    id = Machine.load64(ids + (i * 8), 0)
    if zr_kw_get(hash, id) == QUNDEF
      if seen > 0
        zr_buf_push(b, Machine.bytes(", "), 2)
      end
      zr_buf_byte(b, 58)
      zr_buf_sym(b, id)
      seen += 1
    end
    i += 1
  end
  zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
end

# `unknown keyword: :x` or `unknown keywords: :x, :y` for the keys of
# `hash` the method does not declare; nil when there are none.
sig [Value, Ptr, Word] => Value
machine def zr_kw_unknown(hash, ids, n)
  if hash == QNIL
    return Machine.value(QNIL)
  end
  count = 0
  i = 0
  while i < RHash.len(hash)
    e = RHash.entries(hash) + (i * HEntry.size)
    if HEntry.live(e) != 0 && !(zr_symbol_p(HEntry.key(e)) && zr_kw_declared(ids, n, zr_sym2id(HEntry.key(e))))
      count += 1
    end
    i += 1
  end
  if count == 0
    return Machine.value(QNIL)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, count == 1 ? Machine.bytes("unknown keyword: ") : Machine.bytes("unknown keywords: "), count == 1 ? 17 : 18)
  seen = 0
  i = 0
  while i < RHash.len(hash)
    e = RHash.entries(hash) + (i * HEntry.size)
    if HEntry.live(e) != 0 && !(zr_symbol_p(HEntry.key(e)) && zr_kw_declared(ids, n, zr_sym2id(HEntry.key(e))))
      if seen > 0
        zr_buf_push(b, Machine.bytes(", "), 2)
      end
      s = zr_send(HEntry.key(RHash.entries(hash) + (i * HEntry.size)), Machine.id(:inspect), 0, 0)
      if s == QUNDEF
        free(Buf.ptr(b))
        return s
      end
      zr_buf_str(b, s)
      seen += 1
    end
    i += 1
  end
  zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
end

# `**rest`: the keywords of `hash` the method does not declare.
sig [Value, Ptr, Word] => Value
machine def zr_kw_rest(hash, ids, n)
  out = zr_hash_new()
  if hash == QNIL
    return out
  end
  i = 0
  while i < RHash.len(hash)
    e = RHash.entries(hash) + (i * HEntry.size)
    if HEntry.live(e) != 0 && !(zr_symbol_p(HEntry.key(e)) && zr_kw_declared(ids, n, zr_sym2id(HEntry.key(e))))
      zr_hash_store(out, HEntry.key(e), HEntry.value(e))
    end
    i += 1
  end
  out
end

# `**value` in a hash literal or a call: the value's pairs, which must
# be a Hash (nil adds nothing).
sig [Value, Value] => Value
machine def zr_hash_update(h, other)
  if other == QNIL
    return h
  end
  if zr_special_p(other) || zr_type(other) != T_HASH
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
    zr_buf_str(b, zr_class_name_of(other))
    zr_buf_push(b, Machine.bytes(" into Hash"), 10)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  i = 0
  while i < RHash.len(other)
    e = RHash.entries(other) + (i * HEntry.size)
    if HEntry.live(e) != 0
      zr_hash_store(h, HEntry.key(e), HEntry.value(e))
    end
    i += 1
  end
  h
end
