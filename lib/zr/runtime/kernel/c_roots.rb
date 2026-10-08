module Zr::Kern
  # The roots that C code registers: the addresses of its global VALUE
  # variables (rb_gc_register_address), whose contents the collector reads
  # each time, and objects that it keeps for the life of the program
  # (rb_gc_register_mark_object).

  #: () -> ptr
  def zr_c_root_addresses
    Machine.static(:c_root_addresses, WeakList.size)
  end

  #: () -> ptr
  def zr_c_root_objects
    Machine.static(:c_root_objects, WeakList.size)
  end

  # Marks the Value at each registered address, and each kept object.
  #: () -> void
  def zr_mark_c_roots
    l = zr_c_root_addresses()
    i = 0
    while i < WeakList[l].len
      at = Machine.ptr(Machine.load64(WeakList[l].ptr + (i * 8), 0))
      zr_mark(Machine.value(Machine.load64(at, 0)))
      i += 1
    end
    l = zr_c_root_objects()
    i = 0
    while i < WeakList[l].len
      zr_mark(Machine.value(Machine.load64(WeakList[l].ptr + (i * 8), 0)))
      i += 1
    end
  end

  # Drops the last registration of `at`, if any.
  #: (ptr) -> void
  def zr_c_root_address_drop(at)
    l = zr_c_root_addresses()
    i = WeakList[l].len
    while i > 0
      i -= 1
      if Machine.ptr(Machine.load64(WeakList[l].ptr + (i * 8), 0)) == at
        zr_memmove(WeakList[l].ptr + (i * 8), WeakList[l].ptr + ((i + 1) * 8), (WeakList[l].len - i - 1) * 8)
        WeakList[l].len = WeakList[l].len - 1
        return
      end
    end
  end
end
