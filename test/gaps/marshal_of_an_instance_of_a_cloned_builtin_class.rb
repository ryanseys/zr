# Marshal reads a String, Array or Hash by its builtin type, which an
# instance of a class cloned from String keeps. zr's Marshal decides by
# class, so it dumps such an instance as a plain object.
StrClone = String.clone
s = StrClone.new("ab")
p Marshal.dump(s)
copy = Marshal.load(Marshal.dump(s))
p copy, copy == s
