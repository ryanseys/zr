# `ancestors` (and its Module neighbours) work on a class that a block gets
# from an Array of classes, not only on a constant. Calls chained on the
# result work too.
class A; end
class B; end
module M; end
class C
  include M
end

[A, B].each do |klass|
  p klass.ancestors.map { |m| m.name.to_s }
end

[A, C].each do |klass|
  p klass.ancestors
  p klass.superclass
  p klass.included_modules
  p klass.ancestors.length
  p klass.ancestors.take_while { |m| true }.size
end

# the constant receiver keeps answering the same thing
p A.ancestors
p A.superclass
p C.included_modules
p A.ancestors.map { |m| m.name }

# and a class reached through a local or a hash value is the same boxed value
k = [A].first
p k.ancestors
h = { a: A }
p h[:a].superclass
