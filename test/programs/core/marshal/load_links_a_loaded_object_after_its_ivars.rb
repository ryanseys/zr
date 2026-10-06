# Marshal.load: what `_load` builds takes its link index after the
# ivars of its payload, so a Time with a zone name dumped twice loads
# as one object, and a Regexp with ivars links as before.
t = Time.now
a, b = Marshal.load(Marshal.dump([t, t]))
p a.equal?(b), a == t
r = /ab/
x, y = Marshal.load(Marshal.dump([r, r, "ü"]))
p x.equal?(y), x
