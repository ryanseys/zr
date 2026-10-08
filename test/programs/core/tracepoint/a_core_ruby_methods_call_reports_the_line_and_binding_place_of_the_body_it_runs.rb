# A core method that CRuby writes in Ruby and splits for a call of its
# plain arguments alone (Array#first: `Primitive.mandatory_only?`)
# reports that body's :call line for such a call, and its def's line for
# any other. Its binding stands on the first line of the body that runs.

seen = []
TracePoint.new(:call) do |tp|
  seen << [tp.method_id, tp.binding.source_location, tp.lineno] if %i[first class].include?(tp.method_id)
end.enable do
  [1, 2].first
  [1, 2].first(1)
  1.class
end
p seen
