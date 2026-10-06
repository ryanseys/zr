# lineno belongs to a stream that reads, and lineno= takes a C int.
r, w = IO.pipe
p((w.lineno rescue $!), (begin; w.lineno = 3; rescue => e; e; end))
p((begin; r.lineno = "5"; rescue => e; e; end))
r.lineno = 2.7
p r.lineno
p((begin; r.lineno = 2**40; rescue => e; e; end))
