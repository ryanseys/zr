# Reflection agrees with dispatch. A name the box defined must not appear
# in main's `singleton_methods`, which reads a name set with no box axis of
# its own.

b = Ruby::Box.new
b.eval("class Array; def self.zzz = 1; end")
p Array.singleton_methods(false).include?(:zzz)
p b.eval("Array.singleton_methods(false).include?(:zzz)")
