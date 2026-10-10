# catch and throw: matching by identity, through methods and
# ensure clauses, past rescue clauses, and the uncaught error.
def deep(tag)
  yield
  throw tag, :from_deep
end

r = catch(:done) do
  deep(:done) { puts "in block" }
  :not_reached
end
p r
p catch(:a) { throw :a }
p catch(:a) { 42 }
p catch { |tag| throw tag, [tag.class] }
p catch(:outer) { catch(:inner) { throw :outer, 1 }; 2 }
p catch(:x) { begin; throw :x, 3; ensure; puts "ensure ran"; end }
p catch(:x) { begin; throw :x, 4; rescue => e; puts "rescued?"; end }
p catch(:x) { begin; throw :x, 5; rescue Exception; puts "rescued?"; end }
begin
  throw :nope, 7
rescue UncaughtThrowError => e
  p e.class, e.message, e.tag, e.value, e.class.superclass
end
begin
  catch("s") { throw "s" }
rescue UncaughtThrowError => e
  puts e.message
end
o = Object.new
p catch(o) { throw o, :ok }
begin
  catch(:a) { raise "boom" }
rescue => e
  puts e.backtrace
end
begin
  throw
rescue ArgumentError => e
  puts e.message
end
p catch(:z) { [1, 2, 3].each { |i| throw :z, i * 10 if i == 2 } }
def m = catch(:m) { return :returned }
p m
p catch(:loop) { loop { throw :loop, :broke } }
p Kernel.private_instance_methods.include?(:catch), Kernel.private_instance_methods.include?(:throw), Kernel.private_instance_methods.include?(:Integer), Kernel.public_instance_methods.include?(:tap)
