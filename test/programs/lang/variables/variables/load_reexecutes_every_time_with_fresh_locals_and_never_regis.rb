# Three executions: two `load`s plus a `require` -- load never adds to
# the feature table in real Ruby, so the require still fires. `ticks`
# restarts at 0 each execution (fresh local scope per load), which the
# per-splice-instance gensym reproduces.

Dir.chdir(File.expand_path("load_reexecutes", __dir__))
require_relative "load_reexecutes/main"
