# `include` with a ConstantPathNode argument
# (`include A::B`, not just bare `include B`).
#
# A qualified path like `Foo::Bar::Baz` gives the class the
# methods of that module, for a fresh class and for a reopen.
# Cross-namespace and nested-class includes both resolve.

module A
  module B
    def foo
      "foo-from-AB"
    end

    def greet(name)
      "hello, " + name + "!"
    end
  end
end

class Host
  include A::B
end

puts Host.new.foo
puts Host.new.greet("world")

# Three-deep path: `X::Y::Z` -> `X_Y_Z`.
module X
  module Y
    module Z
      def deep
        "deep-from-XYZ"
      end
    end
  end
end

class DeepHost
  include X::Y::Z
end

puts DeepHost.new.deep

# Including via a path also from a class nested under a module.
# No `Nested::A::B` exists, so the lookup finds the top-level
# `A::B`.
module Nested
  class Sub
    include A::B

    def via_nested
      foo + " (via nested)"
    end
  end
end

puts Nested::Sub.new.via_nested

# Absolute-path include (`::Top`). Inside `module Outer` a bare
# `Helper` names `Outer::Helper`, because such a module exists; the
# absolute path `::Helper` resolves to the top-level `Helper`.
module Helper
  def from_top
    "top-helper"
  end
end

module Outer
  module Helper
    def from_top
      "outer-helper"
    end
  end

  class Inside
    include ::Helper
  end
end

puts Outer::Inside.new.from_top

