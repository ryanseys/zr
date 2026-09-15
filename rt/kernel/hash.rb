# Hashes: entries in insertion order outside the arena, each a key, a
# value, its hash code and whether it is live (a deleted entry stays
# until the table grows), plus an open-addressing index of bins that
# maps a hash code to an entry. A String key is kept as a frozen copy,
# as CRuby keeps it. `gen` counts the times the entries or the bins were
# built again, so a probe that ran a key's own `eql?` can see that the
# table under it changed (CRuby's st "rebuilt" check).
Machine.struct :RHash, basic: RBasic, entries: Ptr, len: Word, live: Word, cap: Word, default: Value, default_proc: Value, bins: Ptr, nbins: Word, iter: Word, gen: Word
Machine.struct :HEntry, key: Value, value: Value, live: Word, hash: Word
T_HASH = 8
G_HASH = 30
G_KEY_ERROR = 31

# How a probe ends when a key's own `hash` or `eql?` raised: the
# exception is pending in the task, and the probe answers this in place
# of an entry.
HASH_RAISED = 1

# The answers of zr_key_eql.
KEY_DIFFERENT = 0
KEY_SAME = 1
KEY_RAISED = 2

sig [] => Value
machine def zr_hash_new
  h = zr_alloc(T_HASH, zr_global(G_HASH))
  RHash.set_entries(h, 0)
  RHash.set_len(h, 0)
  RHash.set_live(h, 0)
  RHash.set_cap(h, 0)
  RHash.set_default(h, Machine.value(QNIL))
  RHash.set_default_proc(h, Machine.value(QNIL))
  RHash.set_bins(h, 0)
  RHash.set_nbins(h, 0)
  RHash.set_iter(h, 0)
  RHash.set_gen(h, 0)
  h
end

sig [Value] => Void
machine def zr_mark_hash(h)
  zr_mark(RHash.default(h))
  zr_mark(RHash.default_proc(h))
  if (RBasic.flags(h) & FL_WEAK) != 0
    return
  end
  keys = (RBasic.flags(h) & FL_WEAKKEY) == 0
  n = RHash.len(h)
  i = 0
  while i < n
    e = RHash.entries(h) + (i * HEntry.size)
    if HEntry.live(e) != 0
      if keys
        zr_mark(HEntry.key(e))
      end
      zr_mark(HEntry.value(e))
    end
    i += 1
  end
end

# Whether two keys are the same key: `eql?` for the builtin kinds
# here, the object's own `eql?` for an object with an ivar table
# (Struct, Data and the program's classes), identity for the rest. An
# `eql?` that raises answers KEY_RAISED, with the exception pending.
sig [Value, Value] => Word
machine def zr_key_eql(a, b)
  if a == b
    return KEY_SAME
  end
  if zr_special_p(a) || zr_special_p(b)
    if zr_float_p(a) && zr_float_p(b)
      return zr_float_value(a) == zr_float_value(b) ? KEY_SAME : KEY_DIFFERENT
    end
    return KEY_DIFFERENT
  end
  t = zr_type(a)
  if t != zr_type(b)
    return KEY_DIFFERENT
  end
  if t == T_STRING
    return zr_bytes_eq(RString.ptr(a), RString.len(a), RString.ptr(b), RString.len(b)) && zr_str_comparable(a, b) ? KEY_SAME : KEY_DIFFERENT
  end
  if t == T_ARRAY
    if RArray.len(a) != RArray.len(b)
      return KEY_DIFFERENT
    end
    # The same two Arrays met again inside their own comparison is a
    # recursion, which answers equal (rb_exec_recursive_paired).
    if zr_guard_enter_paired(a, b, Machine.id(:eql?))
      return KEY_SAME
    end
    same = zr_key_eql_elements(a, b)
    zr_guard_leave(a, Machine.id(:eql?))
    return same
  end
  if t == T_REGEXP
    return RRegexp.options(a) == RRegexp.options(b) ? zr_key_eql(RRegexp.source(a), RRegexp.source(b)) : KEY_DIFFERENT
  end
  # Kernel#eql? is identity, which the first test answered; any other
  # eql? is the key's own, whatever kind of object it is.
  if zr_key_builtin_p(a, Machine.id(:eql?), Machine.addr(:zr_obj_eql_p))
    return KEY_DIFFERENT
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(b))
  r = zr_send(a, Machine.id(:eql?), 1, slot)
  if r == QUNDEF
    return KEY_RAISED
  end
  r != QNIL && r != QFALSE ? KEY_SAME : KEY_DIFFERENT
