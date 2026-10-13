# Object.constants in any box lists the core's constants (String, Array),
# and a box's list leaves out the constants that the program defined.
# Ruby::Box.master evals as a box of its own, and main evals at the top.
module FooBarA; end
code = "consts = Object.constants\n[consts.include?(:String), consts.include?(:Array)]\n"
p Ruby::Box.current.eval(code), Ruby::Box.root.eval(code), Ruby::Box.master.eval(code)
p Object.constants.include?(:FooBarA), Ruby::Box.root.eval("Object.constants.sort").include?(:FooBarA), Ruby::Box.master.eval("Object.constants.sort").include?(:FooBarA)
b = Ruby::Box.new
p b.eval("Object.constants.include?(:Comparable)"), b.eval("Object.constants.include?(:FooBarA)"), b.eval("Object.constants(false).include?(:Kernel)")
p b.eval("module InBox; end; Object.constants.include?(:InBox)"), Object.constants.include?(:InBox), Ruby::Box.master.inspect
