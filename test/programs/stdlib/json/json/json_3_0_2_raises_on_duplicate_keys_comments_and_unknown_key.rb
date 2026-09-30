# json 3.0.2: duplicate keys and comments raise unless allowed, unknown
# keywords raise, a trailing surrogate alone raises, and a strict Symbol
# is written as its name.
require "json"
def try = yield rescue $!

p JSON::VERSION, defined?(JSON::GenericObject), JSON.const_defined?(:ParserOptions)
p try { JSON.parse('{"a": 1, "a": 2}') }
e = try { JSON.parse('{"a": [1, {"b": 2, "b": 3}]}') }
p e, e.json_path
e = try { JSON.parse('{"a": [1, {"b": tru}]}') }
p e, e.json_path, e.line, e.column
e = try { JSON.parse('[1, 2, [3, x]]') }
p e.json_path
e = try { JSON.parse('{"a": 1, "b": ') }
p e, e.json_path
e = try { JSON.parse('{"a": 1, ') }
p e.json_path
p try { JSON.parse('/* c */ [1]') }, JSON.parse('/* c */ [1]', allow_comments: true)
p try { JSON.parse('[1]', bogus: 1) }, try { JSON.parse('[1]', bogus: 1, other: 2) }
p try { JSON.generate([1], bogus: 1) }, try { JSON::State.new(escape_slash: true) }
p JSON::State.new.respond_to?(:escape_slash), JSON::State.new.send(:allow_duplicate_key?)
p try { JSON.parse('"\udc00"') }, JSON.parse('"😀"')
p JSON.generate({ a: 1, "a" => 2 }) rescue p $!
p JSON.generate({ a: 1, "a" => 2 }, allow_duplicate_key: true)
p JSON.generate(:sym, strict: true), JSON.generate([:sym]), JSON[ '[1]' ], JSON['{"a":1}', symbolize_names: true]
p JSON.parse("18446744073709551615"), JSON.parse("-9223372036854775808"), JSON.parse("-9223372036854775809")
p JSON.load('{"json_class": "Range", "a": [1, 2, false]}')
p try { JSON.load("[1]", nil, bogus: 1) }
p JSON.dump({ "a" => 1 }), JSON.pretty_generate({ "a" => [1] })
p try { JSON::Coder.new(bogus: 1) }
require "json/generic_object"
p defined?(JSON::GenericObject)
