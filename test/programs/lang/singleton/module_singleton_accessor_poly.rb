# A module-level singleton accessor gets two or more different
# module/class values. Each read gives the value of the last write.

# 1. Two adapters reassigned — same shape as a Rails-style
#    runtime adapter swap.
module SqliteAdapter
  def self.name; "sqlite"; end
end

module PgAdapter
  def self.name; "postgres"; end
end

module ActiveRecord
  class << self
    attr_accessor :adapter
  end
end

ActiveRecord.adapter = SqliteAdapter
puts ActiveRecord.adapter.name      # sqlite

ActiveRecord.adapter = PgAdapter
puts ActiveRecord.adapter.name      # postgres

ActiveRecord.adapter = SqliteAdapter
puts ActiveRecord.adapter.name      # sqlite

# 2. Three candidates, and a conditional assignment picks which
#    one the accessor holds.
module A
  def self.tag; "A"; end
end
module B
  def self.tag; "B"; end
end
module C
  def self.tag; "C"; end
end

module Pick
  class << self
    attr_accessor :slot
  end
end

[1, 2, 3, 1].each do |n|
  if n == 1
    Pick.slot = A
  elsif n == 2
    Pick.slot = B
  else
    Pick.slot = C
  end
  puts Pick.slot.tag
end
# A B C A
