# Two constant-resolution rules rubygems and bundler lean on all through their
# compatibility shims.
#
# 1. `if defined?(Const)` gates a whole definition. Whether the constant exists
#    is fixed for a whole-program target, so the branch is decided at compile
#    time -- and registration and emission have to decide it the SAME way, or a
#    class reaches codegen with nothing registered behind it.
# 2. A `::`-anchored path names the top level and nothing else, including when
#    the definition it names comes LATER in the flattened program.

# A gate on something the program DOES define: the branch compiles and runs.
# (Asked BEFORE the definition, zr answers "constant" where ruby answers nil --
# a constant's document-order visibility is a separate, pre-existing
# over-approximation, filed as `tests/gaps/issue_defined_before_the_definition.rb`.)
class DefinedBelow; end
if defined?(DefinedBelow)
  class GatedOnReal
    VALUE = 41
    def call = VALUE + 1
  end
end
p GatedOnReal.new.call

