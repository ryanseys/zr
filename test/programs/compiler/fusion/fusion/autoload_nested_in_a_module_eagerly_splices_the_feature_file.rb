# `autoload :Const, "feature"` is treated as a compile-time
# require -- the loader's eager pre-pass splices the feature file (at any
# structural nesting) so the constant is defined; the `autoload` call
# itself is a no-op. Documented divergence from CRuby's laziness (loads at
# the autoload site, not first access), but observationally identical for
# a definitional autoloaded file.

$LOAD_PATH.unshift(File.expand_path("autoload_nested/lib", __dir__))
require_relative "autoload_nested/main"
