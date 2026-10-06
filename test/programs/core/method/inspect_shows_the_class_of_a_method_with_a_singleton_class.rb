m = 1.method(:+)
def m.extra = nil
p m
p m.singleton_class == m.class
p m.class

u = Integer.instance_method(:+)
def u.extra = nil
p u

s = (+"x").method(:upcase)
s.singleton_class.define_method(:note) { :noted }
p [s, s.note]

# A Hash's Proc is C level, so it has no binding.
[{ a: 1 }.to_proc, Hash.new { 1 }.to_proc].each do |pr|
  pr.binding
rescue ArgumentError => e
  p e.message
end
p({ a: 1 }.to_proc.call(:a))
p [{ a: 1 }.to_proc.arity, { a: 1 }.to_proc.lambda?, { a: 1 }.to_proc.source_location]
