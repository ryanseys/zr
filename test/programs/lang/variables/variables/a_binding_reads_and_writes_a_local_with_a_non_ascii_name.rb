# A local whose name is not ASCII is a local of the Binding, as in ruby.
é = 1
b = binding
p b.local_variable_get(:é)
p b.local_variable_defined?(:é)
b.local_variable_set(:é, 2)
p é
p b.local_variables
p local_variables
def named
  über = :x
  binding.local_variable_get("über")
end
p named
