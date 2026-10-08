module Zr::Kern
  # The C API's Times, made through Time.at.

  # rb_time_new: the local Time `sec` seconds and `usec` microseconds
  # after the epoch.
  #: (word, word) -> value
  def rb_time_new(sec, usec)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_time_at(sec, usec, Machine.id(:usec), Machine.value(QNIL))
  end

  # rb_time_nano_new: the same, with nanoseconds.
  #: (word, word) -> value
  def rb_time_nano_new(sec, nsec)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_time_at(sec, nsec, Machine.id(:nsec), Machine.value(QNIL))
  end

  # The offsets of rb_time_timespec_new that are not a UTC offset.
  TIME_OFFSET_LOCAL = 0x7fffffff
  TIME_OFFSET_UTC = 0x7ffffffe

  # rb_time_timespec_new: the Time of the timespec at `ts`: local for the
  # offset INT_MAX, UTC for INT_MAX - 1, else at `offset` seconds from UTC.
  #: (ptr, i32) -> value
  def rb_time_timespec_new(ts, offset)
    Machine.gates_enter
    zr_c_entered()
    off = Machine.sword(offset)
    zone = Machine.value(QNIL)
    if off == TIME_OFFSET_UTC
      zone = zr_str_new(Machine.bytes("UTC"), 3)
    elsif off != TIME_OFFSET_LOCAL
      zone = zr_fix(off)
    end
    zr_capi_time_at(Machine.load64(ts, 0), Machine.load64(ts, 8), Machine.id(:nsec), zone)
  end

  # `Time.at(sec, sub, unit, in: zone)`, without `in:` for a nil zone.
  #: (word, word, word, value) -> value
  def zr_capi_time_at(sec, sub, unit, zone)
    args = Machine.slot(32)
    Machine.store64(args, 0, Machine.word(zr_fix(sec)))
    Machine.store64(args, 8, Machine.word(zr_fix(sub)))
    Machine.store64(args, 16, Machine.word(zr_sym(unit)))
    if zone == QNIL
      return zr_c_result(zr_send(zr_core_class(Machine.id(:Time)), Machine.id(:at), 3, args))
    end
    kw = zr_hash_new()
    zr_hash_store(kw, zr_sym(Machine.id(:in)), zone)
    Machine.store64(args, 24, Machine.word(kw))
    zr_c_result(zr_capi_send_kw(zr_core_class(Machine.id(:Time)), Machine.id(:at), 4, args))
  end
end
