# A program that evals carries the compiler, which parses with prism.
# The compiler's own prism directories never join the program's
# $LOAD_PATH, before or after the first eval, so the program sees ruby's
# load path.
def zr_or_prism = $LOAD_PATH.grep(%r{prism|/zr/|prism_shim})
p zr_or_prism
eval("1 + 1")
p zr_or_prism
p binding.eval("[1].map { _1 * 2 }")
p zr_or_prism
p $LOADED_FEATURES.grep(/prism_shim/)
