class Counter
  @@count = 0
  @@names = []
  def initialize(name)
    @name = name
    @seen = 0
    @@count += 1
    @@names << name
  end
  def self.count = @@count
  def bump = @seen += 1
  protected def peek = @seen
  private def secret = :s
end
class Sub < Counter
  @@extra = true
end
c = Counter.new("a")
p c.instance_variables
p c.instance_variable_get(:@name), c.instance_variable_get("@seen"), c.instance_variable_get(:@nope)
p c.instance_variable_set(:@late, 3), c.instance_variables
p c.instance_variable_defined?(:@late), c.instance_variable_defined?(:@zzz)
begin
  c.instance_variable_get(:name)
rescue NameError => e
  p e
end
begin
  c.instance_variable_get(3)
rescue TypeError => e
  p e
end
p Counter.class_variables.sort, Sub.class_variables.sort, Sub.class_variables(false)
p Counter.class_variable_get(:@@count), Sub.class_variable_get("@@count")
p Counter.class_variable_defined?(:@@names), Counter.class_variable_defined?(:@@extra), Sub.class_variable_defined?(:@@count)
Sub.class_variable_set(:@@count, 10)
p Counter.count
Sub.class_variable_set(:@@fresh, 1)
p Sub.class_variables(false), Counter.class_variables.include?(:@@fresh)
begin
  Counter.class_variable_get(:@@missing)
rescue NameError => e
  p e
end
begin
  Counter.class_variable_get(:count)
rescue NameError => e
  p e
end
p Counter.singleton_methods, c.singleton_methods
def c.solo = 1
p c.singleton_methods, c.singleton_methods(false)
module Extra
  def extra = 2
end
c.extend(Extra)
p c.singleton_methods.sort, c.singleton_methods(false)
p c.methods.include?(:bump), c.methods.include?(:peek), c.methods.include?(:secret), c.methods(false)
p c.public_methods(false).sort.first(3)
p c.private_methods.include?(:secret), c.protected_methods
p 1.singleton_methods, 1.methods.include?(:+)
p Counter.instance_methods(false).sort
p Counter.send("bump") rescue p $!
p c.send("bump"), c.public_send(:bump)
begin
  c.public_send(:secret)
rescue NoMethodError => e
  p e
end
p c.send(:secret)
module Tracked
  def self.included(base) = puts "included in #{base}"
  def self.extended(base) = puts "extended #{base.class}"
end
class Base
  def self.inherited(sub)
    puts "inherited: #{sub} < #{self}"
    super
  end
end
class Leaf < Base
  include Tracked
end
Object.new.extend(Tracked)
begin
  Object.new.extend(3)
rescue TypeError => e
  p e
end
begin
  Object.new.extend
rescue ArgumentError => e
  p e
end
begin
  class Bad < 3; end
rescue TypeError => e
  p e
end
p Leaf.ancestors.first(3)
