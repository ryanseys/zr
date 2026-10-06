# ParserError#json_path: where in the document the parse stopped, as
# parser.c counts it from its open containers.
require "json"
def path(src, **o) = (JSON.parse(src, **o) rescue $!.json_path)

p path('{"a": {"b": [0, 1, {"c": nil}]}}'), path('[[[], [1, 2,]]]'), path('{"x": 1, "y": {"z" 1}}')
p path('{"k": [1, 2'), path('[1, {"a": 1, "a": 2}]'), path('{"a": {"a": 1, "b": 2, "a": 3}}')
p path('{"a": [1,, 2]}'), path('{"q": 1 "r": 2}'), path('{"a": [1, 2]]}'), path('"\\x"')
p path('{"a": [[1] x]}'), path('[1, [2, [3, "\\u12"]]]')
p (JSON.parse('[1] x') rescue $!.json_path.class)
q = JSON::ResumableParser.new
q << '{"a": [1, {"b": 2, "b": 3}]}'
p (q.parse rescue [$!, $!.json_path, $!.line])
q = JSON::ResumableParser.new
q << '{"a": [1, x'
p (q.parse rescue [$!, $!.json_path])
p (JSON.parse('[' * 3 + ']' * 3, max_nesting: 2) rescue [$!, $!.json_path])
p JSON::ParserError.new("m").json_path
