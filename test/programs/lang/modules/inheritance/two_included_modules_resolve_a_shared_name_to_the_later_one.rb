# Top-level `include <Mod>` mixes the module's module_function
# methods into the main scope so bare `<m>` calls dispatch to
# them. CRuby installs them on Object.

module Greeter
  module_function

  def hello(name)
    "hello, " + name + "!"
  end

  def bye
    "bye"
  end
end

include Greeter

# ---
# Multi-include with overlap: a later include shadows the earlier
# alias for the same bare name (CRuby: last-include wins via the
# linearised ancestor chain). Non-overlapping methods from both
# modules stay available.

module First
  module_function

  def shared
    "shared-from-First"
  end

  def only_in_first
    "only-First"
  end
end

module Second
  module_function

  def shared
    "shared-from-Second"
  end

  def only_in_second
    "only-Second"
  end
end

include First
include Second

puts shared           # Second wins
puts only_in_first    # still resolvable via First
puts only_in_second   # newly available via Second