end

# Whether two Arrays of one length hold the same keys, each against
# each. Each round reads the lengths again, as an `eql?` can change
# either Array.
sig [Value, Value] => Word
machine def zr_key_eql_elements(a, b)
  i = 0
  while i < RArray.len(a)
    if i >= RArray.len(b)
      return KEY_DIFFERENT
    end
    same = zr_key_eql(zr_ary_at(a, i), zr_ary_at(b, i))
    if same != KEY_SAME
      return same
    end
    i += 1
  end
  KEY_SAME
end

# A word mixed into a hash code.
sig [Word] => Word
machine def zr_hash_mix(x)
  x = (x ^ (x >> 31)) * 7046029254386353131
  x ^ (x >> 29)
end

# The hash code of a key as the table sees it, written to `out`: the
# value itself for a fixnum, Symbol or special constant, the double's
# bits for a Float (with -0.0 as 0.0), the bytes for a String, the parts
# for a Regexp, and the object's own `hash` for the rest. Under
# compare_by_identity every key hashes as itself. False when the key's
# own `hash` raised; the exception is then pending.
sig [Value, Value, Ptr] => Bool
machine def zr_key_hash(h, key, out)
  Machine.store64(out, 0, zr_key_code(h, key))
  if (RBasic.flags(h) & FL_IDENTITY) != 0 || zr_special_p(key)
    return true
  end
  t = zr_type(key)
  if t == T_STRING || t == T_REGEXP
    return true
  end
  # Kernel#hash answers the identity code, which is here already, or a
  # bignum's own code.
  if zr_key_builtin_p(key, Machine.id(:hash), Machine.addr(:zr_obj_hash))
    if zr_big_p(key)
      Machine.store64(out, 0, zr_hash_mix(zr_fix2long(zr_big_hash(key))))
    end
    return true
  end
  r = zr_send(key, Machine.id(:hash), 0, 0)
  if r == QUNDEF
    return false
  end
  # A bignum folds to a fixnum, as rb_any_hash folds one.
  if zr_big_p(r)
    r = zr_send(r, Machine.id(:hash), 0, 0)
    if r == QUNDEF
      return false
    end
  end
  if zr_fixnum_p(r)
    Machine.store64(out, 0, zr_hash_mix(zr_fix2long(r)))
  end
  true
end

# Whether `key` answers `mid` with the builtin at `builtin`, which the
# table's own identity rule already stands for.
sig [Value, Word, Ptr] => Bool
machine def zr_key_builtin_p(key, mid, builtin)
  e = zr_find_method(zr_class_of(key), mid)
  e != 0 && MEntry.fn(e) == builtin
end

# The code of a key that runs no Ruby code to find it; for a key whose
# own `hash` answers the code, its identity, which zr_key_hash replaces.
sig [Value, Value] => Word
machine def zr_key_code(h, key)
  if (RBasic.flags(h) & FL_IDENTITY) != 0
    return zr_hash_mix(Machine.word(key))
  end
  if zr_float_p(key)
    d = zr_float_value(key)
    if d == Machine.f64(0)
      d = Machine.f64(0)
    end
    return zr_hash_mix(Machine.word(Machine.ptr(Machine.bits(d))))
  end
  if zr_special_p(key)
    return zr_hash_mix(Machine.word(key))
  end
  t = zr_type(key)
  if t == T_STRING
    return zr_hash_mix(zr_bytes_hash(RString.ptr(key), RString.len(key)) ^ (zr_str_ascii_only(key) ? 0 : zr_str_encoding_index(key) + 1))
  end
  if t == T_REGEXP
    return zr_hash_mix(zr_key_code(h, RRegexp.source(key)) + RRegexp.options(key))
  end
  zr_hash_mix(Machine.word(key))
