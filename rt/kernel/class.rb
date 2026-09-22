# Classes and modules: a name, a superclass, and an extension outside
# the arena holding the method table (id, code, arity, kind, meta,
# cref rows searched in order) and the constant table (id, value rows).
# An included module sits in the superclass chain as a proxy (T_ICLASS)
# that shares the module's extension and names it as `attached`.
# Method code takes `(recv, argc, argv, cref)` and answers a Value; the
# cref is the lexical class chain the method was defined under.
# `origin` is the proxy that holds a prepended class's own methods,
# placed below the prepended modules, or nil.
Machine.struct :RClass, basic: RBasic, name: Value, superclass: Value, ext: Ptr, attached: Value, origin: Value
# `serial` counts classes in creation order, which `subclasses` reads.
# `refined` is the class a refinement holder stands over, and `active`
# the one-item activation list that holder alone makes; both are nil on
# an ordinary class or module.
# `boxed` is the shadow class each box sees in place of this one,
# indexed by box slot, and `shadow` the shared class a shadow stands
# over; both are nil outside a box.
# `alloc` is the kind of object the class allocates (ALLOC_*), found
# from its builtin ancestor on first use; 0 until then.
# `saved` holds, `slen` rows of it, the rows of the core library a
# program wrote over or removed, which the core library's own sends
# still reach (see zr_find_core_method).
Machine.struct :ClassExt, mtab: Ptr, mlen: Word, mcap: Word, ctab: Ptr, clen: Word, ccap: Word, iv: IvTab, cv: IvTab, serial: Word, refined: Value, active: Value, boxed: Value, shadow: Value, alloc: Word, cidx: Ptr, cbins: Word,
                           saved: Ptr, slen: Word, supers: Ptr, rank: Word, midx: Ptr, mbins: Word, obj_bytes: Word
# `orig` is the name the method was first defined under, which an
# alias keeps. `from` is the chain node the entry an alias or a
# visibility change copied was found on, where `super` in the body
# continues from as CRuby's alias and zsuper entries do; nil for a
# definition. `core` is 1 for a row the core library wrote before the
# program started.
# `ivar` is the word a kind keeps beside its function: the row guess an
# accessor reads and writes through (cache.rb), or the cref a
# `define_method` body runs under, made at the first call (eval.rb,
# `zr_bmethod_cref`). An entry is 88 bytes: a Method's cell embeds one
# after three Values, and a 128-byte cell holds no more.
# `direct` is the second entry of a compiled def of required positionals
# alone (Zr::Function, `direct?`): the same body, taking its arguments
# in registers with no count to check, which a call site that hands it
# exactly that many reaches through its cell (CallCache.direct). Such a
# def's `fn` is `zr_direct_fn`, which takes the generic arguments and
# checks what the site proved.
Machine.struct :MEntry, mid: Word, fn: Ptr, arity: Word, kind: Word, meta: Ptr, cref: Value, vis: Word, orig: Word, from: Value, core: Word, ivar: IvarCache, cover: Word, direct: Ptr
Machine.struct :CEntry, id: Word, value: Value, file: Ptr, file_len: Word, line: Word, private: Word, deprecated: Word, owner: Value, concealed: Word
# A compiled method takes `(recv, argc, argv, entry, blk, found)`: its
# own entry, whose name and cref its frame records, and the chain node
# the lookup found it on. A builtin takes `(recv, argc, argv, cref, blk)`.
# A direct entry takes `(recv, entry, blk, found, ...)`: its own count
# of arguments in registers, up to four, and one signature a count.
Machine.sig :method, [Value, Word, Ptr, Ptr, Value, Value] => Value
Machine.sig :builtin, [Value, Word, Ptr, Value, Value] => Value
Machine.sig :direct0, [Value, Ptr, Value, Value] => Value
Machine.sig :direct1, [Value, Ptr, Value, Value, Value] => Value
Machine.sig :direct2, [Value, Ptr, Value, Value, Value, Value] => Value
Machine.sig :direct3, [Value, Ptr, Value, Value, Value, Value, Value] => Value
Machine.sig :direct4, [Value, Ptr, Value, Value, Value, Value, Value, Value] => Value
# Method kinds beyond a compiled def and a builtin: accessors keep the
# ivar's id in `fn`.
KIND_ATTR_READER = 3
KIND_ATTR_WRITER = 4
# A builtin that leaves no frame of its own: `Proc#call` and `send`,
# which CRuby keeps out of a backtrace.
KIND_FRAMELESS = 5
# An `undef`: the name answers nothing from here on down the chain.
KIND_UNDEF = 6
# A Method for a name `respond_to_missing?` claimed: a call goes to
# `method_missing`.
KIND_MISSING = 9

sig [Word, Value, Value] => Value
machine def zr_class_alloc(type, sup, klass)
  c = zr_alloc(type, klass, RClass.size)
  RClass.set_name(c, Machine.value(QNIL))
  RClass.set_superclass(c, sup)
  RClass.set_attached(c, Machine.value(QNIL))
  RClass.set_origin(c, Machine.value(QNIL))
  ext = zr_xmalloc(ClassExt.size)
  ClassExt.set_mtab(ext, 0)
  ClassExt.set_mlen(ext, 0)
  ClassExt.set_mcap(ext, 0)
  ClassExt.set_ctab(ext, 0)
  ClassExt.set_clen(ext, 0)
  ClassExt.set_ccap(ext, 0)
  ClassExt.set_cidx(ext, 0)
  ClassExt.set_cbins(ext, 0)
  zr_ivtab_init(ClassExt.iv(ext))
  zr_ivtab_init(ClassExt.cv(ext))
  ClassExt.set_refined(ext, Machine.value(QNIL))
  ClassExt.set_active(ext, Machine.value(QNIL))
  ClassExt.set_boxed(ext, Machine.value(QNIL))
  ClassExt.set_shadow(ext, Machine.value(QNIL))
  ClassExt.set_alloc(ext, 0)
  ClassExt.set_saved(ext, 0)
  ClassExt.set_slen(ext, 0)
  ClassExt.set_supers(ext, 0)
  ClassExt.set_rank(ext, 0)
  ClassExt.set_midx(ext, 0)
  ClassExt.set_mbins(ext, 0)
  ClassExt.set_obj_bytes(ext, RObject.size)
  counter = Machine.static(:class_serial, 8)
  Machine.store64(counter, 0, Machine.load64(counter, 0) + 1)
  ClassExt.set_serial(ext, Machine.load64(counter, 0))
  RClass.set_ext(c, ext)
  zr_methods_changed()
  c
end

# The three superclasses ruby refuses, in `rb_check_inheritable`'s
# order. Answers QUNDEF when it raised.
sig [Value] => Value
machine def zr_check_inheritable(sup)
  if zr_special_p(sup) || zr_type(sup) != T_CLASS
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("superclass must be an instance of Class (given an instance of "), 62)
    zr_buf_class_of(b, sup)
    zr_buf_byte(b, 41)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  if zr_singleton_p(sup)
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't make subclass of singleton class"), 38)
  end
  if sup == zr_global(G_CLASS)
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't make subclass of Class"), 28)
  end
  Machine.value(QNIL)
end

# A class without a metaclass yet: a builtin class gets one on first
# use, the way `zr_singleton_class` makes any.
sig [Value] => Value
machine def zr_class_boot(sup)
  zr_class_alloc(T_CLASS, sup, zr_global(G_CLASS))
end

# A class with its metaclass, as CRuby makes every class: the metaclass
# inherits from the superclass's, so class methods do too.
sig [Value] => Value
machine def zr_class_new(sup)
  c = zr_class_boot(sup)
  zr_make_metaclass(c)
  c
end

T_ICLASS = 28

# Whether `klass`'s chain holds `mod`, itself or as a proxy.
sig [Value, Value] => Bool
machine def zr_chain_includes(klass, mod)
  k = klass
  while k != QNIL
    if k == mod || ((RBasic.flags(k) & T_MASK) == T_ICLASS && RClass.attached(k) == mod)
      return true
    end
    k = RClass.superclass(k)
  end
  false
end

# A proxy standing for the chain node `node` (a module, or a proxy of
# one) ahead of `sup`, sharing the node's tables.
sig [Value, Value] => Value
machine def zr_iclass_new(node, sup)
  mod = zr_type(node) == T_ICLASS ? RClass.attached(node) : node
  ic = zr_alloc(T_ICLASS, mod, RClass.size)
  RClass.set_name(ic, Machine.value(QNIL))
  RClass.set_superclass(ic, sup)
  RClass.set_ext(ic, RClass.ext(node))
  RClass.set_attached(ic, mod)
  RClass.set_origin(ic, Machine.value(QNIL))
  zr_methods_changed()
  ic
end

# Where a class's own methods live: its origin proxy once something is
# prepended, else the class itself.
sig [Value] => Value
machine def zr_origin(klass)
  if RClass.origin(klass) != QNIL
    return RClass.origin(klass)
  end
  klass
end

# CRuby's include_modules_at: a proxy for each node of `mod`'s chain
# spliced in after `at`, but for a node whose tables `klass`'s chain
# already holds. An include (`whole`) searches the whole chain and
# moves the splice point to the node it finds, unless a superclass
# holds it; a prepend searches only down to `klass`'s origin. The
# proxy of a module's origin becomes the origin of the proxy of its
# head, as in the module itself.
sig [Value, Value, Value, Bool] => Void
machine def zr_splice_modules(klass, at, mod, whole)
  klass_origin = zr_origin(klass)
  c = at
  heads = zr_ary_new(2)
  m = mod
  while m != QNIL
    found = false
    if klass_origin != c || whole
      c_seen = klass == c
      class_seen = false
      p = RClass.superclass(klass)
      while p != QNIL && !found
        if klass_origin == p && !whole
          p = Machine.value(QNIL)
        else
          c_seen = true if c == p
          if zr_type(p) == T_ICLASS
            if RClass.ext(p) == RClass.ext(m)
              c = p if c_seen && !class_seen
              found = true
            end
          elsif zr_type(p) == T_CLASS
            class_seen = true
          end
          p = RClass.superclass(p) unless found
        end
      end
    end
    unless found
      ic = zr_iclass_new(m, RClass.superclass(c))
      RClass.set_superclass(c, ic)
      c = ic
      n = RArray.len(heads)
      if RClass.origin(m) != QNIL
        zr_ary_push(heads, ic)
        zr_ary_push(heads, RClass.origin(m))
      elsif n > 0 && zr_ary_at(heads, n - 1) == m
        RClass.set_origin(zr_ary_at(heads, n - 2), ic)
        RArray.set_len(heads, n - 2)
      end
    end
    m = RClass.superclass(m)
  end
  zr_methods_changed()
  zr_gates_recheck(0)
end

# The proxies standing for `mod` in other chains, newest first, as
# CRuby's subclass list of a module runs.
sig [Value] => Value
machine def zr_proxies_of(mod)
  out = zr_ary_new(4)
  a = 0
  while a < Heap.arenas(zr_heap())
    base = zr_arena_at(a)
    first = zr_arena_first(base)
    bytes = ArenaHead.cell(base)
    i = zr_arena_next_allocated(base, 0)
    while i < ARENA_CELLS
      cell = first + (i * bytes)
      if (Machine.load64(cell, 0) & T_MASK) == T_ICLASS
        ic = Machine.value(cell)
        if RClass.attached(ic) == mod && RClass.origin(mod) != ic
          zr_ary_unshift(out, ic)
        end
      end
      i = zr_arena_next_allocated(base, i + 1)
    end
    a += 1
  end
  out
end

