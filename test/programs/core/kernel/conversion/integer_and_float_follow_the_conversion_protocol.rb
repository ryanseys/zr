# Integer() and Float() follow ruby's rb_convert_to_integer and
# rb_convert_to_float: to_int under rb_protect, then to_str, then to_i,
# each result checked.
def t
  p yield
rescue => e
  p [e.class, e.message]
end

class NilAnswer; def to_int = nil; end
class NilThenToI; def to_int = nil; def to_i = 5; end
class StrAnswer; def to_int = "7"; end
class RaisesThenToI; def to_int = raise("boom"); def to_i = 5; end
class StrConv; def to_str = "12"; end
class ToIString; def to_i = "7"; end
class ToINil; def to_i = nil; end
class FloatNil; def to_f = nil; end
class FloatRaises; def to_f = raise("boom"); end

t { Integer(NilAnswer.new) }
t { Integer(NilThenToI.new) }
t { Integer(StrAnswer.new) }
t { Integer(RaisesThenToI.new) }
t { [Integer(StrConv.new), Integer(StrConv.new, 16)] }
t { Integer(ToIString.new) }
t { Integer(ToINil.new) }
t { Integer(ToIString.new, exception: false) }
t { Integer(Float::NAN, exception: false) }
t { Integer(Float::INFINITY) }
t { Integer(12.9) }
t { Integer(5, 16) }
t { Integer(5, 16, exception: false) }
t { Float(FloatNil.new) }
t { Float(FloatRaises.new, exception: false) }
t { Float(FloatNil.new, exception: false) }

# A throw, a break or a return out of a probed to_int stops at the probe.
class ThrowsToInt
  def to_int = throw(:a, 1)
  def to_i = 7
end
r = catch(:a) do
  p Integer(ThrowsToInt.new)
  :after
end
p r
