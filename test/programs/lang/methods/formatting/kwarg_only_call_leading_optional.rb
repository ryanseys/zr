# The whole-program shape: NO call site anywhere supplies the leading optional
# positionally. The keyword goes to the declared keyword only, and the
# optional keeps its default. A companion call that passes the positional
# would hide a fault here, so each shape has its own example.
class A
  def self.f(a = nil, k: :default)
    "a=#{a.inspect} k=#{k.inspect}"
  end
end
puts A.f(k: 1)
