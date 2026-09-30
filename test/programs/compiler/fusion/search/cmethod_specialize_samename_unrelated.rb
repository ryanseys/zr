# An inherited class method that does a bare `new` gets a copy for each
# subclass that calls it. Here `Base.find` gets a copy for `Article`.
# The unrelated `Store.find` has the same name in a different module.
# It is not a copy of `Base.find`, so it stays, and `Store.lookup`
# calls it with no explicit receiver.

class Base
  def self.find(x)
    new
  end
  def initialize
    @v = 7
  end
  attr_reader :v
end

# A subclass that inherits Base.find: `Article.find` triggers the
# bare-`new` specialization, appending an `Article`-owned `find` copy.
class Article < Base
end

# An unrelated module with its own same-named `find`. It must NOT be
# treated as a specialization of Base.find.
module Store
  def self.find(x)
    x * 2
  end
  def self.lookup(x)
    # Bare sibling call -> resolves to Store.find. The call has no
    # constant receiver.
    find(x)
  end
end

p Article.find(1).v
p Store.lookup(21)
