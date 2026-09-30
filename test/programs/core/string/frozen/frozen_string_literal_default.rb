# With no magic comment in this file, a literal is not frozen, as in CRuby:
# `<<` on it works. +"" / String.new / interpolation give mutable strings, and
# a change is seen through every reference.
p "lit".frozen?
s = "m"
begin
  s << "!"
  puts "BUG: no raise"
rescue FrozenError => e
  puts e.message
end

m = +"base"
t = m
m << "!"
p t
p m.equal?(t)

n = String.new("n")
arr = [n]
n.upcase!
p arr[0]

who = "world"
i = "hello #{who}"
i << "!"
p i
