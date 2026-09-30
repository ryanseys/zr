# Comparable's operators call `<=>` through a helper that takes both
# sides, so one bound to any object reports the comparison that failed.
p (Comparable.instance_method(:<).bind_call(Object.new, 1) rescue $!)
p (Comparable.instance_method(:between?).bind_call(Object.new, 1, 2) rescue $!)
p Comparable.private_instance_methods(false), Comparable.singleton_methods
