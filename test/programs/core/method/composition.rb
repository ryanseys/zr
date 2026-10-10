add = proc { |a, b| a + b }
p add.curry.lambda?, add.curry[1][2], add.curry[1, 2], add.curry.(1).(2), add.curry(3)[1][2][3]
l = ->(a, b, c = 0) { a + b + c }
p l.curry[1][2], l.curry(3)[1][2][3], l.curry.arity, l.curry.lambda?
begin; l.curry(1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; l.curry(4); rescue => e; puts "#{e.class}: #{e.message}"; end
v = ->(*a) { a.sum }
p v.curry[1], v.curry(3)[1][2][3], v.curry(0).class
f = ->(x) { x + 1 }
g = ->(x) { x * 2 }
p (f >> g).call(3), (f << g).call(3), (f >> g).lambda?, (proc { |x| x } >> g).lambda?, (f << proc { |x| x }).lambda?
m = 5.method(:+)
p (m >> g).call(1), (m << g).call(1), (m >> g).lambda?, (m >> g).class, (g >> m).call(1)
class Cal; def call(x) = x * 10; end
p (f >> Cal.new).call(1), (f << Cal.new).call(1)
begin; f >> 1; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; f << "x"; rescue => e; puts "#{e.class}: #{e.message}"; end
p f === 1, add === [1, 2]
even = ->(x) { x.even? }
r = case 5 when even then "even" else "odd" end
p r
p f.to_proc.equal?(f)
c = add.curry
p c.arity, c.parameters, c.curry.equal?(c) 
p (f >> g).arity, (f >> g).parameters
p add.curry[1].class
