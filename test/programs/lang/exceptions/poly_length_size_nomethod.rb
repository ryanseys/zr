# `length` / `size` on a receiver that has neither (nil, a number, a user
# object) raises NoMethodError, as in CRuby. A nil read out of a hash miss
# is one such receiver.
def probe(v)
  begin
    v.length
  rescue NoMethodError => e
    "raise: #{e.message}"
  end
end
p probe(nil)
p probe("abc")
p probe([1, 2])
p probe({ a: 1 })
p probe(5)
p probe(:sym)
def psize(v)
  begin
    v.size
  rescue NoMethodError => e
    "raise: #{e.message}"
  end
end
p psize(nil)
p psize(5)
p psize("abc")
p psize([1, 2])
