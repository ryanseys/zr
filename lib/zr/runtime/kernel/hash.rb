module Zr::Kern
  # Hashes. The entries are in insertion order, outside the arena. Each
  # entry has a key, a value, its hash code, and a live flag (a deleted
  # entry stays until the table grows). An open-addressing index of bins
  # maps a hash code to an entry. A String key is kept as a frozen copy, as
  # in CRuby. `gen` counts the rebuilds of the entries or the bins. Thus a
  # probe that ran a key's own `eql?` can see that the table changed
  # (CRuby's st "rebuilt" check).
  class RHash < Layout
    attr_reader :basic #: RBasic
    attr_accessor :entries #: ptr
    attr_accessor :len #: word
    attr_accessor :live #: word
    attr_accessor :cap #: word
    attr_accessor :default #: value
    attr_accessor :default_proc #: value
    attr_accessor :bins #: ptr
    attr_accessor :nbins #: word
    attr_accessor :iter #: word
    attr_accessor :gen #: word
  end

  class HEntry < Layout
    attr_accessor :key #: value
    attr_accessor :value #: value
    attr_accessor :live #: word
    attr_accessor :hash #: word
  end

  T_HASH = 8
  G_HASH = 30
  G_KEY_ERROR = 31

  # The result of a probe when a key's own `hash` or `eql?` raised. The
  # exception is pending in the task, and the probe returns this in place
  # of an entry.
  HASH_RAISED = 1

  # The return values of zr_key_eql.
  KEY_DIFFERENT = 0
  KEY_SAME = 1
  KEY_RAISED = 2

  #: () -> value
  def zr_hash_new
    h = zr_alloc(T_HASH, zr_global(G_HASH), RHash.size)
    RHash[h].entries = 0
    RHash[h].len = 0
    RHash[h].live = 0
    RHash[h].cap = 0
    RHash[h].default = Machine.value(QNIL)
    RHash[h].default_proc = Machine.value(QNIL)
    RHash[h].bins = 0
    RHash[h].nbins = 0
    RHash[h].iter = 0
    RHash[h].gen = 0
    h
  end

  #: (value) -> void
  def zr_mark_hash(h)
    zr_mark(RHash[h].default)
    zr_mark(RHash[h].default_proc)
    if (RBasic[h].flags & FL_WEAK) != 0
      return
    end
    keys = (RBasic[h].flags & FL_WEAKKEY) == 0
    n = RHash[h].len
    i = 0
    while i < n
      e = RHash[h].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        if keys
          zr_mark(HEntry[e].key)
        end
        zr_mark(HEntry[e].value)
      end
      i += 1
    end
  end

  # Whether two keys are the same key. It uses `eql?` for the builtin types
  # here, the object's own `eql?` for an object with an ivar table (Struct,
  # Data and the program's classes), and identity for all others. An
  # `eql?` that raises gives KEY_RAISED, with the exception pending.
  #: (value, value) -> word
  def zr_key_eql(a, b)
    if a == b
      return KEY_SAME
    end
    # rb_eql(a, b): the key looked up decides. A Float, an immediate, a
    # String, an Array and a Regexp answer by their builtin eql?, which
    # is false for a key of another type; any other key's own eql? runs,
    # whatever the stored key is.
    if zr_float_p(a)
      return zr_float_p(b) && zr_float_value(a) == zr_float_value(b) ? KEY_SAME : KEY_DIFFERENT
    end
    if zr_special_p(a)
      return KEY_DIFFERENT
    end
    t = zr_type(a)
    if (t == T_STRING || t == T_ARRAY || t == T_REGEXP) && (zr_special_p(b) || t != zr_type(b))
      return KEY_DIFFERENT
    end
    if t == T_STRING
      return zr_bytes_eq(RString[a].ptr, RString[a].len, RString[b].ptr, RString[b].len) && zr_str_comparable(a, b) ? KEY_SAME : KEY_DIFFERENT
    end
    if t == T_ARRAY
      if RArray[a].len != RArray[b].len
        return KEY_DIFFERENT
      end
      # The same two Arrays found again inside their own comparison is a
      # recursion, and the result is equal (rb_exec_recursive_paired).
      if zr_guard_enter_paired(a, b, Machine.id(:eql?))
        return KEY_SAME
      end
      same = zr_key_eql_elements(a, b)
      zr_guard_leave(a, Machine.id(:eql?))
      return same
    end
    if t == T_REGEXP
      return RRegexp[a].options == RRegexp[b].options ? zr_key_eql(RRegexp[a].source, RRegexp[b].source) : KEY_DIFFERENT
    end
    # Kernel#eql? is identity, which the first check already did. Any
    # other eql? belongs to the key, for all types of object.
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

  # Whether two Arrays of the same length contain the same keys, element
  # by element. Each step reads the lengths again, because an `eql?` can
  # change either Array.
  #: (value, value) -> word
  def zr_key_eql_elements(a, b)
    i = 0
    while i < RArray[a].len
      if i >= RArray[b].len
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

  # Mixes a word into a hash code.
  #: (word) -> word
  def zr_hash_mix(x)
    x = Machine.mul_wrap(x ^ (x >> 31), 7046029254386353131)
    x ^ (x >> 29)
  end

  # Writes the table's hash code of a key to `out`. The code comes from
  # the value itself for a fixnum, Symbol or special constant, the
  # double's bits for a Float (with -0.0 as 0.0), the bytes for a String,
  # the parts for a Regexp, and the object's own `hash` for all others.
  # Under compare_by_identity, each key hashes as itself. Returns false
  # when the key's own `hash` raised, with the exception pending.
  #: (value, value, ptr) -> bool
  def zr_key_hash(h, key, out)
    Machine.store64(out, 0, zr_key_code(h, key))
    if (RBasic[h].flags & FL_IDENTITY) != 0 || zr_special_p(key)
      return true
    end
    t = zr_type(key)
    if t == T_STRING || t == T_REGEXP
      return true
    end
    # Kernel#hash returns the code of the object's id, or a bignum's own
    # code. Use the same code that the method returns, mixed as the table
    # mixes codes.
    if zr_key_builtin_p(key, Machine.id(:hash), Machine.addr(:zr_obj_hash))
      code = zr_big_p(key) ? zr_fix2long(zr_big_hash(key)) : zr_obj_id_code(key) & 4611686018427387903
      Machine.store64(out, 0, zr_hash_mix(code))
      return true
    end
    r = zr_send(key, Machine.id(:hash), 0, 0)
    if r == QUNDEF
      return false
    end
    # Fold a bignum to a fixnum, as rb_any_hash does.
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

  # Whether `key`'s method `mid` is the builtin at `builtin`. The table's
  # own identity rule already gives the same result as that builtin.
  #: (value, word, ptr) -> bool
  def zr_key_builtin_p(key, mid, builtin)
    e = zr_find_method(zr_class_of(key), mid)
    e != 0 && MEntry[e].fn == builtin
  end

  # Returns the code of a key when no Ruby code must run to find it. For a
  # key whose own `hash` gives the code, it returns the identity code, and
  # zr_key_hash replaces it.
  #: (value, value) -> word
  def zr_key_code(h, key)
    if (RBasic[h].flags & FL_IDENTITY) != 0
      return zr_hash_mix(Machine.word(key))
    end
    zr_value_code(key)
  end

  # The code of a value that needs no Ruby code, as zr_key_code gives it
  # to a table that compares by value.
  # It is the mix of the value's `hash`, as the table mixes the `hash` of
  # any other key, so an object whose `hash` returns a key's hash (and
  # whose eql? agrees) finds that key, as in CRuby.
  #: (value) -> word
  def zr_value_code(key)
    zr_hash_mix(zr_value_hash(key))
  end

  # What `hash` returns for a value that needs no Ruby code: a fixnum,
  # Symbol or special constant and a Float (with -0.0 as 0.0) with the
  # run's seed, a String by its bytes, and a Regexp by its parts. The
  # result is in the fixnum range.
  #: (value) -> word
  def zr_value_hash(key)
    mask = 4611686018427387903
    if zr_float_p(key)
      d = zr_float_value(key)
      if d == Machine.f64(0)
        d = Machine.f64(0)
      end
      return zr_hash_mix(Machine.word(Machine.ptr(Machine.bits(d))) ^ zr_hash_seed_word()) & mask
    end
    if zr_special_p(key)
      return zr_hash_mix(Machine.word(key) ^ zr_hash_seed_word()) & mask
    end
    t = zr_type(key)
    if t == T_STRING
      # rb_str_hash: an ASCII-only or empty text hashes with no encoding.
      return zr_hash_mix(zr_str_bytes_hash(key) ^ (RString[key].len == 0 || zr_str_ascii_only(key) ? 0 : zr_str_encoding_index(key) + 1)) & mask
    end
    if t == T_REGEXP
      return zr_hash_mix(zr_value_code(RRegexp[key].source) + RRegexp[key].options) & mask
    end
    zr_hash_mix(Machine.word(key)) & mask
  end

  # CRuby's rb_hash: a Symbol, a fixnum, true, false, nil, a String, a
  # Bignum or a Float hashes without a send, even when its class redefines
  # `hash`. Anything else answers its own `hash`, folded to a fixnum.
  # The hash of the elements of the Array `a` from the fixnum `seed`, as
  # Array#hash joins them (lib/zr/runtime/core/array.rb), when each one
  # hashes with no call: an immediate, a Float or a String. Such an Array
  # cannot reach itself, so it needs no recursion guard. Returns nil when
  # an element needs its own `hash`.
  #: (value, value) -> value
  def zr_ary_leaf_hash(a, seed)
    mask = 72057594037927935
    h = zr_fix2long(seed) & mask
    i = 0
    while i < RArray[a].len
      v = zr_ary_at(a, i)
      if !zr_special_p(v) && !zr_float_p(v) && zr_type(v) != T_STRING
        return Machine.value(QNIL)
      end
      h = ((h * 31) + (zr_value_hash(v) & mask)) & mask
      i += 1
    end
    zr_fix(h)
  end

  #: (value) -> value
  def zr_rb_hash(v)
    if zr_big_p(v)
      return zr_big_hash(v)
    end
    if zr_special_p(v) || zr_float_p(v) || zr_type(v) == T_STRING
      return zr_fix(zr_value_hash(v))
    end
    r = zr_send(v, Machine.id(:hash), 0, 0)
    # rb_hash: a hash that is not a Fixnum is reduced: a bignum by its own
    # hash, anything else by to_int.
    while r != QUNDEF && !zr_fixnum_p(r)
      if zr_big_p(r)
        r = zr_send(r, Machine.id(:hash), 0, 0)
      elsif zr_float_p(r)
        r = zr_send(r, Machine.id(:to_int), 0, 0)
      else
        r = zr_to_int(r)
      end
    end
    r
  end

  # Hashes a String's bytes with the process's seed. Thus a String's hash
  # is different in each run, as in ruby, and a program cannot depend on
  # a particular hash value.
  #: (value) -> word
  def zr_str_bytes_hash(s)
    zr_bytes_hash(RString[s].ptr, RString[s].len) ^ Machine.load64(zr_hash_seed(), 0)
  end

  # The seed, set one time at boot.
  #: () -> ptr
  def zr_hash_seed
    Machine.static(:hash_seed, 8)
  end

  # The seed as a word. A fixnum, Symbol, special constant or Float
  # hashes with it, as rb_hash_start mixes CRuby's seed in, so these
  # hashes too are different in each run.
  #: () -> word
  def zr_hash_seed_word
    Machine.load64(zr_hash_seed(), 0)
  end

  #: () -> void
  def zr_hash_seed_init
    Machine.store64(zr_hash_seed(), 0, Machine.shl_wrap(zr_os_random(), 32) | zr_os_random())
  end

  # Hashes the bytes, one word at a time. Each word is folded into the
  # state and mixed. The last one to seven bytes are one word. The length
  # goes in first, so a string and the same string plus zero bytes are
  # different. No spec can check a particular value, because the seed is
  # different in each process.
  #: (ptr, word) -> word
  def zr_bytes_hash(p, n)
    x = 1469598103934665603 ^ n
    i = 0
    while i + 8 <= n
      x = zr_hash_mix(x ^ Machine.load64(p + i, 0))
      i += 8
    end
    if i < n
      w = 0
      shift = 0
      while i < n
        w = w | Machine.shl_wrap(Machine.u8(Machine.load8(p + i, 0)), shift)
        shift += 8
        i += 1
      end
      x = zr_hash_mix(x ^ w)
    end
    x
  end

  # Returns the live entry for `key`, 0 when there is none, or
  # HASH_RAISED. The probe starts at the code's bin and stops at an empty
  # bin. It skips dead entries.
  #: (value, value) -> ptr
  def zr_hash_entry(h, key)
    if RHash[h].live == 0
      return 0
    end
    code = Machine.slot(8)
    unless zr_key_hash(h, key, code)
      return Machine.ptr(HASH_RAISED)
    end
    zr_hash_find(h, key, Machine.load64(code, 0))
  end

  # A key's own `eql?` can add to the table, which rebuilds its entries
  # and bins. The probe then starts again on the new table, as CRuby's st
  # does when it finds that the table was rebuilt.
  #: (value, value, word) -> ptr
  def zr_hash_find(h, key, code)
    identity = (RBasic[h].flags & FL_IDENTITY) != 0
    gen = RHash[h].gen
    if RHash[h].nbins == 0
      return zr_hash_scan(h, key, code, identity, gen)
    end
    i = code
    while RHash[h].nbins != 0
      i = i & (RHash[h].nbins - 1)
      slot = Machine.load64(RHash[h].bins + (i * 8), 0)
      if slot == 0
        return 0
      end
      e = RHash[h].entries + ((slot - 1) * HEntry.size)
      i += 1 # rubocop:disable Lint/UselessAssignment -- the next probe reads it
      if HEntry[e].live != 0 && HEntry[e].hash == code
        if identity
          if HEntry[e].key == key
            return e
          end
        else
          # st EQUAL(key, stored): the key looked up answers eql?.
          same = zr_key_eql(key, HEntry[e].key)
          if same == KEY_RAISED
            return Machine.ptr(HASH_RAISED)
          end
          if RHash[h].gen != gen
            gen = RHash[h].gen
            i = code
          elsif same == KEY_SAME
            return e
          end
        end
      end
    end
    0
  end

  # A small table has no bins. The scan reads its entries in order and
  # checks the code first, as the probe does for a bin. If a key's `eql?`
  # changes the table, the lookup starts again, with or without bins.
  #: (value, value, word, bool, word) -> ptr
  def zr_hash_scan(h, key, code, identity, gen)
    i = 0
    while i < RHash[h].len
      e = RHash[h].entries + (i * HEntry.size)
      i += 1
      if HEntry[e].live != 0 && HEntry[e].hash == code
        if identity
          if HEntry[e].key == key
            return e
          end
        else
          # st EQUAL(key, stored): the key looked up answers eql?.
          same = zr_key_eql(key, HEntry[e].key)
          if same == KEY_RAISED
            return Machine.ptr(HASH_RAISED)
          end
          if RHash[h].gen != gen
            return zr_hash_find(h, key, code)
          end
          if same == KEY_SAME
            return e
          end
        end
      end
    end
    0
  end

  # Returns the value for `key` in an internal table of the runtime, or
  # undef when there is none. The key must be a Symbol, a fixnum or a
  # String, so the lookup runs no Ruby code and cannot raise.
  #: (value, value) -> value
  def zr_hash_lookup(h, key)
    e = zr_hash_entry(h, key)
    if e == HASH_RAISED
      zr_bug(Machine.bytes("zr_hash_lookup: a key that runs Ruby code\n"), 42)
    end
    if e == 0
      return Machine.value(QUNDEF)
    end
    HEntry[e].value
  end

  # Puts entry `n` (its index in the entries) into the bins.
  #: (value, word) -> void
  def zr_hash_bin(h, n)
    if RHash[h].nbins == 0
      return
    end
    e = RHash[h].entries + (n * HEntry.size)
    mask = RHash[h].nbins - 1
    i = HEntry[e].hash & mask
    while Machine.load64(RHash[h].bins + (i * 8), 0) != 0
      i = (i + 1) & mask
    end
    Machine.store64(RHash[h].bins + (i * 8), 0, n + 1)
  end

  # Rebuilds the bins from the live entries, with two times the entry
  # capacity, so the probes stay short. A table of HASH_SMALL entries or
  # fewer has no bins, because a scan of that many codes costs less than
  # the bins.
  HASH_SMALL = 8

  #: (value) -> void
  def zr_hash_rebins(h)
    zr_sized_xfree(RHash[h].bins, RHash[h].nbins * 8)
    if RHash[h].cap <= HASH_SMALL
      RHash[h].bins = 0
      RHash[h].nbins = 0
      RHash[h].gen = RHash[h].gen + 1
      return
    end
    nbins = 16
    while nbins < RHash[h].cap * 2
      nbins = nbins * 2
    end
    bins = zr_xmalloc(nbins * 8)
    i = 0
    while i < nbins
      Machine.store64(bins + (i * 8), 0, 0)
      i += 1
    end
    RHash[h].bins = bins
    RHash[h].nbins = nbins
    RHash[h].gen = RHash[h].gen + 1
    i = 0
    while i < RHash[h].len
      if HEntry[RHash[h].entries + (i * HEntry.size)].live != 0
        zr_hash_bin(h, i)
      end
      i += 1
    end
  end

  # Makes room for one more entry. The table doubles, deleted entries are
  # removed, and the bins are rebuilt.
  #: (value) -> void
  def zr_hash_reserve(h)
    n = RHash[h].len
    if n < RHash[h].cap
      return
    end
    cap = RHash[h].live * 2
    if cap < 8
      cap = 8
    end
    entries = zr_xmalloc(cap * HEntry.size)
    j = 0
    i = 0
    while i < n
      e = RHash[h].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        zr_memcpy(entries + (j * HEntry.size), e, HEntry.size)
        j += 1
      end
      i += 1
    end
    zr_sized_xfree(RHash[h].entries, RHash[h].cap * HEntry.size)
    RHash[h].entries = entries
    RHash[h].len = j
    RHash[h].cap = cap
    zr_hash_rebins(h)
  end

  # Computes the code of each key again and rebuilds the bins, after
  # compare_by_identity or `rehash`. A key's own `hash` can change the
  # table, and then the loop starts again. Returns false when a `hash`
  # raised.
  #: (value) -> bool
  def zr_hash_recode(h)
    code = Machine.slot(8)
    gen = RHash[h].gen
    i = 0
    while i < RHash[h].len
      if HEntry[RHash[h].entries + (i * HEntry.size)].live != 0
        unless zr_key_hash(h, HEntry[RHash[h].entries + (i * HEntry.size)].key, code)
          return false
        end
        if RHash[h].gen != gen
          gen = RHash[h].gen
          i = 0
        else
          HEntry[RHash[h].entries + (i * HEntry.size)].hash = Machine.load64(code, 0)
          i += 1
        end
      else
        i += 1
      end
    end
    if RHash[h].cap > 0
      zr_hash_rebins(h)
    end
    true
  end

  # `h[key] = value` for the runtime. Returns the value, or undef when the
  # key's own `hash` or `eql?` raised.
  #: (value, value, value) -> value
  def zr_hash_store(h, key, value)
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
      HEntry[e].value = value
      zr_write_barrier(h, value)
      return value
    end
    # RHASH_STRING_KEY_P and rb_hash_key_str: an unfrozen key of class
    # String (a singleton class too) is stored as a frozen copy -- the
    # fstring of its bytes when it is bare (no singleton class, no
    # ivars). A key of a subclass is stored as it is.
    if !zr_special_p(key) && zr_type(key) == T_STRING && !zr_frozen_p(key) && zr_real_class(key) == zr_global(G_STRING) && (RBasic[h].flags & (FL_IDENTITY | FL_WEAKKEY)) == 0
      copy = zr_str_copy_encoding(zr_str_new(RString[key].ptr, RString[key].len), key)
      if RBasic[key].klass == zr_global(G_STRING) && (RBasic[key].flags & FL_EXIVAR) == 0
        key = zr_str_intern(copy)
      else
        key = copy
        RBasic[key].flags = RBasic[key].flags | FL_FREEZE
      end
    end
    zr_hash_append(h, key, code, value)
  end

  # Adds a new entry for `key`, with the code `code`, after the last
  # entry. The caller knows that the key is not in `h`, so no method of
  # the key runs.
  #: (value, value, word, value) -> value
  def zr_hash_append(h, key, code, value)
    zr_hash_reserve(h)
    n = RHash[h].len
    e = RHash[h].entries + (n * HEntry.size)
    HEntry[e].key = key
    HEntry[e].value = value
    zr_write_barrier(h, key)
    zr_write_barrier(h, value)
    HEntry[e].live = 1
    HEntry[e].hash = code
    RHash[h].len = n + 1
    RHash[h].live = RHash[h].live + 1
    zr_hash_bin(h, n)
    value
  end

  # Returns the value for a missing key: the default proc's result, or the
  # default.
  #: (value, value) -> value
  def zr_hash_default(h, key)
    if RHash[h].default_proc != QNIL
      return zr_yield2(RHash[h].default_proc, h, key)
    end
    RHash[h].default
  end

  #: (value, word, ptr, value, value) -> value
  def zr_hash_aref(recv, argc, argv, cref, blk)
    key = Machine.value(Machine.load64(argv, 0))
    e = zr_hash_entry(recv, key)
    if e == HASH_RAISED
      return Machine.value(QUNDEF)
    end
    if e == 0
      return zr_hash_missing(recv, key)
    end
    HEntry[e].value
  end

  # Returns the value for a missing `key`, as rb_hash_default_value does.
  # If the receiver has its own `default`, it calls it. Otherwise it
  # returns the default proc's result or the default.
  #: (value, value) -> value
  def zr_hash_missing(h, key)
    if zr_basic_method_p(h, Machine.id(:default))
      return zr_hash_default(h, key)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(key))
    zr_send(h, Machine.id(:default), 1, slot)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_hash_aset(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    value = Machine.value(Machine.load64(argv, 8))
    key = Machine.value(Machine.load64(argv, 0))
    if RHash[recv].iter != 0
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
  #: (value, word, ptr, value, value) -> value
  def zr_hash_fetch(recv, argc, argv, cref, blk)
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
      return HEntry[found].value
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
    # rb_str_ellipsize(desc, 65): a long key shows its first 62
    # characters and "...".
    if zr_str_char_count(s) > 65
      zr_buf_push(b, RString[s].ptr, zr_str_char_offset(s, 62))
      zr_buf_push(b, Machine.bytes("..."), 3)
    else
      zr_buf_str(b, s)
    end
    e = zr_exc_new(zr_global(G_KEY_ERROR), zr_buf_take(b))
    zr_exc_detail(e, Machine.id(:key), key)
    zr_exc_detail(e, Machine.id(:receiver), recv)
    zr_raise(e)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_hash_key_p(recv, argc, argv, cref, blk)
    e = zr_hash_entry(recv, Machine.value(Machine.load64(argv, 0)))
    if e == HASH_RAISED
      return Machine.value(QUNDEF)
    end
    zr_bool(e != 0)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_hash_delete(recv, argc, argv, cref, blk)
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
    v = HEntry[e].value
    HEntry[e].live = 0
    HEntry[e].key = Machine.value(QNIL)
    HEntry[e].value = Machine.value(QNIL)
    RHash[recv].live = RHash[recv].live - 1
    v
  end

  #: (value, word, ptr, value, value) -> value
  def zr_hash_size(recv, argc, argv, cref, blk)
    zr_fix(RHash[recv].live)
  end

  # Returns the live count as a fixnum, for core code that must not
  # dispatch.
  #: (value) -> value
  def zr_hash_len_m(h)
    zr_fix(RHash[h].live)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_hash_empty_p(recv, argc, argv, cref, blk)
    zr_bool(RHash[recv].live == 0)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_hash_keys(recv, argc, argv, cref, blk)
    out = zr_ary_new(RHash[recv].live)
    i = 0
    while i < RHash[recv].len
      e = RHash[recv].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        zr_ary_push(out, HEntry[e].key)
      end
      i += 1
    end
    out
  end

  #: (value, word, ptr, value, value) -> value
  def zr_hash_values(recv, argc, argv, cref, blk)
    out = zr_ary_new(RHash[recv].live)
    i = 0
    while i < RHash[recv].len
      e = RHash[recv].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        zr_ary_push(out, HEntry[e].value)
      end
      i += 1
    end
    out
  end

  # `[key, value]`.
  #: (ptr) -> value
  def zr_hash_assoc(e)
    pair = zr_ary_new(2)
    zr_ary_push(pair, HEntry[e].key)
    zr_ary_push(pair, HEntry[e].value)
    pair
  end

  # Whether `each` can give a block the key and the value as two
  # arguments, in place of the `[key, value]` Array that ruby yields.
  #
  # This is possible when the block splits that Array again. A `spread`
  # block binds a single Array over its parameters, so two arguments go to
  # the same names. A lambda is different: it binds strictly, and
  # `h.each(&->(k, v) { })` is an ArgumentError in ruby, which occurs only
  # with one argument. `{ |pair| }` and `{ |*x| }` are also different, and
  # `spread` is already false for them.
  #
  # The Array is the main cost of `each`: a cell and a malloc for each
  # entry of each iteration, discarded at the end of the block.
  #: (value) -> bool
  def zr_block_takes_pair(blk)
    RProc[blk].spread != 0 && RProc[blk].lambda == 0
  end

  # `each`: yields one `[key, value]` for each entry. It reads the table
  # again after each yield, because the block can change it.
  #: (value, word, ptr, value, value) -> value
  def zr_hash_each(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_enum_for(recv, Machine.id(:each), argc, argv, zr_fix(RHash[recv].live))
    end
    pairless = zr_block_takes_pair(blk)
    RHash[recv].iter = RHash[recv].iter + 1
    i = 0
    while i < RHash[recv].len
      e = RHash[recv].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        r = pairless ? zr_yield2(blk, HEntry[e].key, HEntry[e].value) : zr_yield1(blk, zr_hash_assoc(e))
        if r == QUNDEF
          RHash[recv].iter = RHash[recv].iter - 1
          return r
        end
      end
      i += 1
    end
    RHash[recv].iter = RHash[recv].iter - 1
    recv
  end

  # rb_hash_foreach: yields each pair of `h`'s own table to `blk`, as
  # `each` does, also when a subclass redefines `each`.
  #: (value, value) -> value
  def zr_hash_foreach(h, blk)
    zr_hash_each(h, 0, 0, Machine.value(QNIL), blk)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_hash_to_a(recv, argc, argv, cref, blk)
    out = zr_ary_new(RHash[recv].live)
    i = 0
    while i < RHash[recv].len
      e = RHash[recv].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        zr_ary_push(out, zr_hash_assoc(e))
      end
      i += 1
    end
    out
  end

  # A Symbol key prints as `key: value`, with quotes when its name is not
  # a plain identifier. Any other key prints as `key => value`.
  #: (value) -> bool
  def zr_symbol_key_simple_p(key)
    if !zr_symbol_p(key)
      return false
    end
    id = zr_sym2id(key)
    p = zr_symbol_name_ptr(id)
    n = zr_symbol_name_len(id)
    if n == 0 || zr_symbol_tag(id) != 0
      return false
    end
    c = Machine.u8(Machine.load8(p, 0))
    unless (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 128
      return false
    end
    i = 1
    while i < n
      c = Machine.u8(Machine.load8(p + i, 0))
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

  #: (value, word, ptr, value, value) -> value
  def zr_hash_inspect(recv, argc, argv, cref, blk)
    if RHash[recv].live == 0
      return zr_usascii_str_new(Machine.bytes("{}"), 2)
    end
    if zr_guard_enter(recv, Machine.id(:inspect))
      return zr_usascii_str_new(Machine.bytes("{...}"), 5)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_byte(b, 123)
    # The text gets the first key's encoding, and each next piece is
    # appended to it, as inspect_i does.
    index = ENC_USASCII
    ascii = true
    first = true
    i = 0
    while i < RHash[recv].len
      e = RHash[recv].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        unless first
          zr_buf_push(b, Machine.bytes(", "), 2)
        end
        key = HEntry[e].key
        if zr_symbol_p(key)
          id = zr_sym2id(key)
          name_ascii = zr_bytes_ascii_only_p(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
          name_index = name_ascii ? ENC_USASCII : zr_symbol_encoding_index(id)
          if first
            index = name_index
          elsif zr_symbol_name_len(id) > 0
            index = zr_enc_append(index, ascii, Buf[b].len, name_index, name_ascii)
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
            zr_buf_free(b)
            zr_guard_leave(recv, Machine.id(:inspect))
            return s
          end
          index = first ? zr_str_encoding_index(s) : zr_enc_append_str(index, ascii, Buf[b].len, s)
          ascii = ascii && zr_str_ascii_bytes_p(s)
          zr_buf_str(b, s)
          zr_buf_push(b, Machine.bytes(" => "), 4)
        end
        e = RHash[recv].entries + (i * HEntry.size)
        s = zr_inspect(HEntry[e].value)
        if s == QUNDEF
          zr_buf_free(b)
          zr_guard_leave(recv, Machine.id(:inspect))
          return s
        end
        index = zr_enc_append_str(index, ascii, Buf[b].len, s)
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

  # `==`: the same keys, and each value is `==` to the other.
  #: (value, word, ptr, value, value) -> value
  def zr_hash_eq(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(other)
      return Machine.value(QFALSE)
    end
    if zr_type(other) != T_HASH
      return zr_eq_by_conversion(recv, other, Machine.id(:to_hash))
    end
    if RHash[recv].live != RHash[other].live
      return Machine.value(QFALSE)
    end
    # The same two Hashes compared again inside their own comparison is a
    # recursion, and the result is equal (rb_exec_recursive_paired).
    if recv == other || zr_guard_enter_paired(recv, other, Machine.id(:==))
      return Machine.value(QTRUE)
    end
    r = zr_hash_eq_entries(recv, other)
    zr_guard_leave(recv, Machine.id(:==))
    r
  end

  #: (value, value) -> value
  def zr_hash_eq_entries(recv, other)
    i = 0
    while i < RHash[recv].len
      e = RHash[recv].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        found = zr_hash_entry(other, HEntry[e].key)
        if found == HASH_RAISED
          return Machine.value(QUNDEF)
        end
        if found == 0
          return Machine.value(QFALSE)
        end
        r = zr_rb_equal(HEntry[RHash[recv].entries + (i * HEntry.size)].value, HEntry[found].value)
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
  # rb_hash_init: sets a default proc from the block, or the default value
  # `ifnone`. A block and `ifnone` cannot both be given. `unset` is true
  # when no default value was given. The capacity only reserves space.
  #: (value, value, value, value, value) -> value
  def zr_hash_init(recv, capacity, unset, ifnone, blk)
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
      RHash[recv].default = Machine.value(QNIL)
      RHash[recv].default_proc = zr_block_proc(blk)
      return recv
    end
    RHash[recv].default = unset == QTRUE ? Machine.value(QNIL) : ifnone
    RHash[recv].default_proc = Machine.value(QNIL)
    recv
  end

  #: (value, word, ptr, value, value) -> value
  def zr_hash_default_m(recv, argc, argv, cref, blk)
    RHash[recv].default
  end

  # Makes `{k => v, ...}` from `n` pairs in `argv`.
  #: (word, ptr) -> value
  def zr_hash_of(n, argv)
    h = zr_hash_new()
    i = 0
    while i < n
      r = zr_hash_store(h, Machine.value(Machine.load64(argv + (i * 16), 0)), Machine.value(Machine.load64(argv + (i * 16), 8)))
      return r if r == QUNDEF
      i += 1
    end
    h
  end

  # The keywords that a method declares are `n` symbol ids at `ids`. The
  # call's keywords are `hash`, or nil when the call passed none.
  #: (value, word) -> value
  def zr_kw_get(hash, id)
    if hash == QNIL
      return Machine.value(QUNDEF)
    end
    zr_hash_lookup(hash, zr_sym(id))
  end

  #: (ptr, word, word) -> bool
  def zr_kw_declared(ids, n, id)
    i = 0
    while i < n
      if Machine.load64(ids + (i * 8), 0) == id
        return true
      end
      i += 1
    end
    false
  end

  # Raises `missing keyword: :a` or `missing keywords: :a, :b` for the
  # required keywords that are not in `hash`. Returns nil when all are
  # there.
  #: (value, ptr, word) -> value
  def zr_kw_missing(hash, ids, n)
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

  # `**nil`: raises for any keyword.
  #: (value) -> value
  def zr_kw_none(hash)
    if hash == QNIL || RHash[hash].live == 0
      return Machine.value(QNIL)
    end
    zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no keywords accepted"), 20)
  end

  # Raises `unknown keyword: :x` or `unknown keywords: :x, :y` for the
  # keys of `hash` that the method does not declare. Returns nil when
  # there are none.
  #: (value, ptr, word) -> value
  def zr_kw_unknown(hash, ids, n)
    # @type var e: ptr
    if hash == QNIL
      return Machine.value(QNIL)
    end
    count = 0
    i = 0
    while i < RHash[hash].len
      e = RHash[hash].entries + (i * HEntry.size)
      if HEntry[e].live != 0 && !(zr_symbol_p(HEntry[e].key) && zr_kw_declared(ids, n, zr_sym2id(HEntry[e].key)))
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
    while i < RHash[hash].len
      e = RHash[hash].entries + (i * HEntry.size)
      if HEntry[e].live != 0 && !(zr_symbol_p(HEntry[e].key) && zr_kw_declared(ids, n, zr_sym2id(HEntry[e].key)))
        if seen > 0
          zr_buf_push(b, Machine.bytes(", "), 2)
        end
        s = zr_inspect(HEntry[RHash[hash].entries + (i * HEntry.size)].key)
        if s == QUNDEF
          zr_buf_free(b)
          return s
        end
        zr_buf_str(b, s)
        seen += 1
      end
      i += 1
    end
    zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
  end

  # A call's keyword table (`zr_kw_pass`) has the count, then the ids.
  # Returns the position of `id` in it, or -1.
  #: (ptr, word) -> word
  def zr_kw_tab_index(tab, id)
    n = Machine.load64(tab, 0)
    i = 0
    while i < n
      if Machine.load64(tab + 8 + (i * 8), 0) == id
        return i
      end
      i += 1
    end
    0 - 1
  end

  # Fills a def's keyword shape cache for the call's table: the position
  # of each of the `m` keywords that the def declares (`ids`), or -1. It
  # fills it one time for each table, after the same checks as for a Hash.
  # `mode` 0 raises for an undeclared keyword, 1 gives it to a `**rest`,
  # and 2 (`**nil`) raises for any keyword. Returns nil, or undef with the
  # error pending and the shape cache unchanged.
  #: (ptr, ptr, ptr, word, ptr, word, word) -> value
  def zr_kw_shape(shape, tab, ids, m, required, nreq, mode)
    if Machine.load64(shape, 0) == Machine.word(tab)
      return Machine.value(QNIL)
    end
    r = zr_kw_missing_tab(tab, required, nreq)
    return r if r == QUNDEF
    if mode == 2 && Machine.load64(tab, 0) > 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no keywords accepted"), 20)
    end
    if mode == 0
      r = zr_kw_unknown_tab(tab, ids, m)
      return r if r == QUNDEF
    end
    k = 0
    while k < m
      Machine.store64(shape + 8 + (k * 8), 0, zr_kw_tab_index(tab, Machine.load64(ids + (k * 8), 0)))
      k += 1
    end
    Machine.store64(shape, 0, Machine.word(tab))
    Machine.value(QNIL)
  end

  # `zr_kw_missing` for a table.
  #: (ptr, ptr, word) -> value
  def zr_kw_missing_tab(tab, ids, n)
    count = 0
    i = 0
    while i < n
      if zr_kw_tab_index(tab, Machine.load64(ids + (i * 8), 0)) < 0
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
      if zr_kw_tab_index(tab, id) < 0
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

  # `zr_kw_unknown` for a table.
  #: (ptr, ptr, word) -> value
  def zr_kw_unknown_tab(tab, ids, m)
    n = Machine.load64(tab, 0)
    count = 0
    i = 0
    while i < n
      if !zr_kw_declared(ids, m, Machine.load64(tab + 8 + (i * 8), 0))
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
    while i < n
      id = Machine.load64(tab + 8 + (i * 8), 0)
      if !zr_kw_declared(ids, m, id)
        if seen > 0
          zr_buf_push(b, Machine.bytes(", "), 2)
        end
        s = zr_inspect(zr_sym(id))
        if s == QUNDEF
          zr_buf_free(b)
          return s
        end
        zr_buf_str(b, s)
        seen += 1
      end
      i += 1
    end
    zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
  end

  # `**rest` from a table: a Hash of the values in `vals` whose keywords
  # the method does not declare.
  #: (ptr, ptr, ptr, word) -> value
  def zr_kw_rest_tab(tab, vals, ids, m)
    out = zr_hash_new()
    n = Machine.load64(tab, 0)
    i = 0
    while i < n
      id = Machine.load64(tab + 8 + (i * 8), 0)
      if !zr_kw_declared(ids, m, id)
        zr_hash_store(out, zr_sym(id), Machine.value(Machine.load64(vals + (i * 8), 0)))
      end
      i += 1
    end
    out
  end

  # `**rest`: the keywords of `hash` that the method does not declare. The
  # entries are copied with their codes, as rb_hash_dup does. A key's own
  # `hash` ran at the call and does not run again here.
  #: (value, ptr, word) -> value
  def zr_kw_rest(hash, ids, n)
    out = zr_hash_new()
    if hash == QNIL
      return out
    end
    i = 0
    while i < RHash[hash].len
      e = RHash[hash].entries + (i * HEntry.size)
      if HEntry[e].live != 0 && !(zr_symbol_p(HEntry[e].key) && zr_kw_declared(ids, n, zr_sym2id(HEntry[e].key)))
        zr_hash_append(out, HEntry[e].key, HEntry[e].hash, HEntry[e].value)
      end
      i += 1
    end
    out
  end

  # `**value` in a hash literal or a call: adds the value's pairs. The
  # value must be a Hash (nil adds nothing).
  #: (value, value) -> value
  def zr_hash_update(h, other)
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
      # rb_convert_type names true and false as themselves.
      if other == QTRUE || other == QFALSE
        s = zr_inspect(other)
        return s if s == QUNDEF
        zr_buf_str(b, s)
      else
        zr_buf_class_of(b, other)
      end
      zr_buf_push(b, Machine.bytes(" into Hash"), 10)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    i = 0
    while i < RHash[other].len
      e = RHash[other].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        r = zr_hash_store(h, HEntry[e].key, HEntry[e].value)
        return r if r == QUNDEF
      end
      i += 1
    end
    h
  end

  # The keywords of an array literal made only of `**` splats. Returns
  # `[h]` to splat into the literal, or `[]` when `h` is empty, because
  # CRuby's pushtoarraykwsplat adds no element for an empty Hash.
  #: (value) -> value
  def zr_ary_kw_element(h)
    if RHash[h].live == 0
      return zr_ary_new(0)
    end
    a = zr_ary_new(1)
    zr_ary_push(a, h)
    a
  end

  # The primitives that lib/zr/runtime/core/hash.rb uses.
  #: (value) -> value
  def zr_hash_default_proc(h)
    RHash[h].default_proc
  end

  #: (value, value) -> value
  def zr_hash_set_default(h, v)
    if zr_modify_frozen_p(h)
      return zr_frozen_error(h)
    end
    RHash[h].default = v
    RHash[h].default_proc = Machine.value(QNIL)
    v
  end

  #: (value, value) -> value
  def zr_hash_set_default_proc(h, p)
    if zr_modify_frozen_p(h)
      return zr_frozen_error(h)
    end
    RHash[h].default_proc = p
    RHash[h].default = Machine.value(QNIL)
    p
  end

  # Removes all entries. The defaults stay.
  #: (value) -> value
  def zr_hash_clear(h)
    if zr_modify_frozen_p(h)
      return zr_frozen_error(h)
    end
    i = 0
    while i < RHash[h].len
      HEntry[RHash[h].entries + (i * HEntry.size)].live = 0
      i += 1
    end
    RHash[h].len = 0
    RHash[h].live = 0
    RHash[h].gen = RHash[h].gen + 1
    i = 0
    while i < RHash[h].nbins
      Machine.store64(RHash[h].bins + (i * 8), 0, 0)
      i += 1
    end
    h
  end

  # `compare_by_identity`: after this, a key matches only itself.
  #: (value) -> value
  def zr_hash_compare_by_identity(h)
    if (RBasic[h].flags & FL_IDENTITY) != 0
      return h
    end
    if zr_modify_frozen_p(h)
      return zr_frozen_error(h)
    end
    if RHash[h].iter != 0
      return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("compare_by_identity during iteration"), 36)
    end
    RBasic[h].flags = RBasic[h].flags | FL_IDENTITY
    zr_hash_recode(h)
    h
  end

  # An iteration of `h` that is not a walk of its table: the block of
  # `update`, which runs inside the update of the receiver.
  #: (value) -> value
  def zr_hash_iter_enter(h)
    RHash[h].iter = RHash[h].iter + 1
    h
  end

  #: (value) -> value
  def zr_hash_iter_leave(h)
    RHash[h].iter = RHash[h].iter - 1
    h
  end

  #: (value) -> value
  def zr_hash_iterating_p(h)
    zr_bool(RHash[h].iter != 0)
  end

  # `rehash`: computes the codes again after keys changed in the table.
  #: (value) -> value
  def zr_hash_rehash(h)
    if zr_modify_frozen_p(h)
      return zr_frozen_error(h)
    end
    if RHash[h].iter != 0
      return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("rehash during iteration"), 23)
    end
    unless zr_hash_recode(h)
      return Machine.value(QUNDEF)
    end
    # Keys that came to be eql? fold into the first one, which takes the
    # last value, as rb_hash_rehash builds the table again. The bins are in
    # entry order, so a key's probe meets its first equal entry first.
    if (RBasic[h].flags & FL_IDENTITY) != 0
      return h
    end
    i = 0
    while i < RHash[h].len
      e = RHash[h].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        found = zr_hash_find(h, HEntry[e].key, HEntry[e].hash)
        if found == HASH_RAISED
          return Machine.value(QUNDEF)
        end
        if found != 0 && found != e && found < e
          HEntry[found].value = HEntry[e].value
          HEntry[e].live = 0
          HEntry[e].key = Machine.value(QNIL)
          HEntry[e].value = Machine.value(QNIL)
          RHash[h].live = RHash[h].live - 1
        end
      end
      i += 1
    end
    h
  end

  #: (value) -> value
  def zr_hash_identity_p(h)
    zr_bool((RBasic[h].flags & FL_IDENTITY) != 0)
  end

  # Returns only the default value, for the core.
  #: (value) -> value
  def zr_hash_default_value(h)
    RHash[h].default
  end

  # `h[key]`, `h[key] = value`, `key?`, `fetch` and `replace` for the core.
  # They use the table directly, as rb_hash_aref, rb_hash_aset,
  # rb_hash_has_key, rb_hash_fetch and rb_hash_replace do, and never call a
  # method that a subclass can replace.
  #: (value, value) -> value
  def zr_hash_aref_m(h, key)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(key))
    zr_hash_aref(h, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
  end

  #: (value, value, value) -> value
  def zr_hash_aset_m(h, key, value)
    slot = Machine.slot(16)
    Machine.store64(slot, 0, Machine.word(key))
    Machine.store64(slot, 8, Machine.word(value))
    zr_hash_aset(h, 2, slot, Machine.value(QNIL), Machine.value(QNIL))
  end

  #: (value, value) -> value
  def zr_hash_key_p_m(h, key)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(key))
    zr_hash_key_p(h, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
  end

  #: (value, value, value) -> value
  def zr_hash_fetch_m(h, key, blk)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(key))
    zr_hash_fetch(h, 1, slot, Machine.value(QNIL), blk)
  end

  #: (value, value) -> value
  def zr_hash_replace_m(h, other)
    zr_hash_copy_from(h, other)
  end

  # `delete(key)` for the core. Returns the value, or nil.
  #: (value, value) -> value
  def zr_hash_delete_m(h, key)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(key))
    zr_hash_delete(h, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
  end
end