# `include`: `mod`'s chain after `klass`'s origin, and after each
# proxy of a module `klass` already in another chain that lacks it.
sig [Value, Value] => Void
machine def zr_include_module(klass, mod)
  zr_splice_modules(klass, zr_origin(klass), mod, true)
  if zr_type(klass) != T_MODULE
    return
  end
  proxies = zr_proxies_of(klass)
  i = 0
  while i < RArray.len(proxies)
    ic = zr_ary_at(proxies, i)
    unless zr_chain_includes(ic, mod)
      zr_splice_modules(ic, zr_origin(ic), mod, true)
    end
    i += 1
  end
end

# The class's methods moved to an origin proxy right under it, where
# `super` from them starts; nothing when it has one.
sig [Value] => Bool
machine def zr_ensure_origin(klass)
  if RClass.origin(klass) != QNIL
    return false
  end
  o = zr_iclass_new(klass, RClass.superclass(klass))
  ext = zr_xmalloc(ClassExt.size)
  zr_memcpy(ext, RClass.ext(klass), ClassExt.size)
  ClassExt.set_ctab(ext, 0)
  ClassExt.set_clen(ext, 0)
  ClassExt.set_ccap(ext, 0)
  ClassExt.set_cidx(ext, 0)
  ClassExt.set_cbins(ext, 0)
  zr_ivtab_init(ClassExt.iv(ext))
  zr_ivtab_init(ClassExt.cv(ext))
  RClass.set_ext(o, ext)
  ClassExt.set_mtab(RClass.ext(klass), 0)
  ClassExt.set_mlen(RClass.ext(klass), 0)
  ClassExt.set_mcap(RClass.ext(klass), 0)
  # The table's index went with the table, to the origin's copy.
  ClassExt.set_midx(RClass.ext(klass), 0)
  ClassExt.set_mbins(RClass.ext(klass), 0)
  ClassExt.set_saved(RClass.ext(klass), 0)
  ClassExt.set_slen(RClass.ext(klass), 0)
  i = 0
  while i < ClassExt.mlen(ext)
    e = ClassExt.mtab(ext) + (i * MEntry.size)
    if MEntry.meta(e) != 0 && FrameMeta.owner(MEntry.meta(e)) == klass
      FrameMeta.set_owner(MEntry.meta(e), o)
    end
    i += 1
  end
  RClass.set_superclass(klass, o)
  RClass.set_origin(klass, o)
  zr_methods_changed()
  true
end

# `prepend`: `mod`'s chain between `klass` and its origin, and between
# each proxy of a module `klass` and that proxy's origin, which a
# proxy made before the module had one gets here.
sig [Value, Value] => Void
machine def zr_prepend_module(klass, mod)
  fresh = zr_ensure_origin(klass)
  zr_splice_modules(klass, klass, mod, false)
  if zr_type(klass) != T_MODULE
    return
  end
  proxies = zr_proxies_of(klass)
  i = 0
  while i < RArray.len(proxies)
    ic = zr_ary_at(proxies, i)
    if fresh && RClass.origin(ic) == QNIL
      o = zr_iclass_new(RClass.origin(klass), RClass.superclass(ic))
      RClass.set_superclass(ic, o)
      RClass.set_origin(ic, o)
    end
    zr_splice_modules(ic, ic, mod, false)
    i += 1
  end
end

# `prepend_features(base)`: the module (self) ahead of `base`'s own
# methods; the core's `prepend` calls it per module, then `prepended`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_prepend_features(recv, argc, argv, cref, blk)
  base = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(base) || (zr_type(base) != T_CLASS && zr_type(base) != T_MODULE)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
    zr_buf_class_of(b, base)
    zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  if zr_modify_frozen_p(base)
    return zr_frozen_error(base)
  end
  if recv == base || zr_chain_includes(recv, base)
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("cyclic prepend detected"), 23)
  end
  zr_prepend_module(base, recv)
  recv
end

# A hook such as `included` or `inherited`: `recv.mid(arg)`, private
# or not.
sig [Value, Word, Value] => Value
machine def zr_hook(recv, mid, arg)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(arg))
  zr_send(recv, mid, 1, slot)
end

sig [Value] => Value
machine def zr_check_module(m)
  if zr_special_p(m) || zr_type(m) != T_MODULE
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
    zr_buf_class_of(b, m)
    zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  Machine.value(QNIL)
end

# `append_features(base)`: the module (self) spliced into `base`; the
# core's `include` calls it per module, then `included`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_append_features(recv, argc, argv, cref, blk)
  base = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(base) || (zr_type(base) != T_CLASS && zr_type(base) != T_MODULE)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
    zr_buf_class_of(b, base)
    zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  if zr_modify_frozen_p(base)
    return zr_frozen_error(base)
  end
  if recv == base || zr_chain_includes(recv, base)
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("cyclic include detected"), 23)
  end
  zr_include_module(base, recv)
  recv
end

# `extend`: each module into the singleton class, then its `extended`
# hook.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_extend(recv, argc, argv, cref, blk)
  if argc == 0
    return zr_wrong_arity_min(0, 1)
  end
  i = argc - 1
  while i >= 0
    m = Machine.value(Machine.load64(argv + (i * 8), 0))
    r = zr_check_module(m)
    return r if r == QUNDEF
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(recv))
    r = zr_send(m, Machine.id(:extend_object), 1, slot)
    return r if r == QUNDEF
    r = zr_hook(m, Machine.id(:extended), recv)
    return r if r == QUNDEF
    i -= 1
  end
  recv
end

# `Module#extend_object`: the module into the object's singleton class;
# a module may override it to see each object it extends.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_extend_object(recv, argc, argv, cref, blk)
  obj = Machine.value(Machine.load64(argv, 0))
  s = zr_singleton_class(obj)
  return s if s == QUNDEF
  if !zr_special_p(obj) && zr_frozen_p(obj)
    return zr_frozen_error(obj)
  end
  zr_include_module(s, recv)
  obj
end

# `alias :"#{a}" :"#{b}"`: the names arrive as values.
sig [Value, Value, Value] => Value
machine def zr_alias_value(klass, new_name, old_name)
  made = Machine.slot(8)
  had = Machine.slot(8)
  r = zr_name_id(new_name, made)
  return r if r == QUNDEF
  r = zr_name_id(old_name, had)
  return r if r == QUNDEF
  zr_alias(klass, Machine.load64(made, 0), Machine.load64(had, 0))
end

# `alias new old` and `alias_method`: the old entry again under the new
# name, keeping its meta, so a backtrace names the original.
sig [Value, Word, Word] => Value
machine def zr_alias(klass, new_id, old_id)
  if zr_modify_frozen_p(klass)
    return zr_frozen_error(klass)
  end
  e = zr_find_method(klass, old_id)
  # A module's chain is the module alone, so Object's methods, Kernel's
  # among them, are looked for next, as rb_alias looks.
  if e == 0 && zr_type(klass) == T_MODULE
    e = zr_find_method(zr_global(G_OBJECT), old_id)
  end
  if e == 0
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("undefined method '"), 18)
    zr_buf_sym(b, old_id)
    zr_buf_push(b, zr_type(klass) == T_MODULE ? Machine.bytes("' for module '") : Machine.bytes("' for class '"), zr_type(klass) == T_MODULE ? 14 : 13)
    zr_buf_class(b, klass)
    zr_buf_byte(b, 39)
    return zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end
  zr_method_copy(klass, new_id, e, MEntry.meta(e), MEntry.vis(e), true)
  zr_method_added(klass, new_id)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_alias_method(recv, argc, argv, cref, blk)
  slot = Machine.slot(16)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  r = zr_name_id(Machine.value(Machine.load64(argv, 8)), slot + 8)
  return r if r == QUNDEF
  new_id = Machine.load64(slot, 0)
  r = zr_alias(recv, new_id, Machine.load64(slot, 8))
  return r if r == QUNDEF
  zr_sym(new_id)
end

# `undef name`: an entry that stops the search, so the name is gone
# from this class and its subclasses even where an ancestor has it.
# `undef :"#{a}"`: the name arrives as a value.
sig [Value, Value] => Value
machine def zr_undef_value(klass, name)
  slot = Machine.slot(8)
  r = zr_name_id(name, slot)
  return r if r == QUNDEF
  zr_undef(klass, Machine.load64(slot, 0))
end

sig [Value, Word] => Value
machine def zr_undef(klass, id)
  if zr_modify_frozen_p(klass)
    return zr_frozen_error(klass)
  end
  if zr_find_method(klass, id) == 0
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("undefined method '"), 18)
    zr_buf_sym(b, id)
    zr_buf_push(b, zr_type(klass) == T_MODULE ? Machine.bytes("' for module '") : Machine.bytes("' for class '"), zr_type(klass) == T_MODULE ? 14 : 13)
    zr_buf_class(b, klass)
    zr_buf_byte(b, 39)
    return zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end
  zr_method_add(klass, id, 0, 0, KIND_UNDEF, 0, Machine.value(QNIL))
  zr_method_undefined(klass, id)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_undef_method(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  i = 0
  while i < argc
    r = zr_name_id(Machine.value(Machine.load64(argv + (i * 8), 0)), slot)
    return r if r == QUNDEF
    r = zr_undef(recv, Machine.load64(slot, 0))
    return r if r == QUNDEF
    i += 1
  end
  recv
end

# `Module#===`: whether the object is one of the module's.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_eqq(recv, argc, argv, cref, blk)
  zr_bool(zr_is_a(Machine.value(Machine.load64(argv, 0)), recv))
end

# The class a class variable belongs to under `cref`: the innermost
# class, past a singleton class to what it is attached to. The
# toplevel has none, though a `class Object` body does.
sig [Value] => Value
machine def zr_cvar_base(cref)
  cref = zr_cref_lexical(cref)
  if cref == zr_global(G_TOP_CREF)
    return Machine.value(QNIL)
  end
  k = zr_cref_klass(cref)
  while zr_singleton_p(k)
    k = RClass.attached(k)
    if zr_special_p(k) || (zr_type(k) != T_CLASS && zr_type(k) != T_MODULE)
      return Machine.value(QNIL)
    end
  end
  k
end

# The class in `klass`'s chain whose table holds `id`, or nil.
sig [Value, Word] => Value
machine def zr_cvar_owner(klass, id)
  k = klass
  while k != QNIL
    if zr_ivtab_row(ClassExt.cv(RClass.ext(k)), id) != 0
      return k
    end
    k = RClass.superclass(k)
  end
  Machine.value(QNIL)
end

sig [Value, Word] => Value
machine def zr_cvar_get(cref, id)
  base = zr_cvar_base(cref)
  if base == QNIL
    return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("class variable access from toplevel"), 35)
  end
  owner = zr_cvar_owner(base, id)
  if owner == QNIL
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("uninitialized class variable "), 29)
    zr_buf_sym(b, id)
    zr_buf_push(b, Machine.bytes(" in "), 4)
    zr_buf_class(b, base)
    return zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end
  zr_ivtab_get(ClassExt.cv(RClass.ext(owner)), id)
end

# Whether `@@id` is set under `cref`.
sig [Value, Word] => Value
machine def zr_cvar_defined(cref, id)
  base = zr_cvar_base(cref)
  if base == QNIL
    return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("class variable access from toplevel"), 35)
  end
  zr_bool(zr_cvar_owner(base, id) != QNIL)
end

sig [Value, Word, Value] => Value
machine def zr_cvar_set(cref, id, v)
  base = zr_cvar_base(cref)
  if base == QNIL
    return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("class variable access from toplevel"), 35)
  end
  owner = zr_cvar_owner(base, id)
  if owner == QNIL
    owner = base
  end
  frozen = zr_class_modify_check(owner)
  return frozen if frozen == QUNDEF
  zr_ivtab_set(ClassExt.cv(RClass.ext(owner)), id, v)
  zr_write_barrier(owner, v)
  v
end

