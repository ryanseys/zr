# Two constant-resolution rules rubygems and bundler lean on all through their
# compatibility shims.
#
# 1. `if defined?(Const)` gates a whole definition. Whether the constant exists
#    is fixed for a whole-program target, so the branch is decided at compile
#    time -- and registration and emission have to decide it the SAME way, or a
#    class reaches codegen with nothing registered behind it.
# 2. A `::`-anchored path names the top level and nothing else, including when
#    the definition it names comes LATER in the flattened program.

# The same gate written against a nested path, and against a plain constant
# assignment rather than a class.
module Outer
  module Inner; end
end
p defined?(Outer::Inner)
p defined?(Outer::Nope)
p defined?(NEVER_ASSIGNED)

