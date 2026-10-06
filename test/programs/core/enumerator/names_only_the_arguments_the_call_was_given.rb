# `rb_scan_args` then RETURN_SIZED_ENUMERATOR(obj, argc, argv): what
# an enumerator names is what the caller wrote, so a default that was
# never passed is not one of them.
Trio = Struct.new(:a, :b, :c)
t = Trio.new(1, 2, 3)

p t.cycle.inspect
p t.cycle(2).inspect
p t.min_by.inspect
p t.min_by(2).inspect
p t.max_by.inspect
p t.max_by(2).inspect
