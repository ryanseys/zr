# When a method's only positional has a default hash literal
# (`attrs = {}`), call sites that pass kwargs whose names DON'T
# match the param name should bundle the kwargs into that hash
# slot. CRuby auto-folds trailing unmatched kwargs into a hash
# positional. The callee sees the kwargs in the Hash, not an empty
# Hash, even when the values have mixed classes.
#
# Sam Ruby's roundhouse `comment_test.rb` uses this shape:
# `Comment.create(article_id: article.id, ...)` against
# `def self.create(attrs = {})`.

class T_kwargs_into_default_hash_param_Bag
  def self.create(attrs = {})
    new(attrs)
  end
  def initialize(attrs = {})
    @id = attrs[:id] || 0
    @name = attrs[:name] || "(none)"
    @count = attrs.length
  end
  attr_reader :id, :name, :count
end

# Class method form: `.create(kw: val, ...)`.
b1 = T_kwargs_into_default_hash_param_Bag.create(id: 7, name: "alpha")
puts b1.id     # 7
puts b1.name   # alpha
puts b1.count  # 2

# Instance constructor form: `.new(kw: val, ...)` with default
# hash param.
b2 = T_kwargs_into_default_hash_param_Bag.new(id: 42, name: "beta")
puts b2.id     # 42
puts b2.name   # beta
puts b2.count  # 2

# Empty call: defaults still kick in.
b3 = T_kwargs_into_default_hash_param_Bag.create
puts b3.id     # 0
puts b3.name   # (none)
puts b3.count  # 0

# Mixed kwarg types -- String + Integer -- in one Hash.
b4 = T_kwargs_into_default_hash_param_Bag.create(id: 99, name: "gamma")
puts b4.id     # 99
puts b4.name   # gamma
