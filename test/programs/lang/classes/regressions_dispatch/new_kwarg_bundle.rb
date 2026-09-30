# `Class.new(kw: val)` (Symbol-keyed kwargs) where the
# class's initialize takes a single positional `attrs` param.
# CRuby binds `attrs = {kw: val}` (the kwargs become a positional
# hash whose keys are the kwarg *symbols*). Access is via the kwarg
# symbols (`attrs[:title]`); String keys would not match, as in CRuby.

class T_new_kwarg_bundle_Article
  def initialize(attrs)
    @title = attrs[:title]
    @body  = attrs[:body]
  end
  attr_reader :title, :body
end

a = T_new_kwarg_bundle_Article.new(title: "Hello", body: "World")
puts a.title
puts a.body

# A second kwarg call site to the same initialize.
b = T_new_kwarg_bundle_Article.new(title: "Second", body: "Post")
puts b.title

# Mixed value types in one kwarg call: the Hash holds each value with
# its own class.
class T_new_kwarg_bundle_Mixed
  def initialize(opts)
    @s = opts[:name]
    @n = opts[:count]
  end
  attr_reader :s, :n
end

m = T_new_kwarg_bundle_Mixed.new(name: "abc", count: 42)
puts m.s
puts m.n.inspect
