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

  # rb_time_timespec, rb_time_timeval and rb_time_interval: `time` (a
  # Time, or a number of seconds) as C's struct timespec (seconds and
  # nanoseconds) or struct timeval (seconds and microseconds); an
  # interval is a number that is not negative. The struct comes back in
  # two registers, so a raw stub (Backend::Aarch64::Stub.pair_result) is
  # each C function, and a zr_capi_time_* def fills the struct for it.
  #: (value) -> word
  def rb_time_timespec(time) = Machine.raw

  #: (value) -> word
  def rb_time_timeval(time) = Machine.raw

  #: (value) -> word
  def rb_time_interval(num) = Machine.raw

  #: (value, ptr) -> void
  def zr_capi_time_timespec(time, out)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_time_pair(time, out, false, 1)
  end

  #: (value, ptr) -> void
  def zr_capi_time_timeval(time, out)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_time_pair(time, out, false, 1000)
  end

  #: (value, ptr) -> void
  def zr_capi_time_interval(num, out)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_time_pair(num, out, true, 1000)
  end

  # Fills the two words at `out` with the seconds of `time` and its
  # fraction in units of `per` nanoseconds. A number counts as seconds
  # since the epoch, as ruby takes it; anything else, a Time as an
  # interval and a negative interval are ruby's errors.
  #: (value, ptr, bool, word) -> void
  def zr_capi_time_pair(time, out, interval, per)
    t = time
    if interval || !zr_is_a(time, zr_core_class(Machine.id(:Time)))
      if !zr_is_a(time, zr_global(G_NUMERIC))
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("can't convert "), 14)
        zr_buf_cname(b, time)
        if interval
          zr_buf_push(b, Machine.bytes(" into time interval"), 19)
        else
          zr_buf_push(b, Machine.bytes(" into time"), 10)
        end
        zr_c_result(zr_raise_new(zr_global(G_TYPE_ERROR), zr_buf_take_at(b, ENC_UTF8)))
      end
      if interval && zr_capi_call1(time, Machine.id(:<), zr_fix(0)) == QTRUE
        zr_c_raise(zr_global(G_ARGUMENT_ERROR), Machine.bytes("time interval must not be negative"), 34)
      end
      t = zr_capi_call1(zr_core_class(Machine.id(:Time)), Machine.id(:at), time)
    end
    sec = zr_c_result(zr_send(t, Machine.id(:to_i), 0, Machine.ptr(0)))
    nsec = zr_c_result(zr_send(t, Machine.id(:nsec), 0, Machine.ptr(0)))
    Machine.store64(out, 0, zr_capi_long(sec))
    Machine.store64(out, 8, zr_capi_long(nsec) / per)
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

  # rb_time_utc_offset: Time#utc_offset.
  #: (value) -> value
  def rb_time_utc_offset(time)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(time, Machine.id(:utc_offset), 0, Machine.ptr(0)))
  end
end