end

# FNV-1a over the bytes.
sig [Ptr, Word] => Word
machine def zr_bytes_hash(p, n)
  x = 1469598103934665603
  i = 0
  while i < n
    x = (x ^ Machine.word(Machine.load8(p + i, 0))) * 1099511628211
    i += 1
  end
  x
end

# The live entry for `key`, 0 when there is none, or HASH_RAISED: the
# bins are probed from the code's slot until an empty bin; a dead entry
# in the way is passed over.
sig [Value, Value] => Ptr
machine def zr_hash_entry(h, key)
  if RHash.live(h) == 0
    return 0
  end
  code = Machine.slot(8)
  unless zr_key_hash(h, key, code)
    return Machine.ptr(HASH_RAISED)
  end
  zr_hash_find(h, key, Machine.load64(code, 0))
end

# A key's own `eql?` can add to the table, and so build its entries and
# bins again. The probe then starts over on the new table, as CRuby's
# st does when it sees the table rebuilt.
sig [Value, Value, Word] => Ptr
machine def zr_hash_find(h, key, code)
  identity = (RBasic.flags(h) & FL_IDENTITY) != 0
  gen = RHash.gen(h)
  i = code
  while RHash.nbins(h) != 0
    i = i & (RHash.nbins(h) - 1)
    slot = Machine.load64(RHash.bins(h) + (i * 8), 0)
    if slot == 0
      return 0
    end
    e = RHash.entries(h) + ((slot - 1) * HEntry.size)
    i += 1
    if HEntry.live(e) != 0 && HEntry.hash(e) == code
      if identity
        if HEntry.key(e) == key
          return e
        end
      else
        same = zr_key_eql(HEntry.key(e), key)
        if same == KEY_RAISED
          return Machine.ptr(HASH_RAISED)
        end
        if RHash.gen(h) != gen
          gen = RHash.gen(h)
          i = code
        elsif same == KEY_SAME
          return e
        end
      end
    end
  end
  0
end

# The value for `key` in a table the runtime keeps for itself, or undef
# when there is none. The key must be a Symbol, a fixnum or a String:
# the lookup then runs no Ruby code and cannot raise.
sig [Value, Value] => Value
machine def zr_hash_lookup(h, key)
  e = zr_hash_entry(h, key)
  if e == HASH_RAISED
    zr_bug(Machine.bytes("zr_hash_lookup: a key that runs Ruby code\n"), 42)
  end
  if e == 0
    return Machine.value(QUNDEF)
  end
  HEntry.value(e)
end

# Entry `n` (its index in the entries) placed in the bins.
sig [Value, Word] => Void
machine def zr_hash_bin(h, n)
  e = RHash.entries(h) + (n * HEntry.size)
  mask = RHash.nbins(h) - 1
  i = HEntry.hash(e) & mask
  while Machine.load64(RHash.bins(h) + (i * 8), 0) != 0
    i = (i + 1) & mask
  end
  Machine.store64(RHash.bins(h) + (i * 8), 0, n + 1)
end

# The bins rebuilt from the live entries, twice the entry room so the
# probes stay short.
sig [Value] => Void
machine def zr_hash_rebins(h)
  if RHash.bins(h) != 0
    free(RHash.bins(h))
  end
  nbins = 16
  while nbins < RHash.cap(h) * 2
    nbins = nbins * 2
  end
  bins = zr_xmalloc(nbins * 8)
  i = 0
  while i < nbins
    Machine.store64(bins + (i * 8), 0, 0)
    i += 1
  end
  RHash.set_bins(h, bins)
  RHash.set_nbins(h, nbins)
  RHash.set_gen(h, RHash.gen(h) + 1)
  i = 0
  while i < RHash.len(h)
    if HEntry.live(RHash.entries(h) + (i * HEntry.size)) != 0
      zr_hash_bin(h, i)
    end
    i += 1
  end
