# An inherited factory (`Base.create`) forwards `new(attrs)` with a Hash, so
# the subclass ctor parameter gets values of more than one type across its
# call sites. The inherited attr_accessor field `id` holds an Integer (from
# `@id = 0`). The `self.id = id` setter writes that parameter into the field.
class Base
  attr_accessor :id

  def initialize
    @id = 0
  end

  def self.create(attrs = {})
    new(attrs)
  end
end

class Article < Base
  def initialize(id = 0)
    self.id = id
  end
end

puts Article.new(7).id
