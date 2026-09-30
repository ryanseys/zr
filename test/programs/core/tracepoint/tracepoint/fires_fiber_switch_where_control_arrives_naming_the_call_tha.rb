# cont.c fires this in the fiber control reached, so the row stands
# where that fiber stands: a fresh one has run no line and names
# nothing. `self` is the thread, which is what th->self is there,
# and the name and the class come from the frame the switch is in,
# as fill_id_and_klass takes them.
rows = []
fs = TracePoint.new(:fiber_switch) do |t|
  rows << [t.self.class.to_s, t.lineno, t.method_id, t.callee_id, t.defined_class.inspect,
           (t.binding ? "Binding" : nil), t.parameters]
end
fs.enable do
  f = Fiber.new { Fiber.yield 1; 2 }
  f.resume
  f.resume
  root = Fiber.current
  g = Fiber.new { root.transfer }
  g.transfer
end
rows.each { |row| p row }
