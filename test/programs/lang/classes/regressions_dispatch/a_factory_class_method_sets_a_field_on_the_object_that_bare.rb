# A factory class method (`def self.from_raw`) makes an instance
# with a bare `new`, then calls a setter on it with the value of a
# user-defined `fetch`. The `fetch` has a nil default, and the call
# gives "" in its place.

class T_issue207_factory_pattern_P
  def initialize(h)
    @h = h
  end
  def fetch(key, default = nil)
    return @h[key] if @h.key?(key)
    default
  end
end

class T_issue207_factory_pattern_T
  attr_accessor :title
  def self.from_raw(params)
    instance = new
    instance.title = params.fetch(:title, "")
    instance
  end
end

p = T_issue207_factory_pattern_P.new({title: "hello", count: 42})
t = T_issue207_factory_pattern_T.from_raw(p)
puts t.title
