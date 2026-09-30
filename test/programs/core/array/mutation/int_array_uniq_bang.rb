# Array#uniq! on an Integer Array removes the duplicates in place.
# (CRuby returns self when something was removed and nil otherwise.
# This test prints the receiver, not the return value.)
a = [1, 2, 2, 3, 3, 3]
a.uniq!
puts a.inspect

b = [1, 2, 3]
b.uniq!
puts b.inspect

c = []
c.uniq!
puts c.inspect
