# A String, an Array or a Float has no ivar table in its cell, so
# an ivar on one is kept beside its arena, as CRuby keeps a
# generic ivar in a table off to the side. An arena whose cells
# never take one holds no slots at all.
s = "hello"
s.instance_variable_set(:@n, 1)
p s.instance_variable_get(:@n)
p s.instance_variables
p "plain".instance_variables

a = [1, 2]
a.instance_variable_set(:@tag, :short)
b = a.clone
p b.instance_variable_get(:@tag)
b.instance_variable_set(:@tag, :long)
p b.instance_variable_get(:@tag)
p a.instance_variable_get(:@tag)
p a.dup.instance_variables

# Enough of them that more than one arena comes to want its slots,
# and a collection walks what they hold.
kept = []
i = 0
while i < 2000
  x = +"x#{i}"
  x.instance_variable_set(:@n, i)
  kept << x
  i += 1
end
GC.start
total = 0
kept.each { |x| total += x.instance_variable_get(:@n) }
p total
p kept.last.instance_variables
p 1.0.frozen?
f = 2.5
p f.instance_variables