# `@@name` for the walking eval road, which has a Symbol where
# compiled code has an id. The lookup is the kernel's own, so a
# string it evaluates reads and writes the class variable compiled
# code reaches.
sig [Value, Value] => Value
machine def zr_cvar_get_m(cref, name)
  zr_cvar_get(cref, zr_sym2id(name))
end

sig [Value, Value] => Value
machine def zr_cvar_defined_m(cref, name)
  zr_cvar_defined(cref, zr_sym2id(name))
end

sig [Value, Value, Value] => Value
machine def zr_cvar_set_m(cref, name, v)
  zr_cvar_set(cref, zr_sym2id(name), v)
end

# `Module#ancestors`: the chain, proxies as the modules they stand for.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_ancestors(recv, argc, argv, cref, blk)
  out = zr_ary_new(8)
  k = recv
  while k != QNIL
    if RClass.origin(k) == QNIL
      zr_ary_push(out, zr_type(k) == T_ICLASS ? RClass.attached(k) : k)
    end
    k = RClass.superclass(k)
  end
  out
end

# `Module#include?`: `mod` is in the chain, other than as itself.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_include_p(recv, argc, argv, cref, blk)
  m = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(m) || zr_type(m) != T_MODULE
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
    zr_buf_class_of(b, m)
    zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  zr_bool(m != recv && zr_chain_includes(recv, m))
end

sig [Value] => Bool
machine def zr_singleton_p(klass)
  (RBasic.flags(klass) & FL_SINGLETON) != 0
end

# The singleton class of the class `klass`: its superclass's, or Class
# for a root; `klass` itself has it as its class from here on.
sig [Value] => Value
machine def zr_make_metaclass(klass)
  sup = RClass.superclass(klass)
  while sup != QNIL && zr_type(sup) == T_ICLASS
    sup = RClass.superclass(sup)
  end
  if sup == QNIL
    msup = zr_global(G_CLASS)
  else
    msup = zr_singleton_class(sup)
  end
  meta = zr_class_alloc(T_CLASS, msup, zr_global(G_CLASS))
  # A singleton class is frozen when its object is.
  RBasic.set_flags(meta, RBasic.flags(meta) | FL_SINGLETON | (RBasic.flags(klass) & FL_FREEZE))
  RClass.set_attached(meta, klass)
  RBasic.set_klass(klass, meta)
  meta
end

# Whether `v` can have no singleton class: an Integer, a Float, a
# Symbol, or a String the fstring table holds, as CRuby's
# rb_singleton_class refuses them. nil, true and false answer their
# own class instead.
sig [Value] => Bool
machine def zr_singleton_refused_p(v)
  if zr_special_p(v)
    return v != QNIL && v != QTRUE && v != QFALSE
  end
  zr_big_p(v) || zr_type(v) == T_FLOAT || zr_type(v) == T_SYMBOL || (zr_type(v) == T_STRING && (RBasic.flags(v) & FL_FSTR) != 0)
end

# The singleton class of `v`, made on first use.
sig [Value] => Value
machine def zr_singleton_class(v)
  if zr_singleton_refused_p(v)
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't define singleton"), 22)
  end
  if zr_special_p(v)
    return zr_class_of(v)
  end
  k = RBasic.klass(v)
  if zr_singleton_p(k) && RClass.attached(k) == v
    return k
  end
  if zr_type(v) == T_CLASS
    return zr_make_metaclass(v)
  end
  s = zr_class_alloc(T_CLASS, k, zr_global(G_CLASS))
  RBasic.set_flags(s, RBasic.flags(s) | FL_SINGLETON | (RBasic.flags(v) & FL_FREEZE))
  RClass.set_attached(s, v)
  RBasic.set_klass(v, s)
  s
end

# Before a change to a class's own tables: its own frozen flag, never
# its origin's. A frozen singleton class names the object it belongs
# to, as CRuby's rb_class_modify_check does.
sig [Value] => Value
machine def zr_class_modify_check(klass)
  if !zr_frozen_p(klass)
    return Machine.value(QNIL)
  end
  zr_frozen_error(zr_singleton_p(klass) ? RClass.attached(klass) : klass)
end

# The class `v.class` answers: past any singleton class.
# The class an object answers `class` with: past its singleton class
# and the proxies of the modules it extends.
sig [Value] => Value
machine def zr_real_class(v)
  k = zr_class_of(v)
  while zr_singleton_p(k) || zr_type(k) == T_ICLASS
    k = RClass.superclass(k)
  end
  k
end

# The path of `v`'s class (zr_class_path): a String always, as a
# message wants it.
sig [Value] => Value
machine def zr_class_name_of(v)
  zr_class_path(zr_real_class(v))
end

sig [] => Value
machine def zr_module_new
  zr_class_alloc(T_MODULE, Machine.value(QNIL), zr_global(G_MODULE))
end

# The gate bit an operator's redefinition sets, or 0.
sig [Value, Word] => Word
machine def zr_gate_bit(klass, mid)
  if klass == zr_global(G_INTEGER)
    if mid == Machine.id(:+)
      GATE_PLUS
    elsif mid == Machine.id(:-)
      GATE_MINUS
    elsif mid == Machine.id(:*)
      GATE_MUL
    elsif mid == Machine.id(:/)
      GATE_DIV
    elsif mid == Machine.id(:%)
      GATE_MOD
    elsif mid == Machine.id(:<)
      GATE_LT
    elsif mid == Machine.id(:<=)
      GATE_LE
    elsif mid == Machine.id(:>)
      GATE_GT
    elsif mid == Machine.id(:>=)
      GATE_GE
    elsif mid == Machine.id(:==)
      GATE_EQ
    elsif mid == Machine.id(:!=)
      GATE_NE
    elsif mid == Machine.id(:&)
      GATE_AND
    elsif mid == Machine.id(:|)
      GATE_OR
    elsif mid == Machine.id(:^)
      GATE_XOR
    elsif mid == Machine.id(:>>)
      GATE_SHR
    else
      0
    end
  elsif klass == zr_global(G_FLOAT)
    if mid == Machine.id(:+)
      GATE_FLO_PLUS
    elsif mid == Machine.id(:-)
      GATE_FLO_MINUS
    elsif mid == Machine.id(:*)
      GATE_FLO_MUL
    elsif mid == Machine.id(:/)
      GATE_FLO_DIV
    elsif mid == Machine.id(:<)
      GATE_FLO_LT
    elsif mid == Machine.id(:<=)
      GATE_FLO_LE
    elsif mid == Machine.id(:>)
      GATE_FLO_GT
    elsif mid == Machine.id(:>=)
      GATE_FLO_GE
    elsif mid == Machine.id(:==)
      GATE_FLO_EQ
    else
      0
    end
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[])
    GATE_AREF
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[]=)
    GATE_ASET
  elsif klass == zr_global(G_HASH) && mid == Machine.id(:[])
    GATE_HASH_AREF
  elsif klass == zr_global(G_HASH) && mid == Machine.id(:[]=)
    GATE_HASH_ASET
  elsif (klass == zr_global(G_ARRAY) || klass == zr_global(G_STRING)) && mid == Machine.id(:<<)
    GATE_LTLT
  elsif klass == zr_global(G_STRING) && mid == Machine.id(:freeze)
    GATE_FREEZE
  elsif klass == zr_global(G_STRING) && mid == Machine.id(:getbyte)
    GATE_GETBYTE
  elsif klass == zr_global(G_STRING) && mid == Machine.id(:setbyte)
    GATE_SETBYTE
  elsif klass == zr_global(G_INTEGER) && mid == Machine.id(:succ)
    GATE_SUCC
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:push)
    GATE_PUSH
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:pop)
    GATE_POP
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:shift)
    GATE_SHIFT
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:empty?)
    GATE_EMPTY_P
  elsif klass == zr_global(G_PROC) && mid == Machine.id(:call)
    GATE_PROC_CALL
  elsif mid == Machine.id(:!) && zr_not_gated_p(klass)
    GATE_NOT
  else
    0
  end
end

# The classes whose `!` an inline `not` stands in for: nil, true and
# false answer inline while none of their ancestors redefines `!`.
sig [Value] => Bool
machine def zr_not_gated_p(klass)
  klass == zr_global(G_NIL) || klass == zr_global(G_TRUE) || klass == zr_global(G_FALSE) ||
    klass == zr_global(G_OBJECT) || klass == zr_global(G_KERNEL) || klass == zr_global(G_BASIC_OBJECT)
end

# The operators compiled code inlines, each as the program found it when
# it started: the class the gate guards (a global's index), the name,
# the gate bit, and the body and visibility that class found then.
Machine.struct :GateRow, klass: Word, mid: Word, bit: Word, fn: Ptr, vis: Word
GATE_ROWS = 39

sig [Word, Word, Word, Word] => Word
machine def zr_gate_row(i, klass, mid, bit)
  row = Machine.static(:gate_rows, GATE_ROWS * GateRow.size) + (i * GateRow.size)
  GateRow.set_klass(row, klass)
  GateRow.set_mid(row, mid)
  GateRow.set_bit(row, bit)
  e = zr_search_method(zr_global(klass), mid)
  if e != 0
    GateRow.set_fn(row, zr_entry_body(e))
    GateRow.set_vis(row, MEntry.vis(e))
  end
  i + 1
end

# When the program starts, after the runtime's own definitions: from
# here on, a change to what a row's class finds closes that row's gate.
sig [] => Void
machine def zr_gates_snapshot
  i = zr_gate_row(0, G_INTEGER, Machine.id(:+), GATE_PLUS)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:-), GATE_MINUS)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:*), GATE_MUL)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:/), GATE_DIV)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:%), GATE_MOD)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:<), GATE_LT)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:<=), GATE_LE)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:>), GATE_GT)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:>=), GATE_GE)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:==), GATE_EQ)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:!=), GATE_NE)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:&), GATE_AND)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:|), GATE_OR)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:^), GATE_XOR)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:>>), GATE_SHR)
  i = zr_gate_row(i, G_ARRAY, Machine.id(:[]), GATE_AREF)
  i = zr_gate_row(i, G_ARRAY, Machine.id(:[]=), GATE_ASET)
  i = zr_gate_row(i, G_HASH, Machine.id(:[]), GATE_HASH_AREF)
  i = zr_gate_row(i, G_HASH, Machine.id(:[]=), GATE_HASH_ASET)
  i = zr_gate_row(i, G_ARRAY, Machine.id(:<<), GATE_LTLT)
  i = zr_gate_row(i, G_STRING, Machine.id(:<<), GATE_LTLT)
  i = zr_gate_row(i, G_STRING, Machine.id(:freeze), GATE_FREEZE)
  i = zr_gate_row(i, G_FLOAT, Machine.id(:+), GATE_FLO_PLUS)
  i = zr_gate_row(i, G_FLOAT, Machine.id(:-), GATE_FLO_MINUS)
  i = zr_gate_row(i, G_FLOAT, Machine.id(:*), GATE_FLO_MUL)
  i = zr_gate_row(i, G_FLOAT, Machine.id(:/), GATE_FLO_DIV)
  i = zr_gate_row(i, G_FLOAT, Machine.id(:<), GATE_FLO_LT)
  i = zr_gate_row(i, G_FLOAT, Machine.id(:<=), GATE_FLO_LE)
  i = zr_gate_row(i, G_FLOAT, Machine.id(:>), GATE_FLO_GT)
  i = zr_gate_row(i, G_FLOAT, Machine.id(:>=), GATE_FLO_GE)
  i = zr_gate_row(i, G_FLOAT, Machine.id(:==), GATE_FLO_EQ)
  i = zr_gate_row(i, G_STRING, Machine.id(:getbyte), GATE_GETBYTE)
  i = zr_gate_row(i, G_STRING, Machine.id(:setbyte), GATE_SETBYTE)
  i = zr_gate_row(i, G_INTEGER, Machine.id(:succ), GATE_SUCC)
  i = zr_gate_row(i, G_ARRAY, Machine.id(:push), GATE_PUSH)
  i = zr_gate_row(i, G_ARRAY, Machine.id(:pop), GATE_POP)
  i = zr_gate_row(i, G_ARRAY, Machine.id(:shift), GATE_SHIFT)
  i = zr_gate_row(i, G_ARRAY, Machine.id(:empty?), GATE_EMPTY_P)
  zr_gate_row(i, G_PROC, Machine.id(:call), GATE_PROC_CALL)
  Machine.store64(Machine.static(:gates_taken, 8), 0, 1)
