# compile.c's opt_newarray_send: `[a, b].max` on a literal compares each
# element with the best so far, also under `using`. A refinement that
# defines Array#max (or #min) turns that path off for that method, with
# or without a `using`, as it clears CRuby's BOP flag; a refinement of
# Enumerable does not. Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

module Empty; end
using Empty

try("[-0.0, NaN].max") { [-0.0, Float::NAN].max }
try("[1.0, NaN].max") { [1.0, Float::NAN].max }
try("[NaN, 1.0].min") { [Float::NAN, 1.0].min }
try("[1, NaN].max") { [1, Float::NAN].max }
try("[-0.0, NaN].min") { [-0.0, Float::NAN].min }
try("[1.0, NaN].minmax") { [1.0, Float::NAN].minmax }
x = 4
try("[x, 2, 9].max") { [x, 2, 9].max }
try("[x, 2, 9].min") { [x, 2, 9].min }

module OfEnumerable
  refine Enumerable do
    def max = :enumerable
  end
end
try("after an Enumerable refinement") { [1.0, Float::NAN].max }

module OfMin
  refine Array do
    def min = :refined_min
  end
end
# Not in use here: min leaves the literal path, max keeps it.
try("min, refinement not used") { [1.0, Float::NAN].min }
try("max, refinement not used") { [1.0, Float::NAN].max }

using OfMin
try("min, refinement used") { [x, 2].min }
try("max, refinement used") { [x, 2].max }
