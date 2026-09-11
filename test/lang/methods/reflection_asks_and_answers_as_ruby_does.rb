def try = yield rescue [$!.class, $!.message]

# respond_to? passes include_all on, and lets the hook's error out.
class RM
  def respond_to_missing?(m, all) = (p [:asked, m, all]; m == :ghost)
end
p RM.new.respond_to?(:ghost), RM.new.respond_to?(:ghost, true)
class Boom
  def respond_to_missing?(m, all) = raise("boom")
end
p try { Boom.new.respond_to?(:x) }

# Two define_method bodies are two methods.
class DM
  define_method(:a) { 1 }
  define_method(:b) { 2 }
end
d = DM.new
p d.method(:a) == d.method(:b), d.method(:a) == d.method(:a)

p Object.private_instance_methods.include?(:initialize_dup), Object.private_instance_methods.include?(:initialize_clone)

# Object#=== is identity first.
o = Object.new
def o.==(x) = false
p Object.instance_method(:===).bind_call(o, o)

p try { 1.instance_of?(1) }
p try { Object.include?(1) }

# The top of the chain has no super method.
def dbl(n) = n * 2
p method(:dbl).super_method
p 1.method(:+).super_method

__END__
[:asked, :ghost, false]
[:asked, :ghost, true]
true
true
[RuntimeError, "boom"]
false
true
true
true
true
[TypeError, "class or module required"]
[TypeError, "wrong argument type Integer (expected Module)"]
nil
nil
