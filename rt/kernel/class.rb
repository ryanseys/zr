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
Machine.struct :ClassExt, mtab: Ptr, mlen: Word, mcap: Word, ctab: Ptr, clen: Word, ccap: Word, iv: IvTab, cv: IvTab, serial: Word, refined: Value, active: Value, boxed: Value, shadow: Value, alloc: Word, cidx: Ptr, cbins: Word
# `orig` is the name the method was first defined under, which an
# alias keeps. `from` is the chain node the entry an alias or a
# visibility change copied was found on, where `super` in the body
# continues from as CRuby's alias and zsuper entries do; nil for a
# definition.
Machine.struct :MEntry, mid: Word, fn: Ptr, arity: Word, kind: Word, meta: Ptr, cref: Value, vis: Word, orig: Word, from: Value
Machine.struct :CEntry, id: Word, value: Value, file: Ptr, file_len: Word, line: Word, private: Word, deprecated: Word, owner: Value
Machine.sig :method, [Value, Word, Ptr, Value, Value] => Value
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
  c = zr_alloc(type, klass)
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
    if k == mod || (zr_type(k) == T_ICLASS && RClass.attached(k) == mod)
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
  ic = zr_alloc(T_ICLASS, mod)
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
    i = 0
    while i < CELLS
      cell = base + (i * CELL)
      flags = Machine.load64(cell, 0)
      if (flags & FL_ALLOCATED) != 0 && (flags & T_MASK) == T_ICLASS
        ic = Machine.value(cell)
        if RClass.attached(ic) == mod && RClass.origin(mod) != ic
          zr_ary_unshift(out, ic)
        end
      end
      i += 1
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
  if zr_frozen_p(base)
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
  if zr_frozen_p(base)
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
  if zr_frozen_p(klass)
    return zr_frozen_error(klass)
  end
  e = zr_find_method(klass, old_id)
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
  if zr_frozen_p(klass)
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
  k = RCref.klass(cref)
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
  v
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
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("wrong argument type Class (expected Module)"), 43)
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
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[])
    GATE_AREF
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[]=)
    GATE_ASET
  elsif (klass == zr_global(G_ARRAY) || klass == zr_global(G_STRING)) && mid == Machine.id(:<<)
    GATE_LTLT
  elsif klass == zr_global(G_STRING) && mid == Machine.id(:freeze)
    GATE_FREEZE
  elsif mid == Machine.id(:!)
    GATE_NOT
  else
    0
  end
end

# The operators compiled code inlines, each as the program found it when
# it started: the class the gate guards (a global's index), the name,
# the gate bit, and the body and visibility that class found then.
Machine.struct :GateRow, klass: Word, mid: Word, bit: Word, fn: Ptr, vis: Word
GATE_ROWS = 20

sig [Word, Word, Word, Word] => Word
machine def zr_gate_row(i, klass, mid, bit)
  row = Machine.static(:gate_rows, GATE_ROWS * GateRow.size) + (i * GateRow.size)
  GateRow.set_klass(row, klass)
  GateRow.set_mid(row, mid)
  GateRow.set_bit(row, bit)
  e = zr_search_method(zr_global(klass), mid)
  if e != 0
    GateRow.set_fn(row, MEntry.fn(e))
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
  i = zr_gate_row(i, G_ARRAY, Machine.id(:<<), GATE_LTLT)
  i = zr_gate_row(i, G_STRING, Machine.id(:<<), GATE_LTLT)
  zr_gate_row(i, G_STRING, Machine.id(:freeze), GATE_FREEZE)
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
  g = zr_gates()
  rows = Machine.static(:gate_rows, GATE_ROWS * GateRow.size)
  i = 0
  while i < GATE_ROWS
    row = rows + (i * GateRow.size)
    if (mid == 0 || GateRow.mid(row) == mid) && (Machine.load64(g, 0) & GateRow.bit(row)) == 0
      e = zr_search_method(zr_global(GateRow.klass(row)), GateRow.mid(row))
      if e == 0 || MEntry.fn(e) != GateRow.fn(row) || MEntry.vis(e) != GateRow.vis(row)
        Machine.store64(g, 0, Machine.load64(g, 0) | GateRow.bit(row))
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
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't define singleton"), 22)
  end
  frozen = zr_class_modify_check(klass)
  return frozen if frozen == QUNDEF
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
  if modfn
    zr_method_add_vis(zr_singleton_class(klass), mid, fn, arity, kind, meta, cref, VIS_PUBLIC)
  end
  zr_method_add_vis(klass, mid, fn, arity, kind, meta, cref, vis)
  # Under `module_function` one def makes two methods, and ruby reports
  # both of them.
  r = zr_method_added(klass, mid)
  return r if r == QUNDEF || !modfn

  zr_method_added(zr_singleton_class(klass), mid)
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

