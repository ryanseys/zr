# `class << CONST` on a constant-bound object installs per-object
# singleton methods on it.

class Foo
  ANOTHER = Object.new
  class << ANOTHER
    def hi
      "hi"
    end
  end
end
puts Foo::ANOTHER.hi
