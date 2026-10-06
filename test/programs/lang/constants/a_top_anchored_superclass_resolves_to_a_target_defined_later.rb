# Two constant-resolution rules rubygems and bundler lean on all through their
# compatibility shims.
#
# 1. `if defined?(Const)` gates a whole definition. Whether the constant exists
#    is fixed for a whole-program target, so the branch is decided at compile
#    time -- and registration and emission have to decide it the SAME way, or a
#    class reaches codegen with nothing registered behind it.
# 2. A `::`-anchored path names the top level and nothing else, including when
#    the definition it names comes LATER in the flattened program.

# A top-anchored superclass whose target is defined later in the program.
module Pkg
  module Timeout
    class Error < RuntimeError; end
  end
end

module Pkg
  module Net
    # Resolved against the top level, skipping the `Pkg::Net` cref -- a bare
    # `Timeout::Error` here would find `Pkg::Timeout::Error` too, but the
    # anchored spelling must not depend on that coincidence.
    class OpenTimeout < ::Pkg::Timeout::Error; end
  end
end

class Elsewhere
  class TimeoutError < ::Pkg::Timeout::Error; end
end

p Pkg::Net::OpenTimeout.ancestors[0, 3]
p Elsewhere::TimeoutError.ancestors[0, 3]
begin
  raise Elsewhere::TimeoutError, "timed out"
rescue Pkg::Timeout::Error => e
  p [e.class, e.message]
end