# A method whose body is the Proc `body`, kept in the entry's cref
# slot; `cref` gives the visibility.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_define_bmethod(klass, mid, meta, body, cref)
  klass = zr_origin(klass)
  FrameMeta.set_name(meta, mid)
  FrameMeta.set_owner(meta, klass)
  modfn = cref != QNIL && RCref.modfn(cref) != 0
  if modfn
    zr_method_add_vis(zr_singleton_class(klass), mid, 0, 0 - 1, KIND_BMETHOD, meta, body, VIS_PUBLIC)
  end
  zr_method_add_vis(klass, mid, 0, 0 - 1, KIND_BMETHOD, meta, body, zr_definition_vis(mid, cref))
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
  klass = zr_origin(klass)
  # Only a handful of names have a gate, so ask for the bit before
  # asking the chain whether this is a redefinition.
  bit = zr_gate_bit(klass, mid)
  if bit != 0 && zr_find_method(klass, mid) != 0
    g = zr_gates()
    Machine.store64(g, 0, Machine.load64(g, 0) | bit)
  end
  zr_methods_changed()
  ext = RClass.ext(klass)
  # A redefinition takes the row the name already has, which is where
  # ruby keeps it: `instance_methods` shows it in the place it was first
  # defined, and a later `remove_method` leaves nothing behind.
  e = zr_find_method_at(klass, mid)
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
        free(old)
      end
      ClassExt.set_mtab(ext, tab)
      ClassExt.set_mcap(ext, cap)
    end
    e = ClassExt.mtab(ext) + (n * MEntry.size)
    ClassExt.set_mlen(ext, n + 1)
  end
  MEntry.set_mid(e, mid)
  MEntry.set_fn(e, fn)
  MEntry.set_arity(e, arity)
  MEntry.set_kind(e, kind)
  MEntry.set_meta(e, meta)
  MEntry.set_cref(e, cref)
  MEntry.set_vis(e, vis)
  MEntry.set_orig(e, mid)
  MEntry.set_from(e, Machine.value(QNIL))
  zr_gates_recheck(mid)
end

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
  zr_method_add_vis(klass, mid, MEntry.fn(e), MEntry.arity(e), MEntry.kind(e), meta, MEntry.cref(e), vis)
  e = zr_find_method_at(zr_origin(klass), mid)
  MEntry.set_orig(e, orig)
  MEntry.set_from(e, from)
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
    zr_method_copy(zr_singleton_class(klass), mid, e, MEntry.meta(e), VIS_PUBLIC, false)
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

# The names in one level's table, filtered by `vis` (a visibility, or
# -1 for all but private), into `out`. A name met at an earlier level
# is `seen` and decided there, an undef among them.
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
      if MEntry.kind(e) != KIND_UNDEF && (vis < 0 ? MEntry.vis(e) != VIS_PRIVATE : MEntry.vis(e) == vis)
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
    if all == 0 && zr_type(k) != T_ICLASS
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

# A builtin that is private, as Kernel's `puts` and `raise` are.
sig [Value, Word, Ptr, Word] => Void
machine def zr_builtin_private(klass, mid, fn, arity)
  zr_builtin(klass, mid, fn, arity)
  MEntry.set_vis(zr_find_method_at(zr_origin(klass), mid), VIS_PRIVATE)
  zr_methods_changed()
end

# The entry for `mid` on `klass` alone, or 0; the last definition wins.
sig [Value, Word] => Ptr
machine def zr_find_method_at(klass, mid)
  ext = RClass.ext(klass)
  n = ClassExt.mlen(ext)
  tab = ClassExt.mtab(ext)
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
end

