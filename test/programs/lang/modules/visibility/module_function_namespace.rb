# `module_function` in a module body installs the subsequent
# `def name` as both an instance method (for include-mixin)
# and a class method (`Mod.name`). This test uses only the
# class-method form.
#
# A bare class ref (`Box.new`) in any method body inside a module
# resolves through the lexical scope, to `Outer::Box`. This is
# also true without `module_function`.

module Outer
  module Helper
    module_function
    def small;  [1, 2, 3]; end
    def medium; [4, 5, 6, 7]; end
  end

  class Conf
    def initialize(flag)
      @flag = flag
      @arr = []
      @arr << 0    # force heap layout
    end
    attr_reader :flag
  end

  class Box
    def initialize(conf)
      @c = conf
      @arr = []
      @arr << 0
    end
    attr_reader :c
  end

  module Builder
    # `def self.X` form — the bare `Box.new` inside walks the
    # lexical scope to resolve `Outer_Box`.
    def self.make(conf)
      Box.new(conf)
    end
  end
end

# module_function dispatch.
puts Outer::Helper.small.length    # 3
puts Outer::Helper.medium.length   # 4

# Module class method body that references a sibling class
# bare-named.
b = Outer::Builder.make(Outer::Conf.new(true))
puts b.c.flag                       # true
