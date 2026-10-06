# Binding#local_variable_set of many new names keeps them in one scope of
# the Binding, so each set stays quick, and the names are locals of the
# Binding.
b = binding
x = 1
20_000.times { |i| b.local_variable_set("n#{i % 2_000}", i) }
b.local_variable_set(:x, 2)
b.local_variable_set(:fresh, 3)
p x, b.local_variable_get(:fresh), b.local_variable_get(:n7), b.local_variable_defined?(:fresh)
p b.local_variables.size, b.eval("fresh + x + n1")
p defined?(fresh)
