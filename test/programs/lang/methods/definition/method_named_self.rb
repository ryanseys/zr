# A method whose name is `self`. Ruby allows it: `def self(token)` with an
# argument list defines an ordinary instance method called `self`, reachable
# through `send`. The `parser` gem's AST builder does this.
#
# `self` is a keyword the generated program cannot escape and reuse, so it
# gets a mangled spelling of its own.

class Builder
  def self(token)
    "made #{token}"
  end
end

puts Builder.new.send(:self, "node")
p Builder.instance_methods(false)
