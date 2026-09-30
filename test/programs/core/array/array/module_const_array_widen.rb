# A module-level array constant initialized as an empty literal
# (`LOG = []`) takes its element type from how the program uses it.
# The module's methods push Hashes with `LOG << v`, also through a
# body local (`entry = {...}; LOG << entry`).
#
# This is the `module Broadcasts; LOG = []; ... LOG << entry`
# pattern of Roundhouse.

module Broadcasts
  module_function
  LOG = []

  def record(action)
    entry = { action: action, target: "x" }
    LOG << entry
  end

  def size
    LOG.length
  end
end

Broadcasts.record(:append)
Broadcasts.record(:replace)
puts Broadcasts.size           # 2
