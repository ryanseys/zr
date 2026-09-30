r = /abc/
puts r.is_a?(Regexp)
puts r.is_a?(Object)
m = "abc".match(/a/)
puts m.is_a?(MatchData)
