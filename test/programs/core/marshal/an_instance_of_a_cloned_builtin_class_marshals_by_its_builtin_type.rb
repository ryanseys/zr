# Marshal writes a String, Array or Hash by its builtin type, which an
# instance of a class cloned from String keeps, though it is no kind of
# String. Its copy loads back equal.
StrClone = String.clone
s = StrClone.new("ab")
p Marshal.dump(s)
copy = Marshal.load(Marshal.dump(s))
p copy, copy == s
