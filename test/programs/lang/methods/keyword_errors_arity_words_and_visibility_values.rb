# Argument errors, keyword splats and declaration values that answer as
# ruby's do.
def t
  p yield
rescue => e
  p [e.class, e.message]
end

# **true and **false name the value, not its class.
def any(*, **) = :ok
t { any(**true) }
t { any(**false) }
t { any(1, **true) }

# A **nil method refuses keywords before it counts its arguments.
def nokw(a, **nil) = a
t { nokw(**{z: 1}) }
t { nokw(1, **{}) }

# Arity words: fetch takes 1..2; curry counts keywords.
t { [].fetch }
t { Thread.current.fetch }
t { ->(a, k: 1) { a }.curry(2).arity }
t { ->(a, k: 1) { a }.curry(5) }
t { ->(a, b) { a }.curry(3) }

# raise checks its first argument before the cause.
t { raise 1, cause: false }
t { raise nil, cause: nil }
t { raise TypeError, "x", cause: 5 }

# ENV.replace names false as false.
t { ENV.replace(false) }

# private_class_method and public_class_method return the receiver.
class Decl
  def self.s = :s
  def self.r = :r
end
t { Decl.send(:private_class_method, :s) }
t { Decl.send(:public_class_method, :s, :r) }
t { Decl.send(:private_class_method, [:r]) }

# Thread-local keys are Symbols or Strings; a nil value removes the key.
th = Thread.current
t { th[1] }
t { th[1] = 2 }
t { th.key?(nil) }
th[:b] = 1
th[:b] = nil
t { th.key?(:b) }
th.thread_variable_set(:tv, 1)
th.thread_variable_set(:tv, nil)
t { th.thread_variable?(:tv) }
t { th.thread_variable_get(1.5) }

# Binding checks the name it is asked for.
t { binding.local_variable_get(:Foo) }
t { binding.local_variable_get(:@x) }
t { [1].map { binding.local_variable_get(:_1) } }
begin
  binding.local_variable_get(:nope)
rescue NameError => e
  p [e.message.sub(/0x\h+/, "X"), e.name]
end
t { binding.local_variable_set(:_1, 2) }
t { binding.local_variable_defined?(:it) }

# Enumerator::Yielder passes keywords on.
e = Enumerator.new do |y|
  y.yield(1, k: 2)
  y.yield([5, 6], z: 1)
end
e.each { |a, *r, k: 0, **kw| p [a, r, k, kw] }
Enumerator.new { |y| y.yield(1, k: 2) }.each { |a, k: 0| p [a, k] }

# A Method passed as a block takes Hash pairs as two arguments.
def pair(k, v) = "#{k}:#{v}"
t { {a: 1, b: 2}.map(&method(:pair)) }
