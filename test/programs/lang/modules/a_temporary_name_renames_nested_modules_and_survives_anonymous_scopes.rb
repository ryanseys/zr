# set_temporary_name renames the modules nested in the module, or clears
# their names, and a module with a temporary name keeps it when an
# anonymous module's constant takes it.
m = Module.new
m::N = Module.new
p m::N.name.match?(/\A#<Module:0x\h+>::N\z/)
m.set_temporary_name "m"
p m::N.name
m.set_temporary_name nil
p m::N.name
outer = Module.new
m = Module.new
m.set_temporary_name "m"
outer::M = m
p m.name, m.inspect
outer = Module.new
m = Module.new
outer::A = m
m.set_temporary_name "m"
outer::M = m
p m.name, m.inspect
