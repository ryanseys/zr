# Loading one stdlib gem must not disturb another: `require "strscan"`
# then `require "json"` still both work end to end.

require "strscan"
require "json"
s = StringScanner.new("hello world")
p s.scan(/\w+/)
p s.rest
p JSON.dump({ "a" => 1 })
