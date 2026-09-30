# The top-level uncaught-raise contract (message on stderr, exit 1) must
# survive the main body's Result crossing back to the OS main thread.

raise "through the boundary"
