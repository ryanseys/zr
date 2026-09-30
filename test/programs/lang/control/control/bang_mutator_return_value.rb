# A successful in-place String mutation returns the receiver, and one that
# changes nothing returns nil. The test prints the receiver and the return
# value together.
a = +"abc"
v = a.sub!("b", "*")
p [a, v]

a = +"abc"
v = a.gsub!("b", "*")
p [a, v]

a = +"abc"
v = a.upcase!
p [a, v]

a = +"abc"
v = a.sub!("b", "*")
p [v, a]

# a mutation that changes nothing still answers nil
a = +"abc"
p [a, a.sub!("z", "*")]
a = +"ABC"
p [a, a.upcase!]
a = +"abc"
p [a.downcase!, a.downcase!]
a = +" x "
p [a.strip!, a.strip!]

# and the non-nil-on-no-change mutators answer the receiver either way
a = +"abc"
p [a.reverse!, a]