end

# After a definition, a visibility change, a removal or a module spliced
# into a chain: the gate of each row whose class now finds another body
# for the name, or finds it under another visibility, closes, and every
# site of that operator takes the call. `mid` 0 asks every row. A gate
# never opens again. The walk leaves `Task.found` as the send that
# asked left it.
sig [Word] => Void
machine def zr_gates_recheck(mid)
  if Machine.load64(Machine.static(:gates_taken, 8), 0) == 0
    return
  end
  found = Task.found(zr_task())
  rows = Machine.static(:gate_rows, GATE_ROWS * GateRow.size)
  i = 0
  while i < GATE_ROWS
    row = rows + (i * GateRow.size)
    if (mid == 0 || GateRow.mid(row) == mid) && (Machine.gates & GateRow.bit(row)) == 0
      e = zr_search_method(zr_global(GateRow.klass(row)), GateRow.mid(row))
      if e == 0 || zr_entry_body(e) != GateRow.fn(row) || MEntry.vis(e) != GateRow.vis(row)
        Machine.gates_set(Machine.gates | GateRow.bit(row))
      end
    end
    i += 1
  end
  Task.set_found(zr_task(), found)
end

# A definition; the first one of each builtin operator is the runtime's
# own and leaves the gate clear, a later one sets it. `meta` is the
# compiled def's own FrameMeta, or 0 for a builtin, which gets one here.
sig [Value, Word, Ptr, Word, Word, Ptr, Value] => Value
machine def zr_define_method(klass, mid, fn, arity, kind, meta, cref)
  zr_define_method_as(klass, mid, fn, arity, kind, meta, cref, zr_definition_vis(mid, cref))
end

# A def with a direct entry (MEntry.direct): `fn` is zr_direct_fn, and
# `direct` the body. The entry waits in a static word for the row,
# which zr_define_method_as reads and clears before any hook runs --
# `method_added` may call the method it was told of -- since the row's
# eight fields fill the argument registers already.
sig [Value, Word, Ptr, Ptr, Word, Word, Ptr, Value] => Value
machine def zr_define_method_direct(klass, mid, fn, direct, arity, kind, meta, cref)
  Machine.store64(zr_direct_pending(), 0, Machine.word(direct))
  zr_define_method(klass, mid, fn, arity, kind, meta, cref)
end

sig [Value, Word, Ptr, Ptr, Word, Word, Ptr, Value] => Value
machine def zr_define_method_public_direct(klass, mid, fn, direct, arity, kind, meta, cref)
  Machine.store64(zr_direct_pending(), 0, Machine.word(direct))
  zr_define_method_public(klass, mid, fn, arity, kind, meta, cref)
end

sig [] => Ptr
machine def zr_direct_pending
  Machine.static(:direct_pending, 8)
end

# The body of `e`, what tells one method from another: its direct
# entry where it has one, since every such def's `fn` is
# zr_direct_fn, else its `fn`.
sig [Ptr] => Ptr
machine def zr_entry_body(e)
  direct = MEntry.direct(e)
  direct != 0 ? direct : MEntry.fn(e)
end

# `def obj.name`, and a def inside a method body: public whatever the
# scope's visibility verb says, except the initialize family.
sig [Value, Word, Ptr, Word, Word, Ptr, Value] => Value
machine def zr_define_method_public(klass, mid, fn, arity, kind, meta, cref)
  zr_define_method_as(klass, mid, fn, arity, kind, meta, cref, zr_definition_vis(mid, Machine.value(QNIL)))
end

sig [Value, Word, Ptr, Word, Word, Ptr, Value, Word] => Value
machine def zr_define_method_as(klass, mid, fn, arity, kind, meta, cref, vis)
  # Under `1.instance_eval` no singleton class can take the method.
  if cref != QNIL && RCref.eval(cref) == EVAL_NO_DEF
    Machine.store64(zr_direct_pending(), 0, 0)
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't define singleton"), 22)
  end
  frozen = zr_class_modify_check(klass)
  if frozen == QUNDEF
    Machine.store64(zr_direct_pending(), 0, 0)
    return frozen
  end
  klass = zr_origin(klass)
  if meta == 0
    meta = zr_xmalloc(FrameMeta.size)
    FrameMeta.set_file(meta, 0)
    FrameMeta.set_file_len(meta, 0)
    FrameMeta.set_kind(meta, KIND_BUILTIN)
    FrameMeta.set_line(meta, 0)
    FrameMeta.set_parent(meta, 0)
    FrameMeta.set_arity(meta, arity)
    FrameMeta.set_params(meta, 0)
    FrameMeta.set_fn(meta, 0)
    FrameMeta.set_box(meta, Machine.value(QNIL))
    FrameMeta.set_ruby(meta, 0)
    FrameMeta.set_node(meta, 0)
    FrameMeta.set_cover(meta, 0)
  elsif Machine.word(FrameMeta.owner(meta)) != 0 && FrameMeta.owner(meta) != klass
    # The same def run under another class (a class body in a block
    # that runs twice) gets a meta of its own, so each keeps its owner.
    copy = zr_xmalloc(FrameMeta.size)
    zr_memcpy(copy, meta, FrameMeta.size)
    meta = copy
  end
  FrameMeta.set_name(meta, mid)
  FrameMeta.set_owner(meta, klass)
  modfn = cref != QNIL && RCref.modfn(cref) != 0
  core = !zr_program_started_p() || zr_internal_meta_p(meta) ? ROW_CORE : 0
  if modfn
    single = zr_singleton_class(klass)
    owned = zr_meta_owned(meta, single)
    zr_method_add_row(single, mid, fn, arity, kind, owned, cref, VIS_PUBLIC | core)
    zr_coverage_method_claim(single, mid, owned)
  end
  zr_method_add_row(klass, mid, fn, arity, kind, meta, cref, vis | core)
  zr_coverage_method_claim(klass, mid, meta)
  # The rows have their direct entry (zr_define_method_direct); the
  # hooks run under no pending one.
  Machine.store64(zr_direct_pending(), 0, 0)
  # Under `module_function` one def makes two methods, and ruby reports
  # both of them.
  r = zr_method_added(klass, mid)
  return r if r == QUNDEF || !modfn

  zr_method_added(zr_singleton_class(klass), mid)
end

# `meta` as the method `owner` holds reports it: the module function's
# copy on the singleton class labels its frames `Mod.name`, where the
# private instance method labels them `Mod#name`.
sig [Ptr, Value] => Ptr
machine def zr_meta_owned(meta, owner)
  if meta == 0 || FrameMeta.owner(meta) == owner
    return meta
  end
  copy = zr_xmalloc(FrameMeta.size)
  zr_memcpy(copy, meta, FrameMeta.size)
  FrameMeta.set_owner(copy, owner)
  copy
end

# The visibility a definition under `cref` gets: the body's current
# one, private under `module_function`, and always private for
# `initialize` and its kin.
sig [Word, Value] => Word
machine def zr_definition_vis(mid, cref)
  if mid == Machine.id(:initialize) || mid == Machine.id(:initialize_copy) || mid == Machine.id(:respond_to_missing?)
    return VIS_PRIVATE
  end
  if cref == QNIL
    return VIS_PUBLIC
  end
  if RCref.modfn(cref) != 0
    return VIS_PRIVATE
  end
  RCref.vis(cref)
end

# The visibility and the `module_function` copy a `def` gets under
# `cref`, for the walking eval road: it defines a method the way
# `Module#define_method` does and then owes the body its own rules,
# which only the cref knows. 0 public, 1 private, 2 protected.
sig [Value, Value] => Value
machine def zr_definition_vis_m(name, cref)
  zr_fix(zr_definition_vis(zr_sym2id(name), cref))
end

# Whether a `def` under `cref` also copies itself to the singleton
# class, which `module_function` asks for.
sig [Value] => Value
machine def zr_cref_modfn_p(cref)
  zr_bool(cref != QNIL && RCref.modfn(cref) != 0)
end

# A method whose body is the Proc `body`, kept in the entry's cref
# slot; `cref` gives the visibility.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_define_bmethod(klass, mid, meta, body, cref)
  klass = zr_origin(klass)
  FrameMeta.set_name(meta, mid)
  FrameMeta.set_owner(meta, klass)
  modfn = cref != QNIL && RCref.modfn(cref) != 0
  # `meta` is the frame the call stands in, which is what a backtrace
  # names; Coverage names the block instead, so the row is claimed from
  # the Proc's own meta -- and a Proc a Symbol or a Method made has
  # none, which is where CRuby's rb_proc_get_iseq answers nothing.
  block_meta = RProc.meta(body)
  if modfn
    single = zr_singleton_class(klass)
    zr_method_add_vis(single, mid, 0, 0 - 1, KIND_BMETHOD, meta, body, VIS_PUBLIC)
    zr_coverage_method_claim(single, mid, block_meta)
  end
  zr_method_add_vis(klass, mid, 0, 0 - 1, KIND_BMETHOD, meta, body, zr_definition_vis(mid, cref))
  zr_coverage_method_claim(klass, mid, block_meta)
  r = zr_method_added(klass, mid)
  return r if r == QUNDEF || !modfn

  zr_method_added(zr_singleton_class(klass), mid)
end

# The `method_added` hook, or `singleton_method_added` on the object
# a singleton class is attached to; nothing until the hooks exist.
sig [Value, Word] => Value
machine def zr_method_added(klass, mid)
  if zr_type(klass) == T_ICLASS
    klass = RClass.attached(klass)
  end
  if zr_singleton_p(klass)
    recv = RClass.attached(klass)
    hook = Machine.id(:singleton_method_added)
  else
    recv = klass
    hook = Machine.id(:method_added)
  end
  if zr_find_method(zr_class_of(recv), hook) == 0
    return Machine.value(QNIL)
  end
  zr_hook(recv, hook, zr_sym(mid))
end

sig [Value, Word, Ptr, Word, Word, Ptr, Value] => Void
machine def zr_method_add(klass, mid, fn, arity, kind, meta, cref)
  zr_method_add_vis(klass, mid, fn, arity, kind, meta, cref, VIS_PUBLIC)
end

# The entry into the table, the meta as it is (an alias keeps the
# original's name).
sig [Value, Word, Ptr, Word, Word, Ptr, Value, Word] => Void
machine def zr_method_add_vis(klass, mid, fn, arity, kind, meta, cref, vis)
  zr_method_add_row(klass, mid, fn, arity, kind, meta, cref, zr_program_started_p() ? vis : vis | ROW_CORE)
end

# Whether `meta` is a method the runtime's own Ruby wrote, which leaves
# no file on its frames: a library such as zlib is the core library's
# too, though it loads after the program starts.
sig [Ptr] => Bool
machine def zr_internal_meta_p(meta)
  meta != 0 && FrameMeta.file_len(meta) == 0 && (FrameMeta.kind(meta) == KIND_BUILTIN || FrameMeta.kind(meta) == KIND_HIDDEN)
end

# The same, `vis` with ROW_CORE when the core library defines the row:
# its own sends reach that row past what a program writes over it later.
ROW_CORE = 256

