# CRuby registers a feature as loading BEFORE executing it, so the
# inner require of an in-progress file is a no-op and execution order
# is ca-start, all of cb, ca-end -- the dedup-before-lowering rule
# reproduces this exactly.

require_relative "circular_requires/main"
