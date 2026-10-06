# NameError#local_variables lists the locals of the block where the
# name was not found and of every scope around it, up to the method.
obj = Object.new
def obj.test(a, b = nil, *c, &d)
  e = a
  1.times { |f| g = foo; g }
  e
end
begin
  obj.test(3)
rescue NameError => e
  p e.local_variables.sort
end
