# Hash#to_h is the identity, so a BOXED receiver keeps the variant it really
# holds. A String-keyed hash from a defaulted parameter keeps String keys.
# An array of pairs keeps its keys when they are not Symbols.
def tag(name, opts = {})
  merged = { "name" => name }.merge(opts.to_h)
  merged.map { |k, v| "#{k}=#{v}" }.join(" ")
end
p tag("a")
p tag("b", { "x" => "1" })
p tag("c", { y: 2 })

def norm(v)
  v.to_h
end
p norm({ "s" => 1 })
p norm({ s: 1 })
p norm(nil)
p norm([[1, 2]])
p({ "a" => 1 }.to_h)
p({ a: 1 }.to_h)
