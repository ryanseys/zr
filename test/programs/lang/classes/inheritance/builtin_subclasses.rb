# frozen_string_literal: true

# A user subclass of a builtin. The sidecar names the parent, and the
# REGISTRAR follows from the ancestors the backend works out -- a payload
# wrapper for `Array`/`String`/`Hash`, a definition with no instances for
# an immediate, the exception registrar for an exception.

class Stack < Array
  def peek = last
end

s = Stack.new
s.push(1)
s << 2
p s
p [s.size, s.peek, s.class]
p s.push(3).class            # a self-return re-wraps to Stack
p s.map { |x| x * 10 }
p s.map { |x| x }.class      # a NEW array is a plain Array
p [s.is_a?(Array), s.is_a?(Enumerable)]
p Stack.new([5, 6, 7]).sum

class Tag < String
  def shout = "#{upcase}!"
end

t = Tag.new("hi")
p [t.shout, t.class, t == "hi", "hi" == t]
p({ "k" => 42 }[Tag.new("k")])

class Counter < Hash
  def initialize = super(0)
end

c = Counter.new
c[:a] += 1
c[:b] += 1
p [c[:a], c[:b], c[:missing]]
p c

# An immediate has no instances at all: the DEFINITION is legal and `.new`
# raises what CRuby raises.
class MyInt < Integer; end
p [MyInt.superclass, MyInt.ancestors.include?(Numeric)]
begin
  MyInt.new
rescue NoMethodError => e
  puts e.message
end

# A builtin with an allocator is an ordinary object.
class Measure < Numeric; end
p [Measure.superclass, Measure < Comparable]

# An exception subclass keeps the native message and backtrace surface.
class Refused < ArgumentError
  def initialize(what) = super("refused #{what}")
end
begin
  raise Refused, "this"
rescue StandardError => e
  p [e.class, e.message, e.is_a?(ArgumentError)]
end
