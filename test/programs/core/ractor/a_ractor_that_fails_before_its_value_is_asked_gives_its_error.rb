# A ractor that ends with an error while the main ractor has not yet
# asked for its value: its end is known from then on, also while its
# task still reports the error, so value and join give the error. A
# method's entry is a safe point, and ZR_GVL_STRESS (.env) lets the
# ractor run there.
def value_of(name, ractor)
  p [name, ractor.value]
rescue Ractor::RemoteError => e
  p [name, e.cause.class, e.cause.message]
end

def joined(name, ractor)
  ractor.join
  p [name, :joined]
rescue Ractor::RemoteError => e
  p [name, e.cause.class]
end

value_of(:raises, Ractor.new { raise ArgumentError, "bad" })
value_of(:returns, Ractor.new { :done })
joined(:join_raises, Ractor.new { raise IOError, "closed" })
joined(:join_returns, Ractor.new { 42 })
4.times { |i| value_of(i, Ractor.new(i) { |n| raise "ractor #{n}" if n.odd?; n }) }
