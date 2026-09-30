# `String#gsub(regex, hash)` -- the per-match hash-lookup form
# Ruby uses for HTML/JSON escape. Each match is replaced by the
# value that the hash holds for it.

ESCAPES = {
  "&" => "&amp;",
  "<" => "&lt;",
  ">" => "&gt;",
}.freeze

PATTERN = /[&<>]/.freeze

puts "a&b<c".gsub(PATTERN, ESCAPES)
puts "<p>x & y</p>".gsub(PATTERN, ESCAPES)
puts "no specials here".gsub(PATTERN, ESCAPES)
