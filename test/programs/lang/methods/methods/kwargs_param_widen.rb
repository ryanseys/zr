# A module class method's required keyword params get their types from
# each `key: value` pair at the call sites. Each value goes to the
# keyword param of the same name, and keeps its own type.
#
# This is the shape of Roundhouse's real-blog `form_with(model:,
# model_name:, action:, method:, opts:)`, with two different object
# types passed to the same keyword.

# Article and Comment each have an array ivar. Each call site passes a
# local that already holds the object, not an inline `X.new(...)`.

class Article
  def initialize(id, name); @id = id; @name = name; @tags = []; end
  def kind; "article-" + @name; end
end

class Comment
  def initialize(body); @body = body; @replies = []; end
  def kind; "comment-" + @body; end
end

module M
  def self.render(model:, label:)
    "[#{label}] #{model.kind}"
  end
end

# Make the objects first, as Roundhouse does, and keep them in locals.
a = Article.new(7, "alpha")
c = Comment.new("hello")

# Two call sites with different obj types for `model:`. The keyword
# param takes both types, and each call gets its own object.
puts M.render(model: a, label: "art")     # [art] article-alpha
puts M.render(model: c, label: "com")     # [com] comment-hello

# Module-inner class constructor inside a module class method
# body. `Inner` resolves to N::Inner, and N::Inner.new gets the
# object from `model:`.
module N
  class Inner
    def initialize(x); @x = x; end
    def show; "inner=#{@x.kind}"; end
  end

  def self.make(model:)
    Inner.new(model).show
  end
end

puts N.make(model: a)                     # inner=article-alpha