# A definition, an alias, an undef, a visibility change, a module
# spliced into a chain, a class whose superclass is set -- and a
# collection, since a swept class can hand its address to a new one and
# a row names classes by address. A constant lookup walks the same
# chains, so the constant stamp moves too.
sig [] => Void
machine def zr_methods_changed
  s = Machine.static(:mcache_stamp, 8)
  Machine.store64(s, 0, Machine.load64(s, 0) + 1)
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
  # A refinement in use answers first, and never from the cache: the
  # cache is keyed by class and name alone.
  if Task.refine(zr_task()) != QNIL
    e = zr_refined_entry(klass, mid)
    if e != 0
      return e
    end
  end
  mode = Machine.load64(Machine.static(:mcache_mode, 8), 0)
  if mode == MCACHE_OFF
    return zr_search_method(klass, mid)
  end
  # A cell is CELL-aligned, so its low bits carry nothing.
  h = ((Machine.word(klass) / CELL) ^ (mid * 31)) & (MCACHE_ROWS - 1)
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

sig [Value] => Value
machine def zr_class_of(v)
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
sig [Value, Value] => Bool
machine def zr_class_inherits(klass, target)
  zr_chain_includes(klass, target)
end

sig [Value, Value] => Bool
machine def zr_is_a(v, klass)
  k = zr_box_view(zr_class_of(v))
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
  n = ClassExt.mlen(ext)
  i = 0
  while i < n
    zr_mark(MEntry.cref(ClassExt.mtab(ext) + (i * MEntry.size)))
    zr_mark(MEntry.from(ClassExt.mtab(ext) + (i * MEntry.size)))
    i += 1
  end
end

# What a cell holds besides its class: marked by type.
sig [Value] => Void
machine def zr_mark_children(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_ICLASS
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
  elsif t == T_OBJECT
    zr_mark_ivtab(RObject.iv(v))
  elsif t == T_ARRAY
    zr_mark_ary(v)
  elsif t == T_HASH
    zr_mark_hash(v)
  elsif t == T_CREF
    zr_mark(RCref.klass(v))
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
        free(ClassExt.mtab(RClass.ext(v)))
      end
      free(RClass.ext(v))
    end
  elsif t == T_CLASS || t == T_MODULE
    ext = RClass.ext(v)
    if ClassExt.mtab(ext) != 0
      free(ClassExt.mtab(ext))
    end
    if ClassExt.ctab(ext) != 0
      free(ClassExt.ctab(ext))
    end
    zr_const_index_drop(ext)
    zr_release_ivtab(ClassExt.iv(ext))
    zr_release_ivtab(ClassExt.cv(ext))
    free(ext)
  elsif t == T_STRING
    if RString.ptr(v) != 0
      free(RString.ptr(v))
    end
  elsif t == T_EXCEPTION
    if RException.rows(v) != 0
      free(RException.rows(v))
    end
  elsif t == T_OBJECT
    zr_release_ivtab(RObject.iv(v))
  elsif t == T_ARRAY
    free(RArray.base(v))
  elsif t == T_HASH
    if RHash.entries(v) != 0
      free(RHash.entries(v))
    end
    if RHash.bins(v) != 0
      free(RHash.bins(v))
    end
  elsif t == T_FIBER
    zr_release_fiber(v)
  elsif t == T_REGEXP
    zr_release_regexp(v)
  elsif t == T_ENV
    free(REnv.slots(v))
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
# the class it stands over, and carries the activation list it alone
# forms so a call inside its own block costs no allocation.
sig [Value] => Value
machine def zr_refinement_new(klass)
  h = zr_class_alloc(T_MODULE, Machine.value(QNIL), zr_global(G_REFINEMENT))
  ext = RClass.ext(h)
  ClassExt.set_refined(ext, klass)
  a = zr_ary_new(1)
  zr_ary_push(a, h)
  ClassExt.set_active(ext, a)
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

# The entry a refinement in use answers for `mid` on `klass`, newest
# first, or 0.
sig [Value, Word] => Ptr
machine def zr_refined_entry(klass, mid)
  list = Task.refine(zr_task())
  if zr_special_p(list) || zr_type(list) != T_ARRAY
    return 0
  end
  i = RArray.len(list) - 1
  while i >= 0
    h = zr_ary_at(list, i)
    if !zr_special_p(h) && zr_type(h) == T_MODULE && zr_class_inherits(klass, ClassExt.refined(RClass.ext(h)))
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
