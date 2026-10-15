# String#setbyte converts the index, then the byte, before it checks the
# index against the length, as rb_str_setbyte does.
def t
  p yield
rescue TypeError, IndexError, RangeError => e
  p [e.class, e.message]
end
t { +"7".setbyte(3, "") }
t { +"7".setbyte("x", "") }
t { +"7".setbyte(3, nil) }
t { +"7".setbyte(3, 2**70) }
t { +"7".setbyte(0, 2**70 + 65) }
t { +"7".setbyte(-1, 66.9) }
t { "7".freeze.setbyte(0, "") }