end

# Room for one more entry: the table doubles, dropping deleted entries
# on the way, and the bins follow.
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
  entries = zr_xmalloc(cap * HEntry.size)
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
  zr_hash_rebins(h)
end

# Every key's code computed again and the bins rebuilt: after
# compare_by_identity, or `rehash`. A key's own `hash` can change the
# table; the walk then starts over. False when a `hash` raised.
sig [Value] => Bool
machine def zr_hash_recode(h)
  code = Machine.slot(8)
  gen = RHash.gen(h)
  i = 0
  while i < RHash.len(h)
    if HEntry.live(RHash.entries(h) + (i * HEntry.size)) != 0
      unless zr_key_hash(h, HEntry.key(RHash.entries(h) + (i * HEntry.size)), code)
        return false
      end
      if RHash.gen(h) != gen
        gen = RHash.gen(h)
        i = 0
      else
        HEntry.set_hash(RHash.entries(h) + (i * HEntry.size), Machine.load64(code, 0))
        i += 1
      end
    else
      i += 1
    end
  end
  if RHash.cap(h) > 0
    zr_hash_rebins(h)
  end
  true
end

# `h[key] = value` for the runtime: the value, or undef when the key's
# own `hash` or `eql?` raised.
sig [Value, Value, Value] => Value
machine def zr_hash_store(h, key, value)
  slot = Machine.slot(8)
  unless zr_key_hash(h, key, slot)
    return Machine.value(QUNDEF)
  end
  code = Machine.load64(slot, 0)
  e = zr_hash_find(h, key, code)
  if e == HASH_RAISED
    return Machine.value(QUNDEF)
  end
  if e != 0
    HEntry.set_value(e, value)
    return value
  end
  if !zr_special_p(key) && zr_type(key) == T_STRING && !zr_frozen_p(key) && (RBasic.flags(h) & (FL_IDENTITY | FL_WEAKKEY)) == 0
    copy = zr_str_copy_encoding(zr_str_new(RString.ptr(key), RString.len(key)), key)
    # The frozen copy keeps a subclass, as CRuby's rb_str_new_frozen does.
    RBasic.set_klass(copy, zr_real_class(key))
    key = copy
    RBasic.set_flags(key, RBasic.flags(key) | FL_FREEZE)
  end
  zr_hash_reserve(h)
  n = RHash.len(h)
  e = RHash.entries(h) + (n * HEntry.size)
  HEntry.set_key(e, key)
  HEntry.set_value(e, value)
  HEntry.set_live(e, 1)
  HEntry.set_hash(e, code)
  RHash.set_len(h, n + 1)
  RHash.set_live(h, RHash.live(h) + 1)
  zr_hash_bin(h, n)
  value
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
  e = zr_hash_entry(recv, key)
  if e == HASH_RAISED
    return Machine.value(QUNDEF)
  end
  if e == 0
    return zr_hash_missing(recv, key)
  end
  HEntry.value(e)
end

# The value for a missing `key`, as rb_hash_default_value answers it: a
# `default` of the receiver's own is called, and otherwise the default
# proc's answer or the default.
sig [Value, Value] => Value
machine def zr_hash_missing(h, key)
  if zr_basic_method_p(h, Machine.id(:default))
    return zr_hash_default(h, key)
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(key))
  zr_send(h, Machine.id(:default), 1, slot)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_aset(recv, argc, argv, cref, blk)
  if zr_modify_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  value = Machine.value(Machine.load64(argv, 8))
  key = Machine.value(Machine.load64(argv, 0))
  if RHash.iter(recv) != 0
    e = zr_hash_entry(recv, key)
    if e == HASH_RAISED
      return Machine.value(QUNDEF)
    end
    if e == 0
      return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("can't add a new key into hash during iteration"), 46)
    end
  end
  zr_hash_store(recv, key, value)
