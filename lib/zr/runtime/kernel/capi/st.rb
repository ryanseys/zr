module Zr::Kern
  # The C API's st tables, which C uses for its own maps. A table's type
  # (st_hash_type) compares and hashes its keys: a numtable's keys are
  # words compared as they are (type 0 here), a strtable's are C strings,
  # and C can give a type of its own. A table has CRuby's public
  # header (st.h), so C reads `num_entries` inline; the rest is zr's own.
  # The entries are in insertion order, as st keeps them, for
  # st_foreach: each is a key, a value and a live word. An index of
  # open addressing finds a key: each slot is an entry's index plus one,
  # or 0 for none.
  class StTable < Layout
    # In st's entry_power, bin_power, size_ind and rebuilds_num, which C
    # does not read, zr keeps the entries' room.
    attr_accessor :room #: word
    attr_accessor :type #: ptr
    attr_accessor :num_entries #: word
    # zr's index, its slot count, the entries in use or dead, and the
    # entries (st's bins, entries_start, entries_bound and entries).
    attr_accessor :bins #: ptr
    attr_accessor :nbins #: word
    attr_accessor :used #: word
    attr_accessor :entries #: ptr
  end

  class StEntry < Layout
    attr_accessor :key #: word
    attr_accessor :value #: word
    attr_accessor :live #: word
  end

  # struct st_hash_type: `compare(a, b)`, 0 for equal keys, and `hash(key)`.
  class StHashType < Layout
    attr_accessor :compare #: ptr
    attr_accessor :hash #: ptr
  end

  # rb_hash_tbl: the Hash's st table, as RHASH_TBL gives it. The table is
  # a view: the st functions see that it has no room of its own and work
  # on the Hash, so what C stores with st_insert is in the Hash. Its
  # `entries` word is the Hash, and its type compares keys with `eql?`
  # and hashes them with `hash`, as CRuby's objhash does. One view stays
  # for each Hash address, so C can ask for the table again and again.
  #: (value, ptr, i32) -> ptr
  def rb_hash_tbl(hash, file, line)
    Machine.gates_enter
    zr_c_entered()
    views = Machine.static(:st_views, 8)
    if Machine.load64(views, 0) == 0
      Machine.store64(views, 0, Machine.word(zr_st_new(8)))
    end
    table = Machine.ptr(Machine.load64(views, 0))
    e = zr_st_find(table, Machine.word(hash))
    view = e == 0 ? zr_st_view_new(table, hash) : Machine.ptr(StEntry[e].value)
    StTable[view].num_entries = RHash[hash].live
    view
  end

  #: (ptr, value) -> ptr
  def zr_st_view_new(table, hash)
    view = zr_xmalloc(StTable.size)
    Libc.memset(view, Machine.i32(0), StTable.size)
    StTable[view].type = zr_st_objtype()
    StTable[view].entries = Machine.ptr(Machine.word(hash))
    zr_st_add(table, Machine.word(hash), Machine.word(view))
    view
  end

  # The Hash that `tab` is a view of, or nil for a table of C's own.
  #: (ptr) -> value
  def zr_st_viewed(tab)
    StTable[tab].room == 0 ? Machine.value(Machine.word(StTable[tab].entries)) : Machine.value(QNIL)
  end

  # The entry of `key` in the Hash, raising what its `hash` or `eql?`
  # raised.
  #: (value, word) -> ptr
  def zr_st_view_find(hash, key)
    e = zr_hash_entry(hash, Machine.value(key))
    if e == HASH_RAISED
      zr_c_unwind()
    end
    e
  end

  # The type of a view: objhash's compare and hash.
  #: () -> ptr
  def zr_st_objtype
    type = Machine.static(:st_objtype, 16)
    StHashType[type].compare = Machine.addr(:zr_capi_st_objcmp)
    StHashType[type].hash = Machine.addr(:zr_capi_st_objhash)
    type
  end

  #: (word, word) -> i32
  def zr_capi_st_objcmp(a, b)
    Machine.gates_enter
    zr_c_entered()
    same = a == b || zr_capi_call1(Machine.value(a), Machine.id(:eql?), Machine.value(b)) == QTRUE
    same ? Machine.i32(0) : Machine.i32(1)
  end

  #: (word) -> word
  def zr_capi_st_objhash(key)
    Machine.gates_enter
    zr_c_entered()
    code = zr_c_result(zr_send(Machine.value(key), Machine.id(:hash), 0, Machine.ptr(0)))
    zr_fixnum_p(code) ? zr_fix2long(code) : Machine.word(code)
  end

  # rb_st_init_table and rb_st_init_table_with_size: a table whose keys
  # the C functions of `type` compare and hash.
  #: (ptr) -> ptr
  def rb_st_init_table(type)
    Machine.gates_enter
    zr_c_entered()
    zr_st_typed(type, 8)
  end

  #: (ptr, word) -> ptr
  def rb_st_init_table_with_size(type, size)
    Machine.gates_enter
    zr_c_entered()
    zr_st_typed(type, size)
  end

  # rb_st_init_strtable and rb_st_init_strcasetable (each also
  # _with_size): a table whose keys are C strings, compared by their
  # bytes or with ASCII letters folded.
  #: () -> ptr
  def rb_st_init_strtable
    Machine.gates_enter
    zr_c_entered()
    zr_st_typed(zr_st_strtype(), 8)
  end

  #: (word) -> ptr
  def rb_st_init_strtable_with_size(size)
    Machine.gates_enter
    zr_c_entered()
    zr_st_typed(zr_st_strtype(), size)
  end

  #: () -> ptr
  def rb_st_init_strcasetable
    Machine.gates_enter
    zr_c_entered()
    zr_st_typed(zr_st_strcasetype(), 8)
  end

  #: (word) -> ptr
  def rb_st_init_strcasetable_with_size(size)
    Machine.gates_enter
    zr_c_entered()
    zr_st_typed(zr_st_strcasetype(), size)
  end

  #: (ptr, word) -> ptr
  def zr_st_typed(type, size)
    tab = zr_st_new(size)
    StTable[tab].type = type
    tab
  end

  # The types of a strtable and a strcasetable, made once. Their
  # functions are the defs below, which C can call through the type too.
  #: () -> ptr
  def zr_st_strtype
    type = Machine.static(:st_strtype, 16)
    StHashType[type].compare = Machine.addr(:zr_capi_st_strcmp)
    StHashType[type].hash = Machine.addr(:zr_capi_st_strhash)
    type
  end

  #: () -> ptr
  def zr_st_strcasetype
    type = Machine.static(:st_strcasetype, 16)
    StHashType[type].compare = Machine.addr(:zr_capi_st_strcasecmp)
    StHashType[type].hash = Machine.addr(:zr_capi_st_strcasehash)
    type
  end

  # A strtable's compare and hash: the bytes of two C strings, and FNV-1a
  # over the bytes of one.
  #: (ptr, ptr) -> i32
  def zr_capi_st_strcmp(a, b)
    Machine.gates_enter
    zr_c_entered()
    la = zr_cstr_len(a)
    zr_bytes_eq(a, la, b, zr_cstr_len(b)) ? Machine.i32(0) : Machine.i32(1)
  end

  #: (ptr) -> word
  def zr_capi_st_strhash(s)
    Machine.gates_enter
    zr_c_entered()
    zr_st_cstr_hash(s, false)
  end

  # A strcasetable's: the same with ASCII letters folded.
  #: (ptr, ptr) -> i32
  def zr_capi_st_strcasecmp(a, b)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_casecmp(a, b, 0 - 1) == 0 ? Machine.i32(0) : Machine.i32(1)
  end

  #: (ptr) -> word
  def zr_capi_st_strcasehash(s)
    Machine.gates_enter
    zr_c_entered()
    zr_st_cstr_hash(s, true)
  end

  #: (ptr, bool) -> word
  def zr_st_cstr_hash(s, fold)
    hash = Machine.word(0xcbf29ce484222325)
    at = s
    while Machine.load8(at, 0) != Machine.i8(0)
      c = Machine.word(Machine.u8(Machine.load8(at, 0)))
      hash = Machine.mul_wrap(hash ^ (fold ? zr_capi_fold(c) : c), 0x100000001b3)
      at += 1
    end
    hash
  end

  # The hash of `key` in `tab`, and whether two keys are one: a numtable
  # reads the word; a typed table calls its type's functions.
  #: (ptr, word) -> word
  def zr_st_key_hash(tab, key)
    type = StTable[tab].type
    if type == 0
      return zr_st_hash(key)
    end
    args = Machine.slot(64)
    Machine.store64(args, 0, key)
    zr_st_hash(zr_call_c(StHashType[type].hash, args, 1))
  end

  #: (ptr, word, word) -> bool
  def zr_st_key_eq(tab, a, b)
    type = StTable[tab].type
    if a == b || type == 0
      return a == b
    end
    args = Machine.slot(64)
    Machine.store64(args, 0, a)
    Machine.store64(args, 8, b)
    Machine.i32(zr_call_c(StHashType[type].compare, args, 2)) == Machine.i32(0)
  end

  # rb_st_copy: a new table with the entries of `old`, and its type.
  #: (ptr) -> ptr
  def rb_st_copy(old)
    Machine.gates_enter
    zr_c_entered()
    hash = zr_st_viewed(old)
    if hash != QNIL
      return zr_st_view_copy(hash)
    end
    tab = zr_st_typed(StTable[old].type, StTable[old].room)
    i = 0
    while i < StTable[old].used
      e = StTable[old].entries + (i * StEntry.size)
      if StEntry[e].live != 0
        zr_st_add(tab, StEntry[e].key, StEntry[e].value)
      end
      i += 1
    end
    tab
  end

  # A table of C's own with the pairs of `hash`, as st_copy of a Hash's
  # table gives.
  #: (value) -> ptr
  def zr_st_view_copy(hash)
    tab = zr_st_typed(zr_st_objtype(), RHash[hash].live)
    i = 0
    while i < RHash[hash].len
      e = RHash[hash].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        zr_st_add(tab, Machine.word(HEntry[e].key), Machine.word(HEntry[e].value))
      end
      i += 1
    end
    tab
  end

  # rb_st_memsize: the bytes that the table holds.
  #: (ptr) -> word
  def rb_st_memsize(tab)
    Machine.gates_enter
    zr_c_entered()
    hash = zr_st_viewed(tab)
    if hash != QNIL
      return StTable.size + (RHash[hash].cap * HEntry.size) + (RHash[hash].nbins * 8)
    end
    StTable.size + (StTable[tab].room * StEntry.size) + (StTable[tab].nbins * 8)
  end

  # rb_st_init_numtable_with_size: a new numtable with room for `size`
  # entries.
  #: (word) -> ptr
  def rb_st_init_numtable_with_size(size)
    Machine.gates_enter
    zr_c_entered()
    zr_st_new(size)
  end

  #: () -> ptr
  def rb_st_init_numtable
    Machine.gates_enter
    zr_c_entered()
    zr_st_new(8)
  end

  # rb_st_insert: sets `key` to `value`. Returns 1 when the key was there.
  #: (ptr, word, word) -> i32
  def rb_st_insert(tab, key, value)
    Machine.gates_enter
    zr_c_entered()
    hash = zr_st_viewed(tab)
    if hash != QNIL
      had = zr_st_view_find(hash, key) != 0
      zr_c_result(zr_hash_store(hash, Machine.value(key), Machine.value(value)))
      StTable[tab].num_entries = RHash[hash].live
      return had ? Machine.i32(1) : Machine.i32(0)
    end
    e = zr_st_find(tab, key)
    if e != 0
      StEntry[e].value = value
      return Machine.i32(1)
    end
    zr_st_add(tab, key, value)
    Machine.i32(0)
  end

  # rb_st_lookup: whether `key` is there; its value goes to `*value`.
  #: (ptr, word, ptr) -> i32
  def rb_st_lookup(tab, key, value)
    Machine.gates_enter
    zr_c_entered()
    hash = zr_st_viewed(tab)
    if hash != QNIL
      return zr_st_view_lookup(hash, key, value)
    end
    e = zr_st_find(tab, key)
    if e == 0
      return Machine.i32(0)
    end
    if value != 0
      Machine.store64(value, 0, StEntry[e].value)
    end
    Machine.i32(1)
  end

  #: (value, word, ptr) -> i32
  def zr_st_view_lookup(hash, key, value)
    e = zr_st_view_find(hash, key)
    if e == 0
      return Machine.i32(0)
    end
    if value != 0
      Machine.store64(value, 0, Machine.word(HEntry[e].value))
    end
    Machine.i32(1)
  end

  # rb_st_delete: removes `*key`; its value goes to `*value`.
  #: (ptr, ptr, ptr) -> i32
  def rb_st_delete(tab, key, value)
    Machine.gates_enter
    zr_c_entered()
    hash = zr_st_viewed(tab)
    if hash != QNIL
      e = zr_st_view_find(hash, Machine.load64(key, 0))
      if value != 0
        Machine.store64(value, 0, e == 0 ? 0 : Machine.word(HEntry[e].value))
      end
      if e == 0
        return Machine.i32(0)
      end
      zr_hash_remove(hash, e)
      StTable[tab].num_entries = RHash[hash].live
      return Machine.i32(1)
    end
    e = zr_st_find(tab, Machine.load64(key, 0))
    if e == 0
      if value != 0
        Machine.store64(value, 0, 0)
      end
      return Machine.i32(0)
    end
    if value != 0
      Machine.store64(value, 0, StEntry[e].value)
    end
    zr_st_kill(tab, e)
    Machine.i32(1)
  end

  # rb_st_foreach: calls `fn(key, value, arg)` for each entry in order;
  # its answer goes on, stops, or deletes the entry (ST_DELETE).
  #: (ptr, ptr, word) -> i32
  def rb_st_foreach(tab, fn, arg)
    Machine.gates_enter
    zr_c_entered()
    hash = zr_st_viewed(tab)
    if hash != QNIL
      zr_capi_hash_foreach(hash, fn, arg)
      StTable[tab].num_entries = RHash[hash].live
      return Machine.i32(0)
    end
    argv = Machine.slot(64)
    Machine.store64(argv, 16, arg)
    i = 0
    while i < StTable[tab].used
      e = StTable[tab].entries + (i * StEntry.size)
      if StEntry[e].live != 0
        Machine.store64(argv, 0, StEntry[e].key)
        Machine.store64(argv, 8, StEntry[e].value)
        r = zr_call_c(fn, argv, 3)
        if r == QUNDEF
          zr_c_unwind()
        end
        answer = Machine.sword(Machine.i32(r))
        if answer == ST_STOP
          return Machine.i32(0)
        end
        if answer == ST_DELETE
          zr_st_kill(tab, StTable[tab].entries + (i * StEntry.size))
        end
      end
      i += 1
    end
    Machine.i32(0)
  end

  # rb_st_update: calls `fn(&key, &value, arg, existing)` with the entry
  # of `key`, or with `key` and an unset value when there is none. Its
  # answer stores what it left in the two (ST_CONTINUE) or deletes the
  # entry (ST_DELETE). Returns whether the entry was there.
  #: (ptr, word, ptr, word) -> i32
  def rb_st_update(tab, key, fn, arg)
    Machine.gates_enter
    zr_c_entered()
    hash = zr_st_viewed(tab)
    if hash != QNIL
      return zr_st_view_update(tab, hash, key, fn, arg)
    end
    e = zr_st_find(tab, key)
    existing = e != 0 ? 1 : 0
    argv = Machine.slot(64)
    pair = Machine.slot(16)
    Machine.store64(pair, 0, key)
    Machine.store64(pair, 8, existing != 0 ? StEntry[e].value : 0)
    Machine.store64(argv, 0, Machine.word(pair))
    Machine.store64(argv, 8, Machine.word(pair + 8))
    Machine.store64(argv, 16, arg)
    Machine.store64(argv, 24, existing)
    r = zr_call_c(fn, argv, 4)
    if r == QUNDEF
      zr_c_unwind()
    end
    answer = Machine.sword(Machine.i32(r))
    if answer == ST_CONTINUE
      if existing == 0
        zr_st_add(tab, Machine.load64(pair, 0), Machine.load64(pair, 8))
      else
        StEntry[e].key = Machine.load64(pair, 0)
        StEntry[e].value = Machine.load64(pair, 8)
      end
    elsif answer == ST_DELETE && existing != 0
      zr_st_kill(tab, e)
    end
    Machine.i32(existing)
  end

  # rb_st_update on a Hash's view: the same answers, which store into the
  # Hash or delete from it.
  #: (ptr, value, word, ptr, word) -> i32
  def zr_st_view_update(tab, hash, key, fn, arg)
    e = zr_st_view_find(hash, key)
    existing = e != 0 ? 1 : 0
    argv = Machine.slot(64)
    pair = Machine.slot(16)
    Machine.store64(pair, 0, key)
    Machine.store64(pair, 8, existing != 0 ? Machine.word(HEntry[e].value) : 0)
    Machine.store64(argv, 0, Machine.word(pair))
    Machine.store64(argv, 8, Machine.word(pair + 8))
    Machine.store64(argv, 16, arg)
    Machine.store64(argv, 24, existing)
    r = zr_call_c(fn, argv, 4)
    if r == QUNDEF
      zr_c_unwind()
    end
    answer = Machine.sword(Machine.i32(r))
    if answer == ST_CONTINUE
      zr_c_result(zr_hash_store(hash, Machine.value(Machine.load64(pair, 0)), Machine.value(Machine.load64(pair, 8))))
    elsif answer == ST_DELETE && existing != 0
      e = zr_st_view_find(hash, key)
      if e != 0
        zr_hash_remove(hash, e)
      end
    end
    StTable[tab].num_entries = RHash[hash].live
    Machine.i32(existing)
  end

  # rb_st_clear: removes every entry.
  #: (ptr) -> void
  def rb_st_clear(tab)
    Machine.gates_enter
    zr_c_entered()
    hash = zr_st_viewed(tab)
    if hash != QNIL
      zr_hash_empty(hash)
      StTable[tab].num_entries = 0
      return
    end
    StTable[tab].used = 0
    StTable[tab].num_entries = 0
    Libc.memset(StTable[tab].bins, Machine.i32(0), StTable[tab].nbins * 8)
  end

  # rb_st_free_table: frees the table and its entries. A Hash's view
  # stays, as the Hash owns it.
  #: (ptr) -> void
  def rb_st_free_table(tab)
    Machine.gates_enter
    zr_c_entered()
    if StTable[tab].room == 0
      return
    end
    zr_xfree(StTable[tab].bins)
    zr_xfree(StTable[tab].entries)
    zr_xfree(tab)
  end

  # rb_st_locale_insensitive_strcasecmp and _strncasecmp: compare C
  # strings with ASCII letters folded, as st.c does whatever the locale.
  #: (ptr, ptr) -> i32
  def rb_st_locale_insensitive_strcasecmp(a, b)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_casecmp(a, b, 0 - 1))
  end

  #: (ptr, ptr, word) -> i32
  def rb_st_locale_insensitive_strncasecmp(a, b, n)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_casecmp(a, b, n))
  end

  # -1, 0 or 1 as `a` sorts before, with or after `b` by their first `n`
  # bytes (all for -1), each ASCII capital as its small letter.
  #: (ptr, ptr, word) -> word
  def zr_capi_casecmp(a, b, n)
    i = 0
    while n < 0 || i < n
      x = zr_capi_fold(Machine.word(Machine.u8(Machine.load8(a + i, 0))))
      y = zr_capi_fold(Machine.word(Machine.u8(Machine.load8(b + i, 0))))
      if x != y
        return x < y ? 0 - 1 : 1
      end
      if x == 0
        return 0
      end
      i += 1
    end
    0
  end

  #: (word) -> word
  def zr_capi_fold(c)
    c >= 65 && c <= 90 ? c + 32 : c
  end

  # A new table with room for `size` entries before it grows.
  #: (word) -> ptr
  def zr_st_new(size)
    tab = zr_xmalloc(StTable.size)
    Libc.memset(tab, Machine.i32(0), StTable.size)
    capacity = size < 8 ? 8 : size
    StTable[tab].entries = zr_xmalloc(capacity * StEntry.size)
    StTable[tab].room = capacity
    zr_st_index(tab, capacity * 2)
    tab
  end

  # The live entry of `key`, or 0.
  #: (ptr, word) -> ptr
  def zr_st_find(tab, key)
    mask = StTable[tab].nbins - 1
    at = zr_st_key_hash(tab, key) & mask
    while true
      slot = Machine.load64(StTable[tab].bins + (at * 8), 0)
      if slot == 0
        return Machine.ptr(0)
      end
      e = StTable[tab].entries + ((slot - 1) * StEntry.size)
      if StEntry[e].live != 0 && zr_st_key_eq(tab, StEntry[e].key, key)
        return e
      end
      at = (at + 1) & mask
    end
    Machine.ptr(0)
  end

  # Appends a new entry, growing the entries and the index as needed.
  #: (ptr, word, word) -> void
  def zr_st_add(tab, key, value)
    n = StTable[tab].used
    if n == StTable[tab].room
      capacity = n * 2
      entries = zr_xmalloc(capacity * StEntry.size)
      zr_memcpy(entries, StTable[tab].entries, n * StEntry.size)
      zr_xfree(StTable[tab].entries)
      StTable[tab].entries = entries
      StTable[tab].room = capacity
    end
    e = StTable[tab].entries + (n * StEntry.size)
    StEntry[e].key = key
    StEntry[e].value = value
    StEntry[e].live = 1
    StTable[tab].used = n + 1
    StTable[tab].num_entries = StTable[tab].num_entries + 1
    if (n + 1) * 2 > StTable[tab].nbins
      zr_st_index(tab, StTable[tab].nbins * 2)
    else
      zr_st_place(tab, n)
    end
  end

  # Makes the index again with `nbins` slots (a power of two), for every
  # live entry.
  #: (ptr, word) -> void
  def zr_st_index(tab, nbins)
    size = 8
    while size < nbins
      size *= 2
    end
    if StTable[tab].bins != 0
      zr_xfree(StTable[tab].bins)
    end
    StTable[tab].bins = zr_xmalloc(size * 8)
    Libc.memset(StTable[tab].bins, Machine.i32(0), size * 8)
    StTable[tab].nbins = size
    i = 0
    while i < StTable[tab].used
      if StEntry[StTable[tab].entries + (i * StEntry.size)].live != 0
        zr_st_place(tab, i)
      end
      i += 1
    end
  end

  # Puts entry `i` in the first free slot from its key's hash.
  #: (ptr, word) -> void
  def zr_st_place(tab, i)
    mask = StTable[tab].nbins - 1
    at = zr_st_key_hash(tab, StEntry[StTable[tab].entries + (i * StEntry.size)].key) & mask
    while Machine.load64(StTable[tab].bins + (at * 8), 0) != 0
      at = (at + 1) & mask
    end
    Machine.store64(StTable[tab].bins + (at * 8), 0, i + 1)
  end

  # Removes entry `e`: it stays dead in its place, and the index is made
  # again, so no probe stops at its slot.
  #: (ptr, ptr) -> void
  def zr_st_kill(tab, e)
    StEntry[e].live = 0
    StTable[tab].num_entries = StTable[tab].num_entries - 1
    zr_st_index(tab, StTable[tab].nbins)
  end

  # A word's hash for the index: its bits mixed, as a pointer's low bits
  # are often zero.
  #: (word) -> word
  def zr_st_hash(key)
    h = Machine.mul_wrap(key ^ Machine.word(Machine.ptr(key) >> 29), Machine.word(0x9E3779B97F4A7C15))
    h ^ Machine.word(Machine.ptr(h) >> 32)
  end

  # rb_st_hash: a hash of the `len` bytes at `bytes`, from the seed `h`
  # (FNV-1a).
  #: (ptr, word, word) -> word
  def rb_st_hash(bytes, len, h)
    Machine.gates_enter
    zr_c_entered()
    hash = h ^ Machine.word(0xcbf29ce484222325)
    i = 0
    while i < len
      hash = Machine.mul_wrap(hash ^ Machine.u8(Machine.load8(bytes + i, 0)), 0x100000001b3)
      i += 1
    end
    hash
  end

  # rb_st_hash_start, rb_st_hash_uint, rb_st_hash_uint32 and
  # rb_st_hash_end: a hash built a word at a time, as C's `hash` method
  # of a struct builds one. Each step mixes the word in; the end spreads
  # the bits.
  #: (word) -> word
  def rb_st_hash_start(h)
    Machine.gates_enter
    zr_c_entered()
    h ^ Machine.word(0x9e3779b97f4a7c15)
  end

  #: (word, word) -> word
  def rb_st_hash_uint(h, i)
    Machine.gates_enter
    zr_c_entered()
    zr_st_hash_step(h, i)
  end

  #: (word, i32) -> word
  def rb_st_hash_uint32(h, i)
    Machine.gates_enter
    zr_c_entered()
    zr_st_hash_step(h, Machine.u32(i))
  end

  #: (word) -> word
  def rb_st_hash_end(h)
    Machine.gates_enter
    zr_c_entered()
    zr_st_hash(h)
  end

  #: (word, word) -> word
  def zr_st_hash_step(h, i)
    Machine.mul_wrap(h ^ zr_st_hash(i), 0x100000001b3)
  end
end
