# A proc whose last expression raises (a call to a missing method, or a read
# of a missing constant) raises that error when called.
x = [1, "a"].sample
g = -> { x.no_such_method_here }   # raises NoMethodError
h = -> { NoSuchConst }             # raises NameError
begin
  g.call
rescue Exception => e
  puts e.class
end
begin
  h.call
rescue Exception => e
  puts e.class
end
puts "done"
