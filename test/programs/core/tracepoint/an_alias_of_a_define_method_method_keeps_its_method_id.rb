# An alias of a define_method method fires :call, :return, :b_call and
# :b_return with the name it was defined with as method_id and the
# alias as callee_id.
o = Class.new {
  define_method(:m) { |x = 1| x }
  alias alias_m m
  alias_method :am2, :alias_m
}.new
ev = []
TracePoint.new(:call, :return, :b_call, :b_return) { |tp| ev << [tp.event, tp.method_id, tp.callee_id] }.enable { o.alias_m; o.m; o.am2 }
ev.each { p _1 }
p o.method(:alias_m).name, o.method(:alias_m).original_name
