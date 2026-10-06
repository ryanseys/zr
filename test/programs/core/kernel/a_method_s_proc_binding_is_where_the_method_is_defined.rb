# The binding of a Method's Proc is where the method is defined, and it
# has the method's receiver and no locals.
def source_location_test(a = 1)
  a
end
b = method(:source_location_test).to_proc.binding
file, line = b.source_location
p [File.basename(file), line, b.receiver.equal?(self), b.local_variables]
p method(:puts).to_proc.binding.source_location
