# json 2.20.0's own ruby over zr's port of its C half: a duplicate key, a
# comment and a mixed-key hash warn (in the deprecated category) where
# json 3.0 raises, unknown options and escape_slash pass, a lone trailing
# surrogate is read as its bytes, and an error keeps no path.
require "json"
$stderr.sync = $stdout.sync = true
def show(label)
  print label, ": "
  p yield
rescue => e
  puts "#{e.class}: #{e.message}"
end

show("version") { JSON::VERSION }
show("dup key") { JSON.parse('{"a":1,"a":2}') }
show("dup key nested") { JSON.parse('{"x":{"b":1,"b":2}}') }
show("dup key allowed") { JSON.parse('{"a":1,"a":2}', allow_duplicate_key: true) }
show("dup key refused") { JSON.parse('{"a":1,"a":2}', allow_duplicate_key: false) }
show("comment") { JSON.parse("[1, /* c */ 2]") }
show("line comment") { JSON.parse("[1, // c\n 2]") }
show("comment allowed") { JSON.parse("[1, /* c */ 2]", allow_comments: true) }
show("comment refused") { JSON.parse("[1, /* c */ 2]", allow_comments: false) }
show("six warnings") { JSON.parse('[' + (1..6).map { |i| %({"k#{i}":1,"k#{i}":2}) }.join(",") + ']').size }
show("lone low surrogate") { JSON.parse('["\udc00"]').first.bytes }
show("lone high surrogate") { JSON.parse('["\ud800"]') }
show("error path") { begin; JSON.parse('[1, {"a": nul}]'); rescue JSON::ParserError => e; e.instance_variables; end }
show("unknown parse option") { JSON.parse("[1]", nonsense: true) }
show("escape_slash") { JSON.generate(["a/b"], escape_slash: true) }
show("state escape_slash") { s = JSON::State.new; s.escape_slash = true; [s.escape_slash?, s.script_safe?, s.escape_slash] }
show("unknown generate option") { JSON.generate([1], nonsense: true) }
show("mixed keys") { JSON.generate({ "a" => 1, a: 2 }) }
show("mixed keys allowed") { JSON.generate({ "a" => 1, a: 2 }, allow_duplicate_key: true) }
show("mixed keys refused") { JSON.generate({ "a" => 1, a: 2 }, allow_duplicate_key: false) }
show("allow_duplicate_key?") { [JSON::State.new.allow_duplicate_key?, JSON::State.new(allow_duplicate_key: true).allow_duplicate_key?, JSON::State.new(allow_duplicate_key: false).allow_duplicate_key?] }
show("pretty") { JSON.pretty_generate({ "a" => [1, 2.5, nil, true], "b" => { "c" => "d" } }) }
show("dump/load") { JSON.load(JSON.dump({ "a" => [1, "x"] })) }
show("big int") { JSON.parse("[123456789012345678901234567890, 18446744073709551615, -9223372036854775808]") }
show("symbolize") { JSON.parse('{"a":{"b":1}}', symbolize_names: true) }
show("create_additions") { JSON.parse('{"json_class":"String","raw":[97]}') }

Warning[:deprecated] = true
show("warned dup key") { JSON.parse(%({"a":1,\n "a":2})) }
show("warned comment") { JSON.parse("[1, /* c */ 2]") }
show("warned six") { JSON.parse('[' + (1..6).map { |i| %({"k#{i}":1,"k#{i}":2}) }.join(",") + ']').size }
show("warned mixed keys") { JSON.generate({ "a" => 1, a: 2 }) }
show("warned parser config") { JSON::Ext::ParserConfig.new({}).parse('{"z":1,"z":2}') }
