# An error that a core method raises fires :raise at the program's line,
# with the method that raised, as a C method's raise does in CRuby. An
# error that the core raises and rescues by itself fires none. Fiber#raise
# fires :raise in the fiber, and again where a fiber that ended with it
# hands it back.
events = []
TracePoint.new(:raise) { |tp| events << [tp.raised_exception.class, tp.lineno, tp.method_id] if tp.path == __FILE__ }.enable do
  [1].fetch(9) rescue nil
  {}.fetch(:a) rescue nil
  [3, 1].sort_by { raise "in block" } rescue nil
  "abc".encode("nope") rescue nil
  loop { raise StopIteration }
  e = [].each
  (e.next rescue nil)
  Encoding.find("utf-8")
end
events.each { p _1 }

main = Fiber.current
f = nil
events = []
TracePoint.new(:raise, :fiber_switch) do |tp|
  events << [tp.event, Fiber.current == main ? :main : (Fiber.current == f ? :f : :other)]
end.enable do
  f = Fiber.new { Fiber.yield; Fiber.yield }
  begin
    f.resume
    f.raise StopIteration
  rescue StopIteration
    events << :rescued
  end
end
events.each { p _1 }
