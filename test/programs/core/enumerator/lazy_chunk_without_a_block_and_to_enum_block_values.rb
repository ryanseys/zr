# Lazy#chunk without a block is a lazy whose `each` chunks by the block
# it is given, because Lazy#to_enum passes the block's value back.
o = Object.new
def o.each
  yield
  yield 1
  yield 1, 2
  yield nil
  yield []
end
o.extend Enumerable
c = o.lazy.chunk
p c.class
p c.each { |v| true }.force

l = (1..3).lazy
p l.chunk { |v| true }.force
e = l.to_enum(:chunk)
p e.each { |v| v.odd? }.force
p l.to_enum(:map).each { |v| v * 2 }
p l.to_enum(:select).each { |v| v > 1 }
