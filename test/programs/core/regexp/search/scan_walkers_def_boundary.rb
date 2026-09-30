# Locals, params and their types stay inside the method, class or module
# that defines them.
#
# The shape: a top-level module with one def whose local shadows
# an outer name. The two names stay apart, and each call site gets
# the right type.

module Outer
  def self.process(path)
    # `path` is the param; body uses it as a string.
    parts = path.split("/")
    parts.length
  end
end

# Top-level local with the same name as Outer.process's param. The two
# stay apart.
path = "/tmp/db"
puts Outer.process(path)
puts Outer.process("/articles/1")

# Module with a deeper structure: two defs, each with the same
# param name, calling each other.
module Resolver
  def self.outer_resolve(path)
    inner_resolve(path)
  end

  def self.inner_resolve(path)
    path.upcase + ":" + path.length.to_s
  end
end

puts Resolver.outer_resolve("hello")
puts Resolver.outer_resolve("world")
