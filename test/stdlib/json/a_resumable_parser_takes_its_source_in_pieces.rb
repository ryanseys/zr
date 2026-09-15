# JSON::ResumableParser takes its source in pieces: a token a piece cuts
# is read again once the rest comes, partial_value closes the containers
# still open, and each whole document waits in value.
require "json"
pr = JSON::ResumableParser.new
pr << %q({"user": "george", "role": "ad)
p pr.parse, pr.eos?, pr.partial_value, pr.rest, pr.partial_value?, pr.value?, pr.parsed_bytes, pr.empty?
pr << %q(min" }[1, 2, 3])
p pr.parse, pr.value, pr.parse, pr.value, pr.parse, pr.eos?, pr.empty?
pr << "123"; p pr.parse, pr.rest; pr << " "; p pr.parse, pr.value
pr << "[1, [2, 3,"; p pr.parse, pr.partial_value, (pr.value rescue $!)
pr.clear; pr << "tr"; p pr.parse, pr.rest; pr << "ue x"; p pr.parse, pr.value; p (pr.parse rescue $!), pr.rest
pr.clear; pr << "/* c"; p pr.parse; pr << " */ 1 "; p pr.parse, pr.value
pr2 = JSON::ResumableParser.new(symbolize_names: true); pr2 << %({"a":1}); p pr2.parse, pr2.value
pr3 = JSON::ResumableParser.new
["[", " {\"k\" : [1 , 2.5", "e3 ] , \"s\": \"a\\u00", "e9\" } ", "]", " -"].each { |piece| pr3 << piece; p [piece, pr3.parse, pr3.partial_value, pr3.rest] }
p pr3.value? && pr3.value
pr4 = JSON::ResumableParser.new
pr4 << "[1]\n[2]\n{\"x\": nu"
got = []
got << pr4.value while pr4.parse
p got, pr4.partial_value, pr4.partial_value?, pr4.parsed_bytes
pr4 << "ll}"; p pr4.parse, pr4.value, pr4.empty?
p((JSON::ResumableParser.new.tap { |x| x << "[1,]" }.parse rescue $!))

__END__
false
false
{"user" => "george", "role" => nil}
"\"ad"
true
false
30
false
true
{"user" => "george", "role" => "admin"}
true
[1, 2, 3]
false
true
true
false
"123"
true
123
false
[1, [2, 3]]
#<ArgumentError: no ready value>
false
"tr"
true
true
#<JSON::ParserError: unexpected character: 'x'>
"x"
false
true
1
true
{a: 1}
["[", false, nil, "["]
[" {\"k\" : [1 , 2.5", false, [{"k" => [1]}], "2.5"]
["e3 ] , \"s\": \"a\\u00", false, [{"k" => [1, 2500.0], "s" => nil}], "\"a\\u00"]
["e9\" } ", false, [{"k" => [1, 2500.0], "s" => "aé"}], ""]
["]", true, [{"k" => [1, 2500.0], "s" => "aé"}], ""]
[" -", false, nil, "-"]
false
[[1], [2]]
{"x" => nil}
true
8
true
{"x" => nil}
true
#<JSON::ParserError: unexpected character: ']'>
