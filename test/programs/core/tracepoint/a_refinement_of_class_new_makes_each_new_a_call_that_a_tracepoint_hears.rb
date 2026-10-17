# CRuby's opt_new runs Class#new with no call, so a TracePoint hears no
# `new`. A refinement of Class#new makes Class's own entry a refined one,
# with or without a `using`, and from then on every `new` is a call, as
# power_assert relies on (its enable_tracepoint_events refines Class#new).
events = []
tp = TracePoint.new(:c_call, :c_return) { events << [it.event, it.method_id, it.defined_class] if it.method_id == :new }
hear = ->(&code) { events.clear; value = tp.enable(&code); [value.class, events.dup] }

class Point
  def initialize(x = 0) = @x = x
  attr_reader :x
end

p hear.() { Object.new }
p hear.() { Point.new(1) }

module ShoutingNew
  refine(Class) { def new(*) = :refined }
end

p hear.() { Object.new }
p hear.() { Point.new(2) }
p Point.new(3).x
p hear.() { Point.new { :block } }

module UsesIt
  using ShoutingNew
  p Object.new, Point.new(4)
end
p Object.new.class

# String.new and Array.new are their own methods, heard before and after.
p hear.() { String.new("a") }
p hear.() { Array.new(2) }

module Hides
  refine(Class) { undef_method :new }
end
p hear.() { Point.new(5) }
module UsesHides
  using Hides
  begin
    Point.new
  rescue NoMethodError => e
    p e.class
  end
end
