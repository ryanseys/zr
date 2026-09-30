# A module value assigned to a module-level
# `class << self; attr_accessor :x; end` accessor reads back as that
# module, and a call on the result reaches the module's own method.
# Each accessor here gets one assignment.

# 1. Module assigned to a module-level singleton accessor.
module SqliteAdapter
  def self.answer
    42
  end
end

module ActiveRecord
  class << self
    attr_accessor :adapter
  end
end

ActiveRecord.adapter = SqliteAdapter
puts ActiveRecord.adapter.answer    # 42

# 2. A method on the stored module that returns a String. The
#    call through the accessor gives the String.
module Greeter
  def self.greet
    "hello"
  end
end

module Service
  class << self
    attr_accessor :greeter
  end
end

Service.greeter = Greeter
puts Service.greeter.greet          # hello

# 3. Class assigned to a module-level singleton accessor. A call
#    through the accessor reaches the class method.
class CounterClass
  def self.count
    7
  end
end

module Holder
  class << self
    attr_accessor :counter
  end
end

Holder.counter = CounterClass
puts Holder.counter.count           # 7
