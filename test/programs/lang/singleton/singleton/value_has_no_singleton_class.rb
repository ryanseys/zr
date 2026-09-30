def try = (yield; :ok) rescue [$!.class, $!.message]

p try { def (2**64).foo; end }
p try { (2**64).singleton_class }
p try { 1e300.singleton_class }
p try { 1.5.singleton_class }
p try { :sym.singleton_class }
p try { "lit".freeze.singleton_class }
p try { (-"dyn#{2}").singleton_class }

# A def under instance_eval needs the singleton class; anything else
# the block does runs.
p try { 1.instance_eval { def foo1 = 1 } }, 2.respond_to?(:foo1)
p try { (2**64).instance_eval { def foo2 = 1 } }
p try { (2**64).instance_eval { self } }
p try { 1e300.instance_eval { def foo3 = 1 } }

# These have one.
p try { "dyn#{1}".freeze.singleton_class.class }
p try { 1r.singleton_class.class }
p try { nil.singleton_class }
p try { nil.instance_eval { def nil_x = 1 } }, nil.nil_x

