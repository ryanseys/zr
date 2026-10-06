# An exception the runtime raised already holds what the runtime put
# in it -- a NoMethodError keeps its name, its receiver and its
# arguments -- so a program's own instance variable is one more than
# the cell was made to hold, and the rows move to the heap.
e = (nil.no_such_method rescue $!)
e.instance_variable_set(:@seen, 1)
p e.instance_variables, e.instance_variable_get(:@seen)

r = (raise "boom" rescue $!)
10.times { |i| r.instance_variable_set(:"@a#{i}", i) }
p r.instance_variables.size, r.instance_variable_get(:@a9), r.message

k = ({}.fetch(:nope) rescue $!)
k.instance_variable_set(:@seen, :yes)
p k.instance_variables, k.key, k.class