end

# `fetch(key)`, `fetch(key, default)`, `fetch(key) { |key| }`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_fetch(recv, argc, argv, cref, blk)
  if argc < 1 || argc > 2
    return zr_wrong_arity_range(argc, 1, 2)
  end
  if blk != QNIL && argc == 2
    zr_warn_here(Machine.bytes("block supersedes default value argument"), 39)
  end
  key = Machine.value(Machine.load64(argv, 0))
  found = zr_hash_entry(recv, key)
  if found == HASH_RAISED
    return Machine.value(QUNDEF)
  end
  if found != 0
    return HEntry.value(found)
  end
  if blk != QNIL
    return zr_yield1(blk, key)
  end
  if argc == 2
    return Machine.value(Machine.load64(argv, 8))
  end
  s = zr_inspect(key)
  return s if s == QUNDEF
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("key not found: "), 15)
  zr_buf_str(b, s)
  e = zr_exc_new(zr_global(G_KEY_ERROR), zr_buf_take(b))
  zr_exc_detail(e, Machine.id(:key), key)
  zr_exc_detail(e, Machine.id(:receiver), recv)
  zr_raise(e)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_key_p(recv, argc, argv, cref, blk)
  e = zr_hash_entry(recv, Machine.value(Machine.load64(argv, 0)))
  if e == HASH_RAISED
    return Machine.value(QUNDEF)
  end
  zr_bool(e != 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_delete(recv, argc, argv, cref, blk)
  if zr_modify_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  e = zr_hash_entry(recv, Machine.value(Machine.load64(argv, 0)))
  if e == HASH_RAISED
    return Machine.value(QUNDEF)
  end
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

# The live count as a fixnum, for core code that must not dispatch.
sig [Value] => Value
machine def zr_hash_len_m(h)
  zr_fix(RHash.live(h))
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

# Whether `each` can hand a block the key and the value as two
# arguments rather than the `[key, value]` Array ruby yields.
#
# It can when the block would have taken that Array apart again: a
# `spread` block binds a lone Array over its parameters, so two
# arguments reach the same names. A lambda is not one of those -- it
# binds strictly and `h.each(&->(k, v) { })` is an ArgumentError in
# ruby, which only happens if it is handed one argument. Nor is
# `{ |pair| }` or `{ |*x| }`, and `spread` already says so.
#
# The Array is what `each` spends: a cell and a malloc for every entry
# of every iteration, thrown away at the end of the block.
sig [Value] => Bool
machine def zr_block_takes_pair(blk)
  RProc.spread(blk) != 0 && RProc.lambda(blk) == 0
end

# `each`: one `[key, value]` per entry, re-reading the table after every
# yield, since the block may change it.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_each(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_enum_for(recv, Machine.id(:each), argc, argv, zr_fix(RHash.live(recv)))
  end
  pairless = zr_block_takes_pair(blk)
  RHash.set_iter(recv, RHash.iter(recv) + 1)
  i = 0
  while i < RHash.len(recv)
    e = RHash.entries(recv) + (i * HEntry.size)
    if HEntry.live(e) != 0
      r = pairless ? zr_yield2(blk, HEntry.key(e), HEntry.value(e)) : zr_yield1(blk, zr_hash_assoc(e))
      if r == QUNDEF
        RHash.set_iter(recv, RHash.iter(recv) - 1)
        return r
      end
    end
    i += 1
  end
  RHash.set_iter(recv, RHash.iter(recv) - 1)
  recv
end

# rb_hash_foreach: `blk` over each pair of `h`'s own table, as `each`
# walks it, whatever a subclass writes over `each`.
sig [Value, Value] => Value
machine def zr_hash_foreach(h, blk)
  zr_hash_each(h, 0, 0, Machine.value(QNIL), blk)
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
  if n == 0 || zr_symbol_tag(id) != 0
    return false
  end
  c = Machine.word(Machine.load8(p, 0))
  unless (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 128
    return false
  end
  i = 1
  while i < n
    c = Machine.word(Machine.load8(p + i, 0))
    unless zr_alnum_p(c) || c == 95 || c >= 128
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
    return zr_usascii_str_new(Machine.bytes("{}"), 2)
  end
  if zr_guard_enter(recv, Machine.id(:inspect))
    return zr_usascii_str_new(Machine.bytes("{...}"), 5)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_byte(b, 123)
  # The text takes the first key's encoding, and each piece after joins
  # it, as inspect_i appends them.
  index = ENC_USASCII
  ascii = true
  first = true
  i = 0
  while i < RHash.len(recv)
    e = RHash.entries(recv) + (i * HEntry.size)
    if HEntry.live(e) != 0
      unless first
        zr_buf_push(b, Machine.bytes(", "), 2)
      end
      key = HEntry.key(e)
      if zr_symbol_p(key)
        id = zr_sym2id(key)
        name_ascii = zr_bytes_ascii_only_p(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
        name_index = name_ascii ? ENC_USASCII : zr_symbol_encoding_index(id)
        if first
          index = name_index
        elsif zr_symbol_name_len(id) > 0
          index = zr_enc_append(index, ascii, Buf.len(b), name_index, name_ascii)
        end
        ascii = ascii && name_ascii
        if zr_symbol_key_simple_p(key)
          zr_buf_sym(b, zr_sym2id(key))
        else
          zr_buf_str_escaped(b, zr_symbol_name_ptr(zr_sym2id(key)), zr_symbol_name_len(zr_sym2id(key)), zr_symbol_tag(zr_sym2id(key)) != 0)
        end
        zr_buf_push(b, Machine.bytes(": "), 2)
      else
        s = zr_inspect(key)
        if s == QUNDEF
          free(Buf.ptr(b))
          zr_guard_leave(recv, Machine.id(:inspect))
          return s
        end
        index = first ? zr_str_encoding_index(s) : zr_enc_append_str(index, ascii, Buf.len(b), s)
        ascii = ascii && zr_str_ascii_bytes_p(s)
        zr_buf_str(b, s)
        zr_buf_push(b, Machine.bytes(" => "), 4)
      end
      e = RHash.entries(recv) + (i * HEntry.size)
      s = zr_inspect(HEntry.value(e))
      if s == QUNDEF
        free(Buf.ptr(b))
        zr_guard_leave(recv, Machine.id(:inspect))
        return s
      end
      index = zr_enc_append_str(index, ascii, Buf.len(b), s)
      ascii = ascii && zr_str_ascii_bytes_p(s)
      zr_buf_str(b, s)
      first = false
    end
    i += 1
  end
  zr_buf_byte(b, 125)
  zr_guard_leave(recv, Machine.id(:inspect))
  zr_str_set_index(zr_buf_take(b), index)
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
  # The same two Hashes compared again inside their own comparison is a
  # recursion, which answers equal (rb_exec_recursive_paired).
  if recv == other || zr_guard_enter_paired(recv, other, Machine.id(:==))
    return Machine.value(QTRUE)
  end
  r = zr_hash_eq_entries(recv, other)
  zr_guard_leave(recv, Machine.id(:==))
  r
end

sig [Value, Value] => Value
machine def zr_hash_eq_entries(recv, other)
  i = 0
  while i < RHash.len(recv)
    e = RHash.entries(recv) + (i * HEntry.size)
    if HEntry.live(e) != 0
      found = zr_hash_entry(other, HEntry.key(e))
      if found == HASH_RAISED
        return Machine.value(QUNDEF)
      end
      if found == 0
        return Machine.value(QFALSE)
      end
      r = zr_rb_equal(HEntry.value(RHash.entries(recv) + (i * HEntry.size)), HEntry.value(found))
      return r if r == QUNDEF
      if r == QFALSE
        return Machine.value(QFALSE)
      end
    end
    i += 1
  end
  Machine.value(QTRUE)
end

# `Hash#initialize`: `Hash.new`, `Hash.new(default)`, `Hash.new { |hash, key| }`.
# rb_hash_init: a default proc from the block, or the default value
# `ifnone`, which a block leaves no room for. `unset` is true where no
# default value was given. The capacity only reserves room.
sig [Value, Value, Value, Value, Value] => Value
machine def zr_hash_init(recv, capacity, unset, ifnone, blk)
  if zr_modify_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  if capacity != zr_fix(0)
    out = Machine.slot(8)
    r = zr_index_operand(capacity, out)
    return r if r == QUNDEF
  end
  if blk != QNIL
    if unset != QTRUE
      return zr_wrong_arity(1, 0)
    end
    RHash.set_default(recv, Machine.value(QNIL))
    RHash.set_default_proc(recv, blk)
    return recv
  end
  RHash.set_default(recv, unset == QTRUE ? Machine.value(QNIL) : ifnone)
  RHash.set_default_proc(recv, Machine.value(QNIL))
  recv
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
    r = zr_hash_store(h, Machine.value(Machine.load64(argv + (i * 16), 0)), Machine.value(Machine.load64(argv + (i * 16), 8)))
    return r if r == QUNDEF
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
# `**nil`: any keyword at all is refused.
sig [Value] => Value
machine def zr_kw_none(hash)
  if hash == QNIL || RHash.live(hash) == 0
    return Machine.value(QNIL)
  end
  zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no keywords accepted"), 20)
end

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
      s = zr_inspect(HEntry.key(RHash.entries(hash) + (i * HEntry.size)))
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
      r = zr_hash_store(out, HEntry.key(e), HEntry.value(e))
      return r if r == QUNDEF
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
    if !zr_special_p(other) && zr_find_method(zr_class_of(other), Machine.id(:to_hash)) != 0
      converted = zr_send(other, Machine.id(:to_hash), 0, 0)
      return converted if converted == QUNDEF
      if !zr_special_p(converted) && zr_type(converted) == T_HASH
        return zr_hash_update(h, converted)
      end
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("can't convert "), 14)
      zr_buf_class_of(b, other)
      zr_buf_push(b, Machine.bytes(" to Hash ("), 10)
      zr_buf_class_of(b, other)
      zr_buf_push(b, Machine.bytes("#to_hash gives "), 15)
      zr_buf_class_of(b, converted)
      zr_buf_push(b, Machine.bytes(")"), 1)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
    zr_buf_class_of(b, other)
    zr_buf_push(b, Machine.bytes(" into Hash"), 10)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  i = 0
  while i < RHash.len(other)
    e = RHash.entries(other) + (i * HEntry.size)
    if HEntry.live(e) != 0
      r = zr_hash_store(h, HEntry.key(e), HEntry.value(e))
      return r if r == QUNDEF
    end
    i += 1
  end
  h
end

# The keywords of an array literal made only of `**` splats: `[h]` to
# splat into the literal, or `[]` when `h` is empty, as CRuby's
# pushtoarraykwsplat adds no element for an empty Hash.
sig [Value] => Value
machine def zr_ary_kw_element(h)
  if RHash.live(h) == 0
    return zr_ary_new(0)
  end
  a = zr_ary_new(1)
  zr_ary_push(a, h)
  a
end

# The primitives rt/core/hash.rb builds on.
sig [Value] => Value
machine def zr_hash_default_proc(h)
  RHash.default_proc(h)
end

sig [Value, Value] => Value
machine def zr_hash_set_default(h, v)
  if zr_modify_frozen_p(h)
    return zr_frozen_error(h)
  end
  RHash.set_default(h, v)
  RHash.set_default_proc(h, Machine.value(QNIL))
  v
end

sig [Value, Value] => Value
machine def zr_hash_set_default_proc(h, p)
  if zr_modify_frozen_p(h)
    return zr_frozen_error(h)
  end
  RHash.set_default_proc(h, p)
  RHash.set_default(h, Machine.value(QNIL))
  p
end

# Every entry dropped; the defaults stay.
sig [Value] => Value
machine def zr_hash_clear(h)
  if zr_modify_frozen_p(h)
    return zr_frozen_error(h)
  end
  i = 0
  while i < RHash.len(h)
    HEntry.set_live(RHash.entries(h) + (i * HEntry.size), 0)
    i += 1
  end
  RHash.set_len(h, 0)
  RHash.set_live(h, 0)
  RHash.set_gen(h, RHash.gen(h) + 1)
  i = 0
  while i < RHash.nbins(h)
    Machine.store64(RHash.bins(h) + (i * 8), 0, 0)
    i += 1
  end
  h
end

# `compare_by_identity`: from now on a key matches only itself.
sig [Value] => Value
machine def zr_hash_compare_by_identity(h)
  if (RBasic.flags(h) & FL_IDENTITY) != 0
    return h
  end
  if zr_modify_frozen_p(h)
    return zr_frozen_error(h)
  end
  if RHash.iter(h) != 0
    return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("compare_by_identity during iteration"), 36)
  end
  RBasic.set_flags(h, RBasic.flags(h) | FL_IDENTITY)
  zr_hash_recode(h)
  h
end

sig [Value] => Value
machine def zr_hash_iterating_p(h)
  zr_bool(RHash.iter(h) != 0)
end

# compare_by_identity on or off, as `replace` takes it from the other
# Hash; the codes are made again for the keys already here.
sig [Value, Value] => Value
machine def zr_hash_set_identity(h, on)
  if on != QNIL && on != QFALSE
    RBasic.set_flags(h, RBasic.flags(h) | FL_IDENTITY)
  else
    RBasic.set_flags(h, RBasic.flags(h) & (0 - FL_IDENTITY - 1))
  end
  zr_hash_recode(h)
  h
end

# `rehash`: the codes computed again after keys changed under the table.
sig [Value] => Value
machine def zr_hash_rehash(h)
  if zr_modify_frozen_p(h)
    return zr_frozen_error(h)
  end
  if RHash.iter(h) != 0
    return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("rehash during iteration"), 23)
  end
  unless zr_hash_recode(h)
    return Machine.value(QUNDEF)
  end
  h
