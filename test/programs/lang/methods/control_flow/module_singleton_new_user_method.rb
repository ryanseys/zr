# `module M; def self.new(x); ...; end; end` defines a user-level
# class method, NOT a constructor (modules can't be instantiated).
# `M.new(args)` returns what the method returns, as a sibling method
# on the same module (`def self.edit`) does.

module Views
  module Articles
    def self.new(x)
      "rendered_#{x}"
    end

    def self.edit(x)
      "edited_#{x}"
    end
  end
end

puts Views::Articles.new("a")
puts Views::Articles.edit("b")
