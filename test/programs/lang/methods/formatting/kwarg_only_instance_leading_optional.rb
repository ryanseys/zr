# One shape per example: a companion call that supplies the positional would
# hide a fault here.
class B
  def f(a = nil, k: :default)
    "a=#{a.inspect} k=#{k.inspect}"
  end
end
puts B.new.f(k: 1)
