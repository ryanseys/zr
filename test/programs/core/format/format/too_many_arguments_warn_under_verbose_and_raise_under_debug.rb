def f = format("%d", 1, 2)
$VERBOSE = true
p f
$DEBUG = true
begin
  f
rescue ArgumentError => e
  p e.message
end
