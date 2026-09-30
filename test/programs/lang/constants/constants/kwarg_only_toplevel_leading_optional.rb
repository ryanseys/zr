# One shape per file: a companion call that supplies the positional would
# hide the case this checks.
def top(a = nil, k: :default)
  "a=#{a.inspect} k=#{k.inspect}"
end
puts top(k: 1)
