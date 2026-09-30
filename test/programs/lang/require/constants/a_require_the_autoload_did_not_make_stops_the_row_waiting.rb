# ruby keeps the row and stops counting it: `check_autoload_required`
# (variable.c:3035) answers 0 once `rb_feature_provided` is true of
# the feature, so `autoload?` answers nil and `const_defined?`
# answers false, whoever loaded the file. The name is still
# declared, so it stands in `constants` and hides the one Object
# now holds.
module Later; end
Later.autoload(:Benchmark, "benchmark")

p Later.autoload?(:Benchmark)
p Later.const_defined?(:Benchmark)

require "benchmark"

p Later.autoload?(:Benchmark)
p Later.const_defined?(:Benchmark)
p Later.constants
begin
  Later::Benchmark
rescue NameError => e
  puts e.message
end

# A row that stopped waiting is still the row a second `autoload`
# of the name replaces, as ruby replaces it: only a name that holds
# a value stands (`autoload_synchronized`, variable.c:2913).
Later.autoload(:Benchmark, "no_such_feature_here")
p Later.autoload?(:Benchmark)
p Later.const_defined?(:Benchmark)
