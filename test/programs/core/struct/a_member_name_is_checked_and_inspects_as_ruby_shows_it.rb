# Struct.new refuses a setter's name as a member, shows a member name
# past ASCII bare in inspect, and warns with a position when it replaces
# a constant.
def t(l)
  p [l, yield]
rescue StandardError => e
  p [l, e.class, e.message]
end
t(:attrset) { Struct.new(:x=) }
t(:attrset2) { Struct.new(:a, :b?) }
t(:bad_name) { Struct.new(:"1a") }
s = Struct.new("R\u{e9}sum\u{e9}", :"r\u{e9}sum\u{e9}")
t(:const) { Struct.const_get("R\u{e9}sum\u{e9}").equal?(s) }
t(:inspect) { s.new(42).inspect }
$stderr = $stdout
$VERBOSE = true
Struct.new("R\u{e9}sum\u{e9}", :"r\u{e9}sum\u{e9}")
$VERBOSE = nil
Struct.new("R\u{e9}sum\u{e9}", :"r\u{e9}sum\u{e9}")
t(:ops) { Struct.new(:a?, :b!).members }
