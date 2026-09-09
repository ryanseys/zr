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
Machine.struct :ClassExt, mtab: Ptr, mlen: Word, mcap: Word, ctab: Ptr, clen: Word, ccap: Word, iv: IvTab, cv: IvTab, serial: Word
# `orig` is the name the method was first defined under, which an
# alias keeps.
Machine.struct :MEntry, mid: Word, fn: Ptr, arity: Word, kind: Word, meta: Ptr, cref: Value, vis: Word, orig: Word
Machine.struct :CEntry, id: Word, value: Value, file: Ptr, file_len: Word, line: Word, private: Word
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
  ext = malloc(ClassExt.size)
  ClassExt.set_mtab(ext, 0)
  ClassExt.set_mlen(ext, 0)
  ClassExt.set_mcap(ext, 0)
  ClassExt.set_ctab(ext, 0)
  ClassExt.set_clen(ext, 0)
  ClassExt.set_ccap(ext, 0)
  zr_ivtab_init(ClassExt.iv(ext))
  zr_ivtab_init(ClassExt.cv(ext))
  counter = Machine.static(:class_serial, 8)
  Machine.store64(counter, 0, Machine.load64(counter, 0) + 1)
  ClassExt.set_serial(ext, Machine.load64(counter, 0))
  RClass.set_ext(c, ext)
  c
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
  ext = malloc(ClassExt.size)
  zr_memcpy(ext, RClass.ext(klass), ClassExt.size)
  ClassExt.set_ctab(ext, 0)
  ClassExt.set_clen(ext, 0)
  ClassExt.set_ccap(ext, 0)
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
    zr_buf_str(b, zr_class_name_of(base))
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
    zr_buf_str(b, zr_class_name_of(m))
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
    zr_buf_str(b, zr_class_name_of(base))
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

# `alias new old` and `alias_method`: the old entry again under the new
# name, keeping its meta, so a backtrace names the original.
sig [Value, Word, Word] => Value
machine def zr_alias(klass, new_id, old_id)
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
  zr_method_copy(klass, new_id, e, MEntry.meta(e), MEntry.vis(e))
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
sig [Value, Word] => Value
machine def zr_undef(klass, id)
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
  RBasic.set_flags(meta, RBasic.flags(meta) | FL_SINGLETON)
  RClass.set_attached(meta, klass)
  RBasic.set_klass(klass, meta)
  meta
end

# The singleton class of `v`, made on first use. An Integer, a Float or
# a Symbol has none; nil, true and false answer their own class.
sig [Value] => Value
machine def zr_singleton_class(v)
  if zr_special_p(v) && v != QNIL && v != QTRUE && v != QFALSE
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
  RBasic.set_flags(s, RBasic.flags(s) | FL_SINGLETON)
  RClass.set_attached(s, v)
  RBasic.set_klass(v, s)
  s
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

sig [Value] => Value
machine def zr_class_name_of(v)
  RClass.name(zr_real_class(v))
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
    else
      0
    end
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[])
    GATE_AREF
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[]=)
    GATE_ASET
  elsif (klass == zr_global(G_ARRAY) || klass == zr_global(G_STRING)) && mid == Machine.id(:<<)
    GATE_LTLT
  elsif mid == Machine.id(:!)
    GATE_NOT
  else
    0
  end
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
  klass = zr_origin(klass)
  if zr_frozen_p(klass)
    return zr_frozen_error(klass)
  end
  if meta == 0
    meta = malloc(FrameMeta.size)
    FrameMeta.set_file(meta, 0)
    FrameMeta.set_file_len(meta, 0)
    FrameMeta.set_kind(meta, KIND_BUILTIN)
    FrameMeta.set_line(meta, 0)
    FrameMeta.set_parent(meta, 0)
    FrameMeta.set_arity(meta, arity)
    FrameMeta.set_params(meta, 0)
    FrameMeta.set_fn(meta, 0)
  elsif Machine.word(FrameMeta.owner(meta)) != 0 && FrameMeta.owner(meta) != klass
    # The same def run under another class (a class body in a block
    # that runs twice) gets a meta of its own, so each keeps its owner.
    copy = malloc(FrameMeta.size)
    zr_memcpy(copy, meta, FrameMeta.size)
    meta = copy
  end
  FrameMeta.set_name(meta, mid)
  FrameMeta.set_owner(meta, klass)
  if cref != QNIL && RCref.modfn(cref) != 0
    zr_method_add_vis(zr_singleton_class(klass), mid, fn, arity, kind, meta, cref, VIS_PUBLIC)
  end
  zr_method_add_vis(klass, mid, fn, arity, kind, meta, cref, vis)
  zr_method_added(klass, mid)
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
  zr_method_add_vis(klass, mid, 0, 0 - 1, KIND_BMETHOD, meta, body, zr_definition_vis(mid, cref))
  zr_method_added(klass, mid)
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
  if zr_find_method(klass, mid) != 0
    g = zr_gates()
    Machine.store64(g, 0, Machine.load64(g, 0) | zr_gate_bit(klass, mid))
  end
  ext = RClass.ext(klass)
  n = ClassExt.mlen(ext)
  if n == ClassExt.mcap(ext)
    cap = n * 2
    if cap < 8
      cap = 8
    end
    tab = malloc(cap * MEntry.size)
    old = ClassExt.mtab(ext)
    if old != 0
      zr_memcpy(tab, old, n * MEntry.size)
      free(old)
    end
    ClassExt.set_mtab(ext, tab)
    ClassExt.set_mcap(ext, cap)
  end
  e = ClassExt.mtab(ext) + (n * MEntry.size)
  MEntry.set_mid(e, mid)
  MEntry.set_fn(e, fn)
  MEntry.set_arity(e, arity)
  MEntry.set_kind(e, kind)
  MEntry.set_meta(e, meta)
  MEntry.set_cref(e, cref)
  MEntry.set_vis(e, vis)
  MEntry.set_orig(e, mid)
  ClassExt.set_mlen(ext, n + 1)
end

# The entry `e` again on `klass` as `mid`, keeping the name it was
# first defined under.
sig [Value, Word, Ptr, Ptr, Word] => Void
machine def zr_method_copy(klass, mid, e, meta, vis)
  orig = MEntry.orig(e)
  zr_method_add_vis(klass, mid, MEntry.fn(e), MEntry.arity(e), MEntry.kind(e), meta, MEntry.cref(e), vis)
  MEntry.set_orig(zr_find_method_at(zr_origin(klass), mid), orig)
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
    zr_method_copy(zr_singleton_class(klass), mid, e, MEntry.meta(e), VIS_PUBLIC)
    vis = VIS_PRIVATE
  end
  if zr_find_method_at(zr_origin(klass), mid) == e
    MEntry.set_vis(e, vis)
  else
    zr_method_copy(zr_origin(klass), mid, e, MEntry.meta(e), vis)
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

# The entry for `mid` on `klass` or an ancestor, or 0; an undef on the
# way is 0 too.
sig [Value, Word] => Ptr
machine def zr_find_method(klass, mid)
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
  zr_class_inherits(zr_class_of(v), klass)
end

# A method table's crefs, and the Procs of the methods a block made.
sig [Ptr] => Void
machine def zr_mark_mtab(ext)
  n = ClassExt.mlen(ext)
  i = 0
  while i < n
    zr_mark(MEntry.cref(ClassExt.mtab(ext) + (i * MEntry.size)))
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
    free(RArray.ptr(v))
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
