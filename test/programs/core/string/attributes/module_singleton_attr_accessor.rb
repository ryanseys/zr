# `module M; class << self; attr_accessor :x; end; end` gives the
# module a reader and a writer, also when the value written is not
# a constant. Roundhouse does this with
# `ActiveRecord.adapter = SqliteAdapter.new` (the RHS is a method
# call, not a constant). A read before any write returns nil.

module Cfg
  class << self
    attr_accessor :adapter, :timeout
  end
end

# String RHS (non-constant).
Cfg.adapter = "sqlite"
puts Cfg.adapter

# Int RHS.
Cfg.timeout = 30
puts Cfg.timeout

# Re-assign.
Cfg.adapter = "postgres"
puts Cfg.adapter

# Pre-assignment read is nil.
module Empty
  class << self
    attr_accessor :slot
  end
end
puts Empty.slot.nil?
