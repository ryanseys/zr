module Zr::Kern
  # The C API's st tables, which C uses for its own maps: numtables, whose
  # keys are words compared as they are. A table has CRuby 4.0's public
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
    e = zr_st_find(tab, key)
    if e == 0
      return Machine.i32(0)
    end
    if value != 0
      Machine.store64(value, 0, StEntry[e].value)
    end
    Machine.i32(1)
  end

  # rb_st_delete: removes `*key`; its value goes to `*value`.
  #: (ptr, ptr, ptr) -> i32
  def rb_st_delete(tab, key, value)
    Machine.gates_enter
    zr_c_entered()
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

  # rb_st_clear: removes every entry.
  #: (ptr) -> void
  def rb_st_clear(tab)
    Machine.gates_enter
    zr_c_entered()
    StTable[tab].used = 0
    StTable[tab].num_entries = 0
    Libc.memset(StTable[tab].bins, Machine.i32(0), StTable[tab].nbins * 8)
  end

  # rb_st_free_table: frees the table and its entries.
  #: (ptr) -> void
  def rb_st_free_table(tab)
    Machine.gates_enter
    zr_c_entered()
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
    at = zr_st_hash(key) & mask
    while true
      slot = Machine.load64(StTable[tab].bins + (at * 8), 0)
      if slot == 0
        return Machine.ptr(0)
      end
      e = StTable[tab].entries + ((slot - 1) * StEntry.size)
      if StEntry[e].live != 0 && StEntry[e].key == key
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
    at = zr_st_hash(StEntry[StTable[tab].entries + (i * StEntry.size)].key) & mask
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
