# A :line hook reads the Binding of the frame the line runs in, which
# holds the locals of a block and of the method around it, even where
# nothing in the block asks for a binding itself.
def outer(a, b = 2)
  [1].map { |x| x + a + b }
end

seen = []
trace = TracePoint.new(:line) { |tp| seen << [tp.lineno, tp.binding.local_variables.sort] }
trace.enable { outer(1) }
seen.each { |row| p row }

