# CRuby writes some core methods in Ruby (Kernel#Integer, Array#first),
# so an error that one raises fires :raise at its <internal:...> path and
# line. zr has no such files, and fires no :raise for them.
events = []
TracePoint.new(:raise) { |tp| events << [tp.raised_exception.class, tp.method_id] }.enable do
  Integer("x") rescue nil
  [1, 2].first(-1) rescue nil
end
events.each { p _1 }
