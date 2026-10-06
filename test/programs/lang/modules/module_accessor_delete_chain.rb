# `M.accessor.delete` calls the `delete` class method of the module
# that the accessor holds. The receiver is not a Hash or an Array, so
# this is an ordinary call, with no warning.

module M
  class << self
    attr_accessor :adapter
  end
end

module Backend
  def self.delete
    "ran-delete"
  end
end

M.adapter = Backend
puts M.adapter.delete

# Also exercise statement context (no puts) -- must not crash and
# must not warn.
M.adapter.delete
