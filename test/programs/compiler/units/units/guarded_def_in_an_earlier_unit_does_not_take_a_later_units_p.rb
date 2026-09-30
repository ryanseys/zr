# The failing shape ACROSS FILES, which is how bundler and rubygems meet:
# the guarded reopen is a unit walked before the unit holding the real
# bodies.

$LOAD_PATH.unshift(File.expand_path("guarded_def_unit", __dir__))
require_relative "guarded_def_unit/main"
