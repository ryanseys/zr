# CRuby writes some core methods in Ruby (Kernel#Integer, Array#first), so
# an error that one raises fires :raise at its <internal:...> path, at the
# line of the Primitive that raised. A call of only the mandatory
# arguments runs the body that CRuby compiles for it alone, which has a
# line of its own.
events = []
TracePoint.new(:raise) do |tp|
  events << [tp.raised_exception.class, tp.path, tp.lineno, tp.method_id, tp.defined_class]
end.enable do
  Integer("x") rescue nil
  Integer(nil) rescue nil
  Integer("z", 16) rescue nil
  Integer("1", exception: 3) rescue nil
  Float("x") rescue nil
  Float("x", exception: true) rescue nil
  [1, 2].first(-1) rescue nil
  [1, 2].first("a") rescue nil
  [1, 2].last(-1) rescue nil
  [1].sample(-1) rescue nil
  "x".unpack("Z*Z", offset: 9) rescue nil
  [1].pack("U", buffer: 1) rescue nil
  warn("x", uplevel: -1) rescue nil
end
events.each { p _1 }

# A raise in a block that such a method yields to is the block's, and the
# method fires no second one as the error passes through it.
events = []
TracePoint.new(:raise) { |tp| events << [tp.path == __FILE__, tp.lineno, tp.method_id] }.enable do
  1.times { raise "in times" } rescue nil
  1.then { raise "in then" } rescue nil
  loop { raise StopIteration }
  [1].each { raise "in each" } rescue nil
end
events.each { p _1 }

# A method that rescues its own error fires the :raise of the error, and
# the :raise of the one it raises next.
def converted(s)
  Integer(s)
rescue ArgumentError
  raise TypeError, "not a number"
end

events = []
TracePoint.new(:raise) { |tp| events << [tp.raised_exception.class, File.basename(tp.path), tp.lineno, tp.method_id] }.enable do
  converted("x") rescue nil
end
events.each { p _1 }

# With :call and :return on, the :raise comes between them.
events = []
TracePoint.new(:call, :return, :raise) { |tp| events << [tp.event, tp.lineno, tp.method_id] if tp.path.start_with?("<internal:") }.enable do
  Integer("x") rescue nil
end
events.each { p _1 }
