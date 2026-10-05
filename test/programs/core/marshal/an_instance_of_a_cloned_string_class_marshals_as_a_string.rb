# String.clone makes a class whose instances are still strings, and
# Marshal writes one as a String of that class (test_class.rb's
# test_cloned_class), even when the clone has a subclass.
StrClone = String.clone
Class.new(StrClone)
s = StrClone.new("[ruby-dev:44460]")
p s.class, s
d = Marshal.dump(s)
p d
p Marshal.load(d) == s
