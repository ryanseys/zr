# Instance variables on a STRING survive a Marshal round-trip (the I
# prefix carries them), as the ivars of an object do.
s = +"payload"
s.instance_variable_set(:@tag, :iv)
r = Marshal.load(Marshal.dump(s))
p r
p r.instance_variable_get(:@tag)
