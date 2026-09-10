# The parser ruby itself uses. prism serializes a parse into a buffer of
# bytes and `Prism::Serialize`, which is ordinary ruby, reads them back,
# so the whole native half is four calls.
Machine.import "pm_serialize_parse", [Ptr, Ptr, Word, Ptr] => Void
Machine.import "pm_serialize_parse_comments", [Ptr, Ptr, Word, Ptr] => Void
Machine.import "pm_serialize_lex", [Ptr, Ptr, Word, Ptr] => Void
Machine.import "pm_serialize_parse_lex", [Ptr, Ptr, Word, Ptr] => Void
Machine.import "pm_buffer_init", [Ptr] => I8
Machine.import "pm_buffer_free", [Ptr] => Void
Machine.import "pm_version", [] => Ptr
Machine.import "pm_parse_success_p", [Ptr, Word, Ptr] => I8

# `pm_buffer_t` is a length, a capacity and a pointer, in that order.
BUF_LENGTH = 0
BUF_VALUE = 16
PM_BUFFER_SIZE = 24

# The buffer's bytes as a binary String; the buffer is freed.
sig [Ptr] => Value
machine def zr_pm_take(b)
  out = zr_str_new_at(Machine.ptr(Machine.load64(b, BUF_VALUE)), Machine.load64(b, BUF_LENGTH), ENC_BINARY)
  pm_buffer_free(b)
  out
end

sig [Value, Value] => Value
machine def zr_pm_parse(source, options)
  b = Machine.slot(PM_BUFFER_SIZE)
  pm_buffer_init(b)
  pm_serialize_parse(b, RString.ptr(source), RString.len(source), RString.ptr(options))
  zr_pm_take(b)
end

sig [Value, Value] => Value
machine def zr_pm_parse_comments(source, options)
  b = Machine.slot(PM_BUFFER_SIZE)
  pm_buffer_init(b)
  pm_serialize_parse_comments(b, RString.ptr(source), RString.len(source), RString.ptr(options))
  zr_pm_take(b)
end

sig [Value, Value] => Value
machine def zr_pm_lex(source, options)
  b = Machine.slot(PM_BUFFER_SIZE)
  pm_buffer_init(b)
  pm_serialize_lex(b, RString.ptr(source), RString.len(source), RString.ptr(options))
  zr_pm_take(b)
end

sig [Value, Value] => Value
machine def zr_pm_parse_lex(source, options)
  b = Machine.slot(PM_BUFFER_SIZE)
  pm_buffer_init(b)
  pm_serialize_parse_lex(b, RString.ptr(source), RString.len(source), RString.ptr(options))
  zr_pm_take(b)
end

sig [Value, Value] => Value
machine def zr_pm_parse_success(source, options)
  zr_bool(Machine.word(pm_parse_success_p(RString.ptr(source), RString.len(source), RString.ptr(options))) != 0)
end

sig [] => Value
machine def zr_pm_version
  v = pm_version()
  zr_str_new(v, zr_cstr_len(v))
end
