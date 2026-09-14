# The system logger, for syslog_ext (rt/ext/syslog_ext.rb). openlog keeps
# the ident it is given rather than a copy, so the connection keeps one
# of its own until closelog.
Machine.import "openlog", [Ptr, I32, I32] => Void
Machine.import "syslog", [I32, Ptr] => Void
Machine.import "closelog", [] => Void
Machine.import "setlogmask", [I32] => I32

sig [] => Ptr
machine def zr_syslog_ident_slot
  Machine.static(:syslog_ident, 8)
end

sig [Value, Value, Value] => Value
machine def zr_syslog_open(ident, options, facility)
  slot = zr_syslog_ident_slot()
  copy = zr_xmalloc(RString.len(ident) + 1)
  zr_memcpy(copy, RString.ptr(ident), RString.len(ident) + 1)
  Machine.store64(slot, 0, Machine.word(copy))
  openlog(copy, Machine.i32(zr_fix2long(options)), Machine.i32(zr_fix2long(facility)))
  zr_fix(Machine.sword(setlogmask(Machine.i32(0))))
end

sig [] => Value
machine def zr_syslog_close
  slot = zr_syslog_ident_slot()
  closelog()
  free(Machine.ptr(Machine.load64(slot, 0)))
  Machine.store64(slot, 0, 0)
  Machine.value(QNIL)
end

# One message at `priority`, its `%` already doubled: syslog takes the
# text as its format.
sig [Value, Value] => Value
machine def zr_syslog_write(priority, format)
  syslog(Machine.i32(zr_fix2long(priority)), RString.ptr(format))
  Machine.value(QNIL)
end

sig [Value] => Value
machine def zr_syslog_mask(mask)
  zr_fix(Machine.sword(setlogmask(Machine.i32(zr_fix2long(mask)))))
end
