# Two `class Foo` definitions in one program (from two
# require_relative'd files, or a single file with a re-opened class).
# CRuby's semantics are "last definition wins": the second body
# replaces the first for any method with the same name; methods
# unique to either copy survive. This single-file reopen covers the
# same shape as the require_relative case.

class Foo
  def initialize
    @x = 1
  end
  def go
    "first: " + @x.to_s
  end
  def only_first
    "kept"
  end
end

class Foo
  def initialize
    @x = 2
  end
  def go
    "second: " + @x.to_s
  end
  def only_second
    "added"
  end
end

f = Foo.new
puts f.go
puts f.only_first
puts f.only_second
