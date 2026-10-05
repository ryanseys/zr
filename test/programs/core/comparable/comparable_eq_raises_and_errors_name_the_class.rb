# Comparable#== lets the errors of <=> through, and a comparison error
# names a class by its to_s.
def show
  p yield
rescue Exception => e
  p [e.class, e.message]
end

class Cmp
  include Comparable
  attr_accessor :result
  def <=>(other) = result.call
end

o = Cmp.new
o.result = -> { 0 }
show { o == nil }
o.result = -> { raise NotImplementedError, "not a StandardError" }
show { o == nil }
o.result = -> { raise StandardError, "plain" }
show { o == nil }
o.result = -> { "bad value" }
show { o == nil }
show { "bad value" > 0 }

labeled = Class.new do
  def self.to_s = "Labeled\u{30a8}"
  singleton_class.alias_method :inspect, :to_s
  singleton_class.alias_method :name, :to_s
end
show { 1.0 < labeled.new }
show { 1 < labeled.new }
show { 1.0 < nil }
