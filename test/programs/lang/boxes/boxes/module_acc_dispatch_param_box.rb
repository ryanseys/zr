# `Mod.accessor.method(args)`: a module-singleton accessor returns a
# module, and a call on it takes args of different types at different
# call sites.
#
# The shape comes from Roundhouse's `ActiveRecord.adapter.update(table,
# @id, attrs)`, where `@id` can be an Integer or a String.

module Backend
  class << self
    attr_accessor :db
  end
end

module Storage
  module_function
  def fetch(id)
    # Just round-trip the id through to_s + length so the
    # method body works for both int and String inputs.
    id.to_s.length
  end
end

Backend.db = Storage

# Two call sites with different types.
puts Backend.db.fetch(42)          # 2
puts Backend.db.fetch("alpha")     # 5
