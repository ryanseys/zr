# `$-W` is the warning level that `$VERBOSE` gives: 0 for nil, 1 for
# false and 2 for true. It is read-only, and a global like any other.
p $-W
[nil, false, true, 1, "x"].each do |v|
  $VERBOSE = v
  p [v, $-W]
end
$VERBOSE = false
p defined?($-W)
p global_variables.include?(:$-W)
begin
  eval("$-W = 2")
rescue NameError => e
  p [e.class, e.message, e.name]
end
p Ractor.new { $-W }.value
def level = $-W
$VERBOSE = nil
p level
$VERBOSE = false
