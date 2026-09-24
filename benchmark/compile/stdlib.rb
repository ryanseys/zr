# The middle rung of the compile-cost ladder: an ordinary program that
# requires a handful of the stdlib zr carries. Nothing here is slow to
# run; what it times is the require graph an application of a few
# thousand lines pulls in before its first statement.
require "set"
require "json"
require "time"
require "uri"
require "forwardable"
require "ostruct"

s = Set.new([1, 2, 3])
p s.include?(2)
p JSON.parse(JSON.generate({ "a" => [1, 2] }))
p Time.at(0).utc.iso8601
p URI.parse("https://example.com/a?b=1").host
p OpenStruct.new(a: 1).a
