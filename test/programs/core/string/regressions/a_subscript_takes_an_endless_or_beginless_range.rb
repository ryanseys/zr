# `s[1..]` (Ruby 2.6+ endless range) gives the substring from index 1
# to the end. CRuby returns "id" for ":id"[1..], as a router does when
# it strips the leading `:` from a `:id` pattern segment.
#
# A missing endpoint means the matching end of the string:
#   - missing left  -> 0  (s[..k] == s[0..k])
#   - missing right -> -1 (s[k..] == s[k..-1])
# The exclusive flag has no effect on the missing endpoint (CRuby
# semantics: `s[1..]` == `s[1...]` == `s[1..-1]`).

s = "hello"

# Endless from inclusive lower bound.
puts s[1..]      # ello
puts s[1...]     # ello  (CRuby treats endless ... same as ..)
puts s[-2..]     # lo

# Beginless to inclusive upper bound.
puts s[..2]      # hel
puts s[...2]     # he   (exclusive upper)

# The Sam Ruby repro shape: strip the leading char.
pp = ":id"
puts pp[1..]     # id