sig [Value, Word, Ptr, Word, Word, Ptr, Value, Word] => Void
machine def zr_method_add_row(klass, mid, fn, arity, kind, meta, cref, vis)
  core = (vis & ROW_CORE) != 0
  vis = vis & (ROW_CORE - 1)
  klass = zr_origin(klass)
  # Only a handful of names have a gate, so ask for the bit before
  # asking the chain whether this is a redefinition. A builtin row the
  # runtime writes at boot stands where the kernel's own did: `freeze`
  # on String is Kernel's function, which the fast path stands in for.
  bit = zr_gate_bit(klass, mid)
  booting = kind == KIND_BUILTIN && !zr_program_started_p()
  if bit != 0 && !booting && zr_find_method(klass, mid) != 0
    Machine.gates_set(Machine.gates | bit)
  end
  zr_methods_changed()
  ext = RClass.ext(klass)
  # A redefinition takes the row the name already has, which is where
  # ruby keeps it: `instance_methods` shows it in the place it was first
  # defined, and a later `remove_method` leaves nothing behind.
  e = zr_find_method_at(klass, mid)
  if e != 0
    zr_warn_redefined(ext, mid, e, fn, kind, meta, cref)
  end
  if !core
    zr_save_core_row(ext, e)
  end
  if e == 0
    n = ClassExt.mlen(ext)
    if n == ClassExt.mcap(ext)
      cap = n * 2
      if cap < 8
        cap = 8
      end
      tab = zr_xmalloc(cap * MEntry.size)
      old = ClassExt.mtab(ext)
      if old != 0
        zr_memcpy(tab, old, n * MEntry.size)
        zr_xfree(old)
      end
      ClassExt.set_mtab(ext, tab)
      ClassExt.set_mcap(ext, cap)
    end
    e = ClassExt.mtab(ext) + (n * MEntry.size)
    ClassExt.set_mlen(ext, n + 1)
    MEntry.set_mid(e, mid)
    zr_method_index_add(ext, n)
  end
  MEntry.set_mid(e, mid)
  MEntry.set_fn(e, fn)
  MEntry.set_arity(e, arity)
  MEntry.set_kind(e, kind)
  MEntry.set_meta(e, meta)
  MEntry.set_cref(e, cref)
  zr_write_barrier(klass, cref)
  MEntry.set_vis(e, vis)
  MEntry.set_orig(e, mid)
  MEntry.set_from(e, Machine.value(QNIL))
  MEntry.set_core(e, core ? 1 : 0)
  MEntry.set_cover(e, 0)
  MEntry.set_direct(e, Machine.ptr(Machine.load64(zr_direct_pending(), 0)))
  IvarCache.set_index(MEntry.ivar(e), 0)
  zr_gates_recheck(mid)
end

# `method redefined; discarding old m`, where rb_method_entry_make warns:
# under `$VERBOSE` true, for a definition over a row that is no undef,
# no alias, no copy a visibility verb made on an ancestor's method, and
# not aliased itself. A method written in Ruby says where it was. The
# runtime's own definitions are not the program's, and say nothing.
sig [Ptr, Word, Ptr, Ptr, Word, Ptr, Value] => Void
machine def zr_warn_redefined(ext, mid, e, fn, kind, meta, cref)
  if zr_gvar_get(Machine.id(:$VERBOSE)) != QTRUE || !zr_program_started_p() || Task.top(zr_task()) == 0
    return
  end
  if kind == KIND_UNDEF || MEntry.kind(e) == KIND_UNDEF || MEntry.orig(e) != mid || MEntry.from(e) != QNIL || zr_entry_hidden_p(e)
    return
  end
  # The same definition again, as `alias_method :m, :m` or a second
  # `module_function :m` writes it: the same body, or the same Proc.
  body = Machine.ptr(Machine.load64(zr_direct_pending(), 0))
  if body == 0
    body = fn
  end
  if MEntry.kind(e) == kind && (kind == KIND_BMETHOD ? MEntry.cref(e) == cref : zr_entry_body(e) == body && !zr_word_entry_p(kind))
    return
  end
  if zr_internal_meta_p(meta) && !zr_word_entry_p(kind)
    return
  end
  if MEntry.fn(e) == 0 && MEntry.kind(e) != KIND_BMETHOD && !zr_word_entry_p(MEntry.kind(e))
    return
  end
  i = 0
  while i < ClassExt.mlen(ext)
    row = ClassExt.mtab(ext) + (i * MEntry.size)
    if row != e && MEntry.orig(row) == mid && MEntry.mid(row) != mid && MEntry.kind(row) != KIND_UNDEF
      return
    end
    i += 1
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("method redefined; discarding old "), 33)
  zr_buf_sym(b, mid)
  old = MEntry.meta(e)
  if (MEntry.kind(e) == KIND_DEF || MEntry.kind(e) == KIND_BMETHOD) && old != 0 && FrameMeta.file_len(old) > 0
    zr_buf_byte(b, 10)
    zr_buf_push(b, FrameMeta.file(old), FrameMeta.file_len(old))
    zr_buf_byte(b, 58)
    zr_buf_long(b, FrameMeta.line(old))
    zr_buf_push(b, Machine.bytes(": warning: previous definition of "), 34)
    zr_buf_sym(b, mid)
    zr_buf_push(b, Machine.bytes(" was here"), 9)
  end
  zr_warn_here(Buf.ptr(b), Buf.len(b))
  zr_buf_free(b)
end

# Whether the program has started: the core library's own definitions
# are all written.
sig [] => Bool
machine def zr_program_started_p
  Machine.load64(Machine.static(:program_started, 8), 0) != 0
end

# The runtime's own definitions are all written: what is defined from
# here on is the program's, the gem prelude's libraries first.
sig [] => Void
machine def zr_runtime_written
  Machine.store64(Machine.static(:program_started, 8), 0, 1)
end

# Row `e` of `ext`, a row of the core library a program is about to
# write over or remove, kept aside for the core library's own sends.
# Nothing is kept for any other row, or twice for one name.
sig [Ptr, Ptr] => Void
machine def zr_save_core_row(ext, e)
  if e == 0 || MEntry.core(e) == 0 || !zr_program_started_p() || zr_saved_row(ext, MEntry.mid(e)) != 0
    return
  end
  n = ClassExt.slen(ext)
  tab = zr_xmalloc((n + 1) * MEntry.size)
  if n > 0
    zr_memcpy(tab, ClassExt.saved(ext), n * MEntry.size)
    zr_xfree(ClassExt.saved(ext))
  end
  zr_memcpy(tab + (n * MEntry.size), e, MEntry.size)
  ClassExt.set_saved(ext, tab)
  ClassExt.set_slen(ext, n + 1)
end

sig [Ptr, Word] => Ptr
machine def zr_saved_row(ext, mid)
  i = 0
  while i < ClassExt.slen(ext)
    e = ClassExt.saved(ext) + (i * MEntry.size)
    if MEntry.mid(e) == mid
      return e
    end
    i += 1
  end
  0
end

# Whether the core library's own sends to an instance of `klass` reach
# the core library's methods: a class the runtime made before the
# program started. A class's singleton class counts as the class it is
# attached to, so a program's subclass keeps its own class methods; any
# other singleton class counts as the class it stands ahead of.
sig [Value] => Bool
machine def zr_core_class_p(klass)
  if !zr_program_started_p()
    return false
  end
  while klass != QNIL && (RBasic.flags(klass) & FL_SINGLETON) != 0
    attached = RClass.attached(klass)
    if !zr_special_p(attached) && (zr_type(attached) == T_CLASS || zr_type(attached) == T_MODULE)
      klass = attached
    else
      klass = RClass.superclass(klass)
    end
  end
  klass != QNIL && ClassExt.serial(RClass.ext(klass)) <= Machine.load64(Machine.static(:master_serial, 8), 0)
end

# The entry a send the core library makes reaches for `mid` on
# `klass`: the core library's own row, past every row a program wrote
# over it, removed, or put ahead of it with a module, as a call in
# CRuby's C reaches a C function and not the method a program defines.
# 0 when the core library defines no such method on the chain, where
# the send reaches what any send reaches.
sig [Value, Word] => Ptr
machine def zr_search_core_method(klass, mid)
  k = klass
  while k != QNIL
    ext = RClass.ext(k)
    e = zr_saved_row(ext, mid)
    if e == 0
      e = zr_find_method_at(k, mid)
      if e != 0 && MEntry.core(e) == 0
        e = 0
      end
    end
    if e != 0
      if MEntry.kind(e) == KIND_UNDEF
        return 0
      end
      Task.set_found(zr_task(), k)
      return e
    end
    k = RClass.superclass(k)
  end
  0
end

# The same, from the method cache under a key of its own.
sig [Value, Word] => Ptr
machine def zr_find_core_method(klass, mid)
  mode = Machine.load64(Machine.static(:mcache_mode, 8), 0)
  if mode == MCACHE_OFF
    return zr_search_core_method(klass, mid)
  end
  key = mid | CORE_KEY
  h = ((Machine.word(klass) / CELL_MIN) ^ (key * 31)) & (MCACHE_ROWS - 1)
  row = Machine.static(:mcache, MCACHE_ROWS * MCache.size) + (h * MCache.size)
  stamp = Machine.load64(Machine.static(:mcache_stamp, 8), 0)
  if MCache.stamp(row) == stamp && MCache.klass(row) == klass && MCache.mid(row) == key
    e = MCache.entry(row)
    if e != 0
      Task.set_found(zr_task(), MCache.found(row))
    end
    if mode == MCACHE_VERIFY && e != zr_search_core_method(klass, mid)
      zr_bug(Machine.bytes("the method cache answered what the core chain does not\n"), 55)
    end
    return e
  end
  e = zr_search_core_method(klass, mid)
  MCache.set_klass(row, klass)
  MCache.set_mid(row, key)
  MCache.set_entry(row, e)
  MCache.set_found(row, e == 0 ? Machine.value(QNIL) : Task.found(zr_task()))
  MCache.set_stamp(row, stamp)
  e
end

# A method cache row for a core library send keys on the name with this
# bit, which no symbol id reaches.
CORE_KEY = 1 << 62

# The entry `e` again on `klass` as `mid`, keeping the name it was
# first defined under and, when `e` was just found by `zr_find_method`
# (`found`), the chain node it came from.
sig [Value, Word, Ptr, Ptr, Word, Bool] => Void
machine def zr_method_copy(klass, mid, e, meta, vis, found)
  orig = MEntry.orig(e)
  from = MEntry.from(e)
  if found && from == QNIL
    from = Task.found(zr_task())
  end
  cover = MEntry.cover(e)
  direct = MEntry.direct(e)
  zr_method_add_vis(klass, mid, MEntry.fn(e), MEntry.arity(e), MEntry.kind(e), meta, MEntry.cref(e), vis)
  e = zr_find_method_at(zr_origin(klass), mid)
  MEntry.set_orig(e, orig)
  MEntry.set_from(e, from)
  # An alias or a visibility copy of a def with a direct entry keeps it.
  MEntry.set_direct(e, direct)
  zr_write_barrier(klass, from)
  # An alias counts where the method it was made from counts, which is
  # what rb_resolve_me_location gives the :call event.
  MEntry.set_cover(e, cover)
end

# `private`, `public`, `protected` and `module_function` as a class
# body's verbs: with no names they set what later defs get, through the
# caller's cref; with names they change those methods on `klass`.
sig [Value, Word, Ptr, Value, Word, Word] => Value
machine def zr_set_visibility(klass, argc, argv, blk, vis, modfn)
  if argc == 0
    cref = Frame.cref(Frame.prev(Task.top(zr_task())))
    if cref == QNIL
      zr_bug(Machine.bytes("a visibility verb outside a class body is not implemented yet\n"), 62)
    end
    if modfn != 0
      RCref.set_modfn(cref, 1)
    else
      RCref.set_vis(cref, vis)
      RCref.set_modfn(cref, 0)
    end
    return Machine.value(QNIL)
  end
  i = 0
  while i < argc
    name = Machine.value(Machine.load64(argv + (i * 8), 0))
    if !zr_special_p(name) && zr_type(name) == T_ARRAY
      r = zr_set_visibility(klass, RArray.len(name), RArray.ptr(name), blk, vis, modfn)
      return r if r == QUNDEF
    else
      slot = Machine.slot(8)
      r = zr_name_id(name, slot)
      return r if r == QUNDEF
      r = zr_set_method_visibility(klass, Machine.load64(slot, 0), vis, modfn)
      return r if r == QUNDEF
    end
    i += 1
  end
  if argc == 1
    return Machine.value(Machine.load64(argv, 0))
  end
  zr_ary_of(argc, argv)
