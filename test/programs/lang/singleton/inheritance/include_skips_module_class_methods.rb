# `class C; include M; end` does NOT copy M's `def self.X` (class
# methods on the module) into C as instance methods. M's class methods
# write M's own @ivars, so M's @slots stays a Hash.

module M
  @slots = {}
  def self.set(k, v); @slots[k] = v; nil; end
  def self.get(k); @slots.fetch(k, nil); end
end

class MyTest
  include M
  def run
    M.set(:title, "Hello")
    puts M.get(:title).inspect
  end
end

MyTest.new.run

# `MyTest.new` should NOT respond to `set` / `get` -- those are
# class methods on M, not instance methods. Probing via respond_to?
# (true/false) confirms the include didn't import them.
puts MyTest.new.respond_to?(:set)
puts MyTest.new.respond_to?(:get)
