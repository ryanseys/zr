# THE keystone parity test: `.ancestors` for every core class, byte-
# identical to real ruby. (Mutex/Queue excluded: real Ruby names them
# `Thread::Mutex`/`Thread::Queue` -- a documented naming divergence.)

[BasicObject, Object, Kernel, Comparable, Enumerable,
 Numeric, Integer, Float, Rational, Complex,
 String, Symbol, Array, Hash, Range,
 NilClass, TrueClass, FalseClass,
 Proc, Regexp, MatchData, Struct, Enumerator,
 Class, Module, Math, Fiber, Thread, Ractor].each do |c|
  puts "#{c}: #{c.ancestors.inspect}"
end
