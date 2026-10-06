# A symbol that names TracePoint arms the trace events. With eval, prism
# is in eval support too, and both must still load whole.
require "prism"
names = %i[TracePoint]
p names.size
p eval("1 + 1")
p Prism.parse("a = 1").value.statements.body.size