end

sig [Value] => Value
machine def zr_hash_identity_p(h)
  zr_bool((RBasic.flags(h) & FL_IDENTITY) != 0)
end

# The default value alone, for the core.
sig [Value] => Value
machine def zr_hash_default_value(h)
  RHash.default(h)
end

# `h[key]`, `h[key] = value`, `key?`, `fetch` and `replace` for the core,
# which reach the table as rb_hash_aref, rb_hash_aset, rb_hash_has_key,
# rb_hash_fetch and rb_hash_replace do: never through a method a subclass
# can replace.
sig [Value, Value] => Value
machine def zr_hash_aref_m(h, key)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(key))
  zr_hash_aref(h, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
end

sig [Value, Value, Value] => Value
machine def zr_hash_aset_m(h, key, value)
  slot = Machine.slot(16)
  Machine.store64(slot, 0, Machine.word(key))
  Machine.store64(slot, 8, Machine.word(value))
  zr_hash_aset(h, 2, slot, Machine.value(QNIL), Machine.value(QNIL))
end

sig [Value, Value] => Value
machine def zr_hash_key_p_m(h, key)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(key))
  zr_hash_key_p(h, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
end

sig [Value, Value, Value] => Value
machine def zr_hash_fetch_m(h, key, blk)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(key))
  zr_hash_fetch(h, 1, slot, Machine.value(QNIL), blk)
end

sig [Value, Value] => Value
machine def zr_hash_replace_m(h, other)
  zr_hash_copy_from(h, other)
end

# `delete(key)` for the core: the value, or nil.
sig [Value, Value] => Value
machine def zr_hash_delete_m(h, key)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(key))
  zr_hash_delete(h, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
end