end

sig [Value, Word, Word, Word] => Value
machine def zr_set_method_visibility(klass, mid, vis, modfn)
  frozen = zr_class_modify_check(klass)
  return frozen if frozen == QUNDEF
  e = zr_find_method(klass, mid)
  if e == 0
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("undefined method '"), 18)
    zr_buf_sym(b, mid)
    zr_buf_push(b, zr_type(klass) == T_MODULE ? Machine.bytes("' for module '") : Machine.bytes("' for class '"), zr_type(klass) == T_MODULE ? 14 : 13)
    zr_buf_class(b, klass)
    zr_buf_byte(b, 39)
    return zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end
  if modfn != 0
    single = zr_singleton_class(klass)
    zr_method_copy(single, mid, e, zr_meta_owned(MEntry.meta(e), single), VIS_PUBLIC, false)
    vis = VIS_PRIVATE
  end
  # A verb that finds the method on an ancestor makes a row here, and a
  # new row is a definition: it takes the hook. A verb that changes the
  # row this class already holds takes none.
  copied = zr_find_method_at(zr_origin(klass), mid) != e
  if copied
    zr_method_copy(zr_origin(klass), mid, e, MEntry.meta(e), vis, true)
  else
    MEntry.set_vis(e, vis)
    zr_methods_changed()
    zr_gates_recheck(mid)
  end
  # The hooks run last: one can define a method, which moves the table
  # the entry sits in.
  if modfn != 0
    r = zr_method_added(zr_singleton_class(klass), mid)
    return r if r == QUNDEF
  end
  if copied
    r = zr_method_added(zr_origin(klass), mid)
    return r if r == QUNDEF
  end
  Machine.value(QNIL)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_private(recv, argc, argv, cref, blk)
  zr_set_visibility(recv, argc, argv, blk, VIS_PRIVATE, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public(recv, argc, argv, cref, blk)
  zr_set_visibility(recv, argc, argv, blk, VIS_PUBLIC, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_protected(recv, argc, argv, cref, blk)
  zr_set_visibility(recv, argc, argv, blk, VIS_PROTECTED, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_module_function(recv, argc, argv, cref, blk)
  zr_set_visibility(recv, argc, argv, blk, VIS_PRIVATE, 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_private_class_method(recv, argc, argv, cref, blk)
  zr_set_visibility(zr_singleton_class(recv), argc, argv, blk, VIS_PRIVATE, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public_class_method(recv, argc, argv, cref, blk)
  zr_set_visibility(zr_singleton_class(recv), argc, argv, blk, VIS_PUBLIC, 0)
end

# Whether `e` is a helper the core library keeps for itself (a def
# marked `Primitive.attr! :hidden`), where CRuby has no method at all:
# no list shows it, and `respond_to?` and `method_defined?` deny it. A
# method `define_method` makes carries its caller's meta, so only a
# compiled def or a builtin counts.
sig [Ptr] => Bool
machine def zr_entry_hidden_p(e)
  (MEntry.kind(e) == KIND_DEF || MEntry.kind(e) == KIND_BUILTIN) && MEntry.meta(e) != 0 && FrameMeta.kind(MEntry.meta(e)) == KIND_HIDDEN
end

# The names in one level's table, filtered by `vis` (a visibility, or
# -1 for all but private), into `out`. A name met at an earlier level
# is `seen` and decided there, an undef or a hidden helper among them.
sig [Value, Value, Value, Word] => Void
machine def zr_level_method_names(level, out, seen, vis)
  ext = RClass.ext(level)
  i = 0
  while i < ClassExt.mlen(ext)
    e = ClassExt.mtab(ext) + (i * MEntry.size)
    name = zr_sym(MEntry.mid(e))
    if zr_ary_index_of(seen, name) < 0
      zr_ary_push(seen, name)
      e = zr_find_method_at(level, MEntry.mid(e))
      if MEntry.kind(e) != KIND_UNDEF && !zr_entry_hidden_p(e) && (vis < 0 ? MEntry.vis(e) != VIS_PRIVATE : MEntry.vis(e) == vis)
        zr_ary_push(out, name)
      end
    end
    i += 1
  end
end

# `undefined_instance_methods`: the names this module's own table
# undefined, so a call over them stops at the module.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_undefined_instance_methods(recv, argc, argv, cref, blk)
  ext = RClass.ext(zr_origin(recv))
  out = zr_ary_new(4)
  i = 0
  while i < ClassExt.mlen(ext)
    e = ClassExt.mtab(ext) + (i * MEntry.size)
    if MEntry.kind(e) == KIND_UNDEF && zr_ary_index_of(out, zr_sym(MEntry.mid(e))) < 0
      zr_ary_push(out, zr_sym(MEntry.mid(e)))
    end
    i += 1
  end
  out
end

# `instance_methods` and the three by visibility, on a module (`all`
# for the ancestors too) or, for `methods` on an object, on its class
# chain: the singleton class and the modules it extends come first.
sig [Value, Word, Word, Bool] => Value
machine def zr_method_names(klass, all, vis, object)
  out = zr_ary_new(8)
  seen = zr_ary_new(8)
  k = all == 0 ? zr_origin(klass) : klass
  if object
    while k != QNIL && (zr_singleton_p(k) || zr_type(k) == T_ICLASS)
      zr_level_method_names(k, out, seen, vis)
      k = RClass.superclass(k)
    end
  end
  while k != QNIL
    zr_level_method_names(k, out, seen, vis)
    if all == 0
      k = Machine.value(QNIL)
    else
      k = RClass.superclass(k)
    end
  end
  out
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_instance_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(recv, all ? 1 : 0, 0 - 1, false)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public_instance_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(recv, all ? 1 : 0, VIS_PUBLIC, false)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_private_instance_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(recv, all ? 1 : 0, VIS_PRIVATE, false)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_protected_instance_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(recv, all ? 1 : 0, VIS_PROTECTED, false)
end

sig [Value, Word, Ptr, Word] => Void
machine def zr_builtin(klass, mid, fn, arity)
  zr_define_method(klass, mid, fn, arity, KIND_BUILTIN, 0, Machine.value(QNIL))
end

# `rb_f_notimplement`: the row a call this platform lacks stands in. It
# is listed, reflects as taking no arguments, and `respond_to?` denies
# it; a call raises NotImplementedError naming the function.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_f_notimplement(recv, argc, argv, cref, blk)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_sym(b, zr_frame_mid(Task.top(zr_task())))
  zr_buf_push(b, Machine.bytes("() function is unimplemented on this machine"), 44)
  zr_raise_buf(zr_core_class(Machine.id(:NotImplementedError)), b)
end

# The core's way to give `klass` such a row under `name`, a Symbol.
sig [Value, Value] => Value
machine def zr_define_notimplement(klass, name)
  zr_builtin(klass, zr_sym2id(name), Machine.addr(:zr_f_notimplement), 0 - 1)
  Machine.value(QNIL)
end

# A builtin that is private, as Kernel's `puts` and `raise` are.
sig [Value, Word, Ptr, Word] => Void
machine def zr_builtin_private(klass, mid, fn, arity)
  zr_builtin(klass, mid, fn, arity)
  MEntry.set_vis(zr_find_method_at(zr_origin(klass), mid), VIS_PRIVATE)
  zr_methods_changed()
end

# A private builtin the core library keeps for itself, as a def marked
# `Primitive.attr! :hidden` is kept: no list shows it and no backtrace
# has a row for it.
sig [Value, Word, Ptr, Word] => Void
machine def zr_builtin_hidden(klass, mid, fn, arity)
  zr_builtin_private(klass, mid, fn, arity)
  FrameMeta.set_kind(MEntry.meta(zr_find_method_at(zr_origin(klass), mid)), KIND_HIDDEN)
end

# The entry for `mid` on `klass` alone, or 0; the last definition wins.
# A method table this long or longer is found through a hash index of
# its names, built when a lookup first needs it and dropped when a row
# leaves (const.rb has the same for constants): Kernel's and Object's
# hold hundreds of rows, and every chain walk passes them. A shorter
# table is scanned. A name has one row (a redefinition takes the row it
# had), so a bin holds that row's number plus one, zero when empty.
METHOD_INDEX_MIN = 16

sig [Ptr] => Void
machine def zr_method_index_drop(ext)
  if ClassExt.midx(ext) != 0
    zr_xfree(ClassExt.midx(ext))
    ClassExt.set_midx(ext, 0)
  end
end

sig [Ptr, Word] => Void
machine def zr_method_index_put(ext, row)
  mask = ClassExt.mbins(ext) - 1
  h = (MEntry.mid(ClassExt.mtab(ext) + (row * MEntry.size)) * 2654435761) & mask
  while Machine.load64(ClassExt.midx(ext) + (h * 8), 0) != 0
    h = (h + 1) & mask
  end
  Machine.store64(ClassExt.midx(ext) + (h * 8), 0, row + 1)
end

# Every row into a fresh index with at least four bins a row.
sig [Ptr] => Void
machine def zr_method_index_build(ext)
  zr_method_index_drop(ext)
  n = ClassExt.mlen(ext)
  bins = 64
  while bins < n * 4
    bins = bins * 2
  end
  ClassExt.set_midx(ext, zr_xmalloc(bins * 8))
  memset(ClassExt.midx(ext), Machine.i32(0), bins * 8)
  ClassExt.set_mbins(ext, bins)
  i = 0
  while i < n
    zr_method_index_put(ext, i)
    i += 1
  end
end

# A new last row: into the index while the bins stay under half full,
# else the index goes and the next lookup builds a bigger one.
sig [Ptr, Word] => Void
machine def zr_method_index_add(ext, row)
  if ClassExt.midx(ext) == 0
    return
  end
  if (row + 1) * 2 > ClassExt.mbins(ext)
    zr_method_index_drop(ext)
    return
  end
  zr_method_index_put(ext, row)
end

# The row number of `mid` in the table plus one, or 0.
sig [Ptr, Word] => Word
machine def zr_method_index_find(ext, mid)
  if ClassExt.midx(ext) == 0
    zr_method_index_build(ext)
  end
  mask = ClassExt.mbins(ext) - 1
  h = (mid * 2654435761) & mask
  slot = Machine.load64(ClassExt.midx(ext) + (h * 8), 0)
  while slot != 0
    if MEntry.mid(ClassExt.mtab(ext) + ((slot - 1) * MEntry.size)) == mid
      return slot
    end
    h = (h + 1) & mask
    slot = Machine.load64(ClassExt.midx(ext) + (h * 8), 0)
  end
  0
end

sig [Value, Word] => Ptr
machine def zr_find_method_at(klass, mid)
  ext = RClass.ext(klass)
  n = ClassExt.mlen(ext)
  tab = ClassExt.mtab(ext)
  if n >= METHOD_INDEX_MIN
    slot = zr_method_index_find(ext, mid)
    return slot == 0 ? 0 : tab + ((slot - 1) * MEntry.size)
  end
  i = n - 1
  while i >= 0
    e = tab + (i * MEntry.size)
    if MEntry.mid(e) == mid
      return e
    end
    i -= 1
  end
  0
end

# The answer a walk of the chain gave for one (class, name): the entry
# and the chain node it sat on, and the stamp the answer held under.
Machine.struct :MCache, klass: Value, mid: Word, entry: Ptr, found: Value, stamp: Word
MCACHE_ROWS = 2048
# `ZR_MCACHE=0` answers every send from the walk, and `ZR_MCACHE=verify`
# takes both answers and stops on a disagreement, which is what says no
# change to a method table or a chain moves the stamp too late. Both
# govern the call-site cells too (cache.rb).
MCACHE_OFF = 1
MCACHE_VERIFY = 2

sig [] => Void
machine def zr_mcache_init
  v = getenv(Machine.bytes("ZR_MCACHE\0"))
  if v != 0
    first = Machine.word(Machine.load8(v, 0))
    if first == 48
      Machine.store64(Machine.static(:mcache_mode, 8), 0, MCACHE_OFF)
    elsif first == 118
      Machine.store64(Machine.static(:mcache_mode, 8), 0, MCACHE_VERIFY)
    end
  end
  # A site's own test of its cell never hits in either mode: every send
  # comes through the kernel, which fills no cell or verifies each hit.
  if Machine.load64(Machine.static(:mcache_mode, 8), 0) != 0
    Machine.store64(Machine.static(:site_stamp, 8), 0, 0 - 1)
  end
end

# A definition, an alias, an undef, a visibility change, a module
# spliced into a chain, a class whose superclass is set -- and a
# collection, since a swept class can hand its address to a new one and
# a row names classes by address. A constant lookup walks the same
# chains, so the constant stamp moves too.
sig [] => Void
machine def zr_methods_changed
  s = Machine.static(:mcache_stamp, 8)
  stamp = Machine.load64(s, 0) + 1
  Machine.store64(s, 0, stamp)
  if Machine.load64(Machine.static(:mcache_mode, 8), 0) == 0
    Machine.store64(Machine.static(:site_stamp, 8), 0, stamp)
  end
  zr_consts_changed()
end

# The entry for `mid` on `klass` or an ancestor, or 0; an undef on the
# way is 0 too.
sig [Value, Word] => Ptr
machine def zr_search_method(klass, mid)
  while klass != QNIL
    e = zr_find_method_at(klass, mid)
    if e != 0
      if MEntry.kind(e) == KIND_UNDEF
        return 0
      end
      # The frame the call pushes takes this as where it was defined.
      Task.set_found(zr_task(), klass)
      return e
    end
    klass = RClass.superclass(klass)
  end
  0
end

# The same answer as a walk, from the cache while the cache still holds
# one. Every send comes through here, so the statics are read where they
# are used: a helper for each would cost more than it saves.
sig [Value, Word] => Ptr
machine def zr_find_method(klass, mid)
  # A refinement in use is asked at its own place in the chain, and
  # never from the cache: the cache is keyed by class and name alone.
  if Task.refine(zr_task()) != QNIL
    return zr_refined_search(klass, mid)
  end
  mode = Machine.load64(Machine.static(:mcache_mode, 8), 0)
  if mode == MCACHE_OFF
    return zr_search_method(klass, mid)
  end
  # A cell is CELL_MIN-aligned, so its low bits carry nothing.
  h = ((Machine.word(klass) / CELL_MIN) ^ (mid * 31)) & (MCACHE_ROWS - 1)
  row = Machine.static(:mcache, MCACHE_ROWS * MCache.size) + (h * MCache.size)
  stamp = Machine.load64(Machine.static(:mcache_stamp, 8), 0)
  if MCache.stamp(row) == stamp && MCache.klass(row) == klass && MCache.mid(row) == mid
    e = MCache.entry(row)
    if e != 0
      Task.set_found(zr_task(), MCache.found(row))
    end
    if mode == MCACHE_VERIFY && e != zr_search_method(klass, mid)
      zr_bug(Machine.bytes("the method cache answered what the chain does not\n"), 50)
    end
    return e
  end
  e = zr_search_method(klass, mid)
  MCache.set_klass(row, klass)
  MCache.set_mid(row, mid)
  MCache.set_entry(row, e)
  MCache.set_found(row, e == 0 ? Machine.value(QNIL) : Task.found(zr_task()))
  MCache.set_stamp(row, stamp)
  e
end

# Whether `recv`'s `mid` is still the core library's own row, which
# rb_method_basic_definition_p asks before the C skips a call to it.
sig [Value, Word] => Bool
machine def zr_basic_method_p(recv, mid)
  e = zr_find_method(zr_class_of(recv), mid)
  e != 0 && MEntry.core(e) != 0
end

# The same for the core: `Primitive.zr_basic_method_m(self, :each)`.
sig [Value, Value] => Value
machine def zr_basic_method_m(recv, name)
  zr_bool(zr_basic_method_p(recv, zr_sym2id(name)))
end

sig [Value] => Value
machine def zr_class_of(v)
  # A heap object first, its class in its header: the low three bits
  # of a cell are clear and its address is past every special value,
  # where a fixnum is odd, a flonum ends in 10 and a symbol in 1100.
  if (Machine.word(v) & 7) == 0 && Machine.word(v) > QUNDEF
    return RBasic.klass(v)
  end
  if zr_fixnum_p(v)
    zr_global(G_INTEGER)
  elsif v == QNIL
    zr_global(G_NIL)
  elsif v == QTRUE
    zr_global(G_TRUE)
  elsif v == QFALSE
    zr_global(G_FALSE)
  elsif zr_symbol_p(v)
    zr_global(G_SYMBOL)
  elsif zr_flonum_p(v)
    zr_global(G_FLOAT)
  else
    RBasic.klass(v)
  end
end

# Whether `klass` is `target` or inherits from it, or includes it.
# The classes in a class's chain, the nearest last, and their count:
# `supers[d]` is the ancestor at depth `d`, so a class `c` is an
# ancestor when its rank is at most `klass`'s and `supers[rank(c) - 1]`
# is `c`, one step where a walk takes one per ancestor. Built at the
# first ask from the chain with its proxies skipped. A chain that does
# not reach BasicObject (a class `Class.allocate` made, not yet
# initialized) stays unbuilt, since its superclass is still to come;
# the rank answers 0 for it.
sig [Value] => Word
machine def zr_class_rank(klass)
  ext = RClass.ext(klass)
  if ClassExt.supers(ext) != 0
    return ClassExt.rank(ext)
  end
  n = 0
  top = klass
  k = klass
  while k != QNIL
    if (RBasic.flags(k) & T_MASK) == T_CLASS
      n += 1
      top = k
    end
    k = RClass.superclass(k)
  end
  if top != zr_global(G_BASIC_OBJECT)
    return 0
  end
  s = zr_xmalloc(n * 8)
  i = n
  k = klass
  while k != QNIL
    if (RBasic.flags(k) & T_MASK) == T_CLASS
      i -= 1
      Machine.store64(s + (i * 8), 0, Machine.word(k))
    end
    k = RClass.superclass(k)
  end
  ClassExt.set_supers(ext, s)
  ClassExt.set_rank(ext, n)
  n
end

# Whether `target` is in `klass`'s chain: two classes answer from the
# superclass list, anything else from a walk.
sig [Value, Value] => Bool
machine def zr_class_inherits(klass, target)
  if !zr_special_p(target) && !zr_special_p(klass) && (RBasic.flags(target) & T_MASK) == T_CLASS && (RBasic.flags(klass) & T_MASK) == T_CLASS
    r = zr_class_rank(target)
    n = zr_class_rank(klass)
    if r != 0 && n != 0
      return r <= n && Machine.value(Machine.load64(ClassExt.supers(RClass.ext(klass)) + ((r - 1) * 8), 0)) == target
    end
  end
  zr_chain_includes(klass, target)
end

sig [Value, Value] => Bool
machine def zr_is_a(v, klass)
  k = zr_class_of(v)
  if ClassExt.boxed(RClass.ext(k)) != QNIL
    k = zr_box_view(k)
  end
  if zr_class_inherits(k, klass)
    return true
  end
  # A box shadow stands for the shared class, so what the shared class
  # answers to, the shadow answers to as well.
  o = zr_box_origin(klass)
  o != QNIL && zr_class_inherits(k, o)
end

# A method table's crefs, and the Procs of the methods a block made.
sig [Ptr] => Void
machine def zr_mark_mtab(ext)
  zr_mark_entries(ClassExt.mtab(ext), ClassExt.mlen(ext))
  zr_mark_entries(ClassExt.saved(ext), ClassExt.slen(ext))
end

# What `n` method entries from `tab` hold: a cref or a body, the node
# a copy came from, and a define_method body's own cref.
sig [Ptr, Word] => Void
machine def zr_mark_entries(tab, n)
  i = 0
  while i < n
    zr_mark_entry(tab + (i * MEntry.size))
    i += 1
  end
end

sig [Ptr] => Void
machine def zr_mark_entry(e)
  zr_mark(MEntry.cref(e))
  zr_mark(MEntry.from(e))
  if MEntry.kind(e) == KIND_BMETHOD
    zr_mark(zr_bmethod_cref_kept(e))
  end
end

# What a cell holds besides its class: marked by type, the common
# kinds tested first. A String or a Float holds no Value, and
# zr_mark_cell answers those without queueing them.
sig [Value] => Void
machine def zr_mark_children(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_OBJECT
    zr_mark_ivtab(RObject.iv(v))
  elsif t == T_ARRAY
    zr_mark_ary(v)
  elsif t == T_HASH
    zr_mark_hash(v)
  elsif t == T_STRING || t == T_FLOAT
    return
  elsif t == T_ICLASS
    zr_mark(RClass.superclass(v))
    zr_mark(RClass.attached(v))
    if RClass.origin(RClass.attached(v)) == v
      zr_mark_mtab(RClass.ext(v))
    end
  elsif t == T_CLASS || t == T_MODULE
    zr_mark(RClass.name(v))
    zr_mark(RClass.superclass(v))
    zr_mark(RClass.attached(v))
    ext = RClass.ext(v)
    zr_mark_mtab(ext)
    n = ClassExt.clen(ext)
    i = 0
    while i < n
      zr_mark(CEntry.value(ClassExt.ctab(ext) + (i * CEntry.size)))
      i += 1
    end
    zr_mark_ivtab(ClassExt.iv(ext))
    zr_mark_ivtab(ClassExt.cv(ext))
    zr_mark(ClassExt.refined(ext))
    zr_mark(ClassExt.active(ext))
    zr_mark(ClassExt.boxed(ext))
    zr_mark(ClassExt.shadow(ext))
  elsif t == T_EXCEPTION
    zr_mark(RException.message(v))
    zr_mark(RException.bt(v))
    if RException.cause(v) != QUNDEF
      zr_mark(RException.cause(v))
    end
    zr_mark_backtrace_rows(v)
  elsif t == T_CREF
    zr_mark(RCref.klass(v))
    zr_mark(RCref.lazy(v))
    zr_mark(RCref.next(v))
  elsif t == T_ENV
    zr_mark_env(v)
  elsif t == T_PROC
    zr_mark_proc(v)
  elsif t == T_METHOD
    zr_mark_method(v)
  elsif t == T_FIBER
    zr_mark_fiber(v)
  elsif t == T_REGEXP
    zr_mark_regexp(v)
  end
end

# What a cell owns outside the arena: freed with it.
sig [Value] => Void
machine def zr_release(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_ICLASS || t == T_CLASS || t == T_MODULE
    # A freed class's address can come back as another class: a method
    # cache row keyed on it must not answer for the newcomer.
    zr_methods_changed()
  end
  if t == T_CREF
    # So can a cref's, and a constant cell keys on one.
    zr_consts_changed()
  end
  if t == T_ICLASS
    if RClass.origin(RClass.attached(v)) == v
      if ClassExt.mtab(RClass.ext(v)) != 0
        zr_xfree(ClassExt.mtab(RClass.ext(v)))
      end
      zr_method_index_drop(RClass.ext(v))
      zr_xfree(RClass.ext(v))
    end
  elsif t == T_CLASS || t == T_MODULE
    ext = RClass.ext(v)
    if ClassExt.mtab(ext) != 0
      zr_xfree(ClassExt.mtab(ext))
    end
    if ClassExt.saved(ext) != 0
      zr_xfree(ClassExt.saved(ext))
    end
    if ClassExt.ctab(ext) != 0
      zr_xfree(ClassExt.ctab(ext))
    end
    if ClassExt.supers(ext) != 0
      zr_xfree(ClassExt.supers(ext))
    end
    zr_method_index_drop(ext)
    zr_const_index_drop(ext)
    zr_release_ivtab(ClassExt.iv(ext))
    zr_release_ivtab(ClassExt.cv(ext))
    zr_xfree(ext)
  elsif t == T_STRING
    zr_str_buf_free(v)
  elsif t == T_EXCEPTION
    if RException.rows(v) != 0
      zr_xfree(RException.rows(v))
    end
  elsif t == T_OBJECT
    zr_release_ivtab(RObject.iv(v))
  elsif t == T_ARRAY
    zr_ary_buf_free(v)
  elsif t == T_HASH
    zr_sized_xfree(RHash.entries(v), RHash.cap(v) * HEntry.size)
    zr_sized_xfree(RHash.bins(v), RHash.nbins(v) * 8)
  elsif t == T_FIBER
    zr_release_fiber(v)
  elsif t == T_REGEXP
    zr_release_regexp(v)
  elsif t == T_ENV
    zr_xfree(REnv.slots(v))
  end
end

# `set_temporary_name`: a name a later constant assignment replaces;
# nil clears it. The answer says whether the module had a permanent
# name, which cannot change.
sig [Value, Value] => Value
machine def zr_mod_set_temporary_name(mod, name)
  if RClass.name(mod) != QNIL && (RBasic.flags(mod) & FL_TEMP_NAME) == 0
    return Machine.value(QFALSE)
  end
  RClass.set_name(mod, name)
  if name == QNIL
    RBasic.set_flags(mod, RBasic.flags(mod) & (0 - (FL_TEMP_NAME + 1)))
  else
    RBasic.set_flags(mod, RBasic.flags(mod) | FL_TEMP_NAME)
  end
  Machine.value(QTRUE)
end

# --- refinements -------------------------------------------------------

G_REFINEMENT = 46
# One row per `using` the program holds; a call site names the row that
# covers it.
G_ACTIVATIONS = 47

# The holder module `refine` makes: an ordinary module that remembers
# the class it stands over. Its activation list is `active`, the list
# every refinement of the same module shares, as rb_mod_refine shares
# activated_refinements: a call inside one refine block reaches the
# module's other refinements, the later ones too.
sig [Value, Value] => Value
machine def zr_refinement_new(klass, active)
  h = zr_class_alloc(T_MODULE, Machine.value(QNIL), zr_global(G_REFINEMENT))
  ext = RClass.ext(h)
  ClassExt.set_refined(ext, klass)
  zr_write_barrier(h, klass)
  zr_ary_push(active, h)
  ClassExt.set_active(ext, active)
  zr_write_barrier(h, active)
  h
end

sig [Value] => Value
machine def zr_refined_class(h)
  ClassExt.refined(RClass.ext(h))
end

# Row `id` as it stands now. A row whose `using` a condition skipped
# holds the id of the row before it, which answers in its place; a row
# nothing has touched holds nil.
sig [Value, Word] => Value
machine def zr_activation_row(rows, id)
  if zr_special_p(rows) || id < 0 || id >= RArray.len(rows)
    return Machine.value(QNIL)
  end
  row = zr_ary_at(rows, id)
  while zr_fixnum_p(row)
    from = zr_fix2long(row)
    row = Machine.value(QNIL)
    if from >= 0 && from < RArray.len(rows)
      row = zr_ary_at(rows, from)
    end
  end
  row
end

# The activation list a call site names, which every send under it
# reads.
sig [Word] => Value
machine def zr_activate(id)
  Task.set_refine(zr_task(), zr_activation_row(zr_global(G_ACTIVATIONS), id))
  Machine.value(QNIL)
end

# Inside a `refine` block the refinement being written is in use, so a
# sibling method is reachable by bare name.
sig [Ptr] => Value
machine def zr_activate_owner(rec)
  meta = zr_method_meta_of(rec)
  list = Machine.value(QNIL)
  if meta != 0
    owner = FrameMeta.owner(meta)
    if !zr_special_p(owner) && (zr_type(owner) == T_MODULE || zr_type(owner) == T_CLASS)
      list = ClassExt.active(RClass.ext(owner))
    end
  end
  Task.set_refine(zr_task(), list)
  Machine.value(QNIL)
end

# The table of activation rows, long enough to hold row `id`.
sig [Word] => Value
machine def zr_activation_rows(id)
  rows = zr_global(G_ACTIVATIONS)
  if zr_special_p(rows)
    rows = zr_ary_new(8)
    zr_set_global(G_ACTIVATIONS, rows)
  end
  while RArray.len(rows) <= id
    zr_ary_push(rows, Machine.value(QNIL))
  end
  rows
end

# Every row the program was compiled with, taken before its first line.
# A row is otherwise made where its `using` runs, and one under a
# condition that never holds is never made -- so the table alone would
# not say how far a program's rows reach, and a compile at run time
# would number a row the program already holds.
sig [Word] => Value
machine def zr_activations_reserve(count)
  if count > 0
    zr_activation_rows(count - 1)
  end
  Machine.value(QNIL)
end

# The same, and how many rows stand taken, for the compiler a program
# carries: it numbers a snippet's rows after them, then takes them.
sig [Value] => Value
machine def zr_activations_reserve_m(count)
  zr_activations_reserve(zr_fix2long(count))
end

sig [] => Value
machine def zr_activations_count
  rows = zr_global(G_ACTIVATIONS)
  zr_fix(zr_special_p(rows) ? 0 : RArray.len(rows))
end

# A `using` that a condition holds may never run. Until it does, its
# row stands for row `from`, whatever that row holds when a call reads
# it. A row a `using` already filled keeps its own.
sig [Word, Word] => Value
machine def zr_using_default(id, from)
  rows = zr_activation_rows(id)
  if zr_ary_at(rows, id) == QNIL
    zr_ary_store(rows, id, zr_fix(from))
  end
  Machine.value(QNIL)
end

# `using mod` at row `id`: the rows `from` holds now, then every holder
# `mod` refines. `from` is -1 where nothing was in use.
sig [Word, Value, Word] => Value
machine def zr_using_activate(id, mod, from)
  rows = zr_activation_rows(id)
  list = zr_ary_new(4)
  prior = zr_activation_row(rows, from)
  if prior != QNIL
    zr_ary_splat(list, prior)
  end
  r = zr_using_holders(list, mod)
  return r if r == QUNDEF
  zr_ary_store(rows, id, list)
  Machine.value(QNIL)
end

# Every holder `mod` refines, appended to `list`. `Module#refinements`
# answers them, so a module written in ruby takes part too.
sig [Value, Value] => Value
machine def zr_using_holders(list, mod)
  if zr_special_p(mod) || (zr_type(mod) != T_MODULE && zr_type(mod) != T_CLASS)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
    zr_buf_class_of(b, mod)
    zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  found = zr_send(mod, Machine.id(:refinements), 0, 0)
  return found if found == QUNDEF
  zr_ary_splat(list, found)
end

# The class a row's element stands over, or nil for anything else that
# reached the row: a row is filled from `Module#refinements`, which is
# ruby, and a program may answer it with whatever it likes.
sig [Value] => Value
machine def zr_refined_target(h)
  if zr_special_p(h) || zr_type(h) != T_MODULE
    return Machine.value(QNIL)
  end
  ClassExt.refined(RClass.ext(h))
end

# Whether a holder over `target` stands before `stop` in the row.
sig [Value, Value, Word] => Bool
machine def zr_refined_target_seen_p(list, target, stop)
  i = 0
  while i < stop
    if zr_refined_target(zr_ary_at(list, i)) == target
      return true
    end
    i += 1
  end
  false
end

# `Module.used_refinements`: every refinement in force where the caller
# stands, in the order CRuby answers. Its table is keyed by the refined
# class and holds the head of that class's chain, so its answer is the
# refined classes in the order a `using` first reached them and, down
# each one, the newest refinement first. The activation row is one flat
# list in `using` order, so a walk per distinct target gives both orders
# back.
#
# This is a builtin because a compiled ruby frame starts with no
# refinements in use -- they belong to the call site, not to what the
# site called -- while a builtin's frame keeps the row the site filled.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_used_refinements(recv, argc, argv, cref, blk)
  out = zr_ary_new(4)
  list = Task.refine(zr_task())
  if zr_special_p(list) || zr_type(list) != T_ARRAY
    return out
  end
  n = RArray.len(list)
  i = 0
  while i < n
    target = zr_refined_target(zr_ary_at(list, i))
    if target != QNIL && !zr_refined_target_seen_p(list, target, i)
      k = n - 1
      while k >= 0
        h = zr_ary_at(list, k)
        if zr_refined_target(h) == target
          zr_ary_push(out, h)
        end
        k -= 1
      end
    end
    i += 1
  end
  out
end

# `Module.used_modules`: the module each refinement in use was written
# in, in the same order and without repeats -- a module that refines two
# classes stands in two chains, and CRuby uniqs.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_used_modules(recv, argc, argv, cref, blk)
  found = zr_mod_used_refinements(recv, argc, argv, cref, blk)
  out = zr_ary_new(4)
  i = 0
  while i < RArray.len(found)
    origin = zr_ivar_get(zr_ary_at(found, i), Machine.id(:__origin__))
    if zr_ary_index_of(out, origin) < 0
      zr_ary_push(out, origin)
    end
    i += 1
  end
  out
end

# The walk a lookup makes with refinements in use: at each node of the
# chain, a refinement of that node's class or module answers before
# the node's own table, so a subclass's own method still wins over a
# refinement of its ancestor, as CRuby resolves a refined entry where
# the refined class sits.
sig [Value, Word] => Ptr
machine def zr_refined_search(klass, mid)
  k = klass
  while k != QNIL
    e = zr_refined_entry_at(zr_type(k) == T_ICLASS ? RClass.attached(k) : k, mid)
    if e != 0
      return e
    end
    e = zr_find_method_at(k, mid)
    if e != 0
      if MEntry.kind(e) == KIND_UNDEF
        return 0
      end
      Task.set_found(zr_task(), k)
      return e
    end
    k = RClass.superclass(k)
  end
  0
end

# The entry a refinement in use answers for `mid` on `target` itself,
# newest first, or 0.
sig [Value, Word] => Ptr
machine def zr_refined_entry_at(target, mid)
  list = Task.refine(zr_task())
  if zr_special_p(list) || zr_type(list) != T_ARRAY
    return 0
  end
  i = RArray.len(list) - 1
  while i >= 0
    h = zr_ary_at(list, i)
    if !zr_special_p(h) && zr_type(h) == T_MODULE && ClassExt.refined(RClass.ext(h)) == target
      e = zr_search_method(h, mid)
      if e != 0
        return e
      end
    end
    i -= 1
  end
  0
end

# The refinement the last lookup answered from, or nil. A Method built
# from a refined name is owned by its holder.
sig [] => Value
machine def zr_found_refinement
  f = Task.found(zr_task())
  if !zr_special_p(f) && zr_type(f) == T_MODULE && ClassExt.refined(RClass.ext(f)) != QNIL
    return f
  end
  Machine.value(QNIL)
end
