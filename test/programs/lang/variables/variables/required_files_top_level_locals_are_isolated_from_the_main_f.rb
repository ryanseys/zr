# Real Ruby gives every file its own top-level local scope: main's
# `count` and the lib's `count` (mutated through a block, exercising
# the rename pass inside shared-scope block bodies) never touch. The
# lib hands its result out through a global -- the only channel real
# Ruby shares.

require_relative "required_file_locals/main"
