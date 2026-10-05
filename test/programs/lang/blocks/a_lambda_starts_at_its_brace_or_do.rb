# A lambda whose parameters span lines starts at its `{` or `do`: that
# is its source_location line and the line its inspect shows.
brace = ->(x,
           y) {
  raise "in the body"
}
p brace.source_location[1], brace.inspect[/:\d+ /]

word = ->(a,
          b) do
end
p word.source_location[1]

begin
  brace.call(1, 2)
rescue RuntimeError => e
  p e.backtrace_locations[0].lineno
end
p ->(a) {}.source_location[1]
