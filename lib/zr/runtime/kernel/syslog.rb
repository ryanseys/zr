module Zr::Kern
  # The system logger, for syslog_ext (lib/zr/runtime/ext/syslog_ext.rb). openlog
  # keeps a pointer to its ident, not a copy. Thus the connection keeps
  # its own copy of the ident until closelog.

  #: () -> ptr
  def zr_syslog_ident_slot
    Machine.static(:syslog_ident, 8)
  end

  #: (value, value, value) -> value
  def zr_syslog_open(ident, options, facility)
    slot = zr_syslog_ident_slot()
    copy = zr_xmalloc(RString[ident].len + 1)
    zr_memcpy(copy, RString[ident].ptr, RString[ident].len + 1)
    Machine.store64(slot, 0, Machine.word(copy))
    Libc.openlog(copy, Machine.i32(zr_fix2long(options)), Machine.i32(zr_fix2long(facility)))
    zr_fix(Machine.sword(Libc.setlogmask(Machine.i32(0))))
  end

  #: () -> value
  def zr_syslog_close
    slot = zr_syslog_ident_slot()
    Libc.closelog()
    zr_xfree(Machine.ptr(Machine.load64(slot, 0)))
    Machine.store64(slot, 0, 0)
    Machine.value(QNIL)
  end

  # Logs one message at `priority`. The caller doubles each `%` first,
  # because syslog uses the text as its format.
  #: (value, value) -> value
  def zr_syslog_write(priority, format)
    Libc.syslog(Machine.i32(zr_fix2long(priority)), RString[format].ptr)
    Machine.value(QNIL)
  end

  #: (value) -> value
  def zr_syslog_mask(mask)
    zr_fix(Machine.sword(Libc.setlogmask(Machine.i32(zr_fix2long(mask)))))
  end
end
