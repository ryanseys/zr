# TracePoint#path is the code's own path: one frozen String for every
# event of a file, as ruby gives the path of its instruction sequence.
# A C profiler keeps it without marking it (ruby-prof's frames).
def area(w, h)
  w * h
end

paths = []
TracePoint.new(:call, :return, :line, :c_call) { |tp| paths << tp.path }.enable do
  area(2, 3)
  area(4, 5)
end
p paths.size > 4
p paths.map(&:object_id).uniq.size
p paths.all?(&:frozen?)
p File.basename(paths.first)
p paths.first.equal?(__FILE__)
