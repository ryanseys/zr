# A bang mutator on a String read out of a container answers the receiver on a
# change and nil on none. The String is a shared handle, so the "did it
# change?" test must not compare the new text against itself.
h = { a: +"abc" }
s = h[:a]
p s.sub!("b", "*")
p h
p s

h2 = { a: +"abc" }
t = h2[:a]
p t.sub!("z", "*")
p h2

h3 = { a: +"abc" }
u = h3[:a]
p u.gsub!("b", "*")
p u.upcase!
p u.upcase!
p u.swapcase!
p u.reverse!
p h3

a = [+"abc"]
v = a[0]
p v.sub!("b", "*")
p a

# a plain local, which already worked
w = +"abc"
p w.sub!("b", "*")
p w.sub!("z", "*")

# strip!/squeeze!/chomp! answer nil when they change nothing
x = { a: +"  pad  " }[:a]
p x.strip!
p x.strip!
