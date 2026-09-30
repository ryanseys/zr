# A user-defined method whose name matches a built-in method (e.g.
# `String#index`) does not change the call on a String: `s.index("[")`
# with a String argument calls `String#index`. The same is true for
# names like `show` and `create` on user classes.

class StringIndexer
  def index(needle, start = 0)
    "from-StringIndexer"
  end
end

def find_bracket(s)
  s.index("[")
end
puts find_bracket("hello[world]")    # 5

# String method that's also defined on a controller-shaped class.
class ArticlesController
  def show
    "ArticlesController#show"
  end
end

def first_or_default(s)
  s.start_with?("/")    # String#start_with? — should not be shadowed
end
puts first_or_default("/articles")    # true
puts first_or_default("articles")     # false

# Hash-shared `keys` shouldn't pull a user-class param into obj_X.
class KeyHolder
  def keys
    ["alpha", "beta"]
  end
end

def count_keys(h)
  h.keys.length
end
puts count_keys({a: 1, b: 2, c: 3})   # 3
