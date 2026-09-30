# `String#index` / `String#rindex` return nil when there is no
# match, so the CRuby idiom
#
#   pos = body.index('"content"', i)
#   break if pos.nil?
#
# ends the loop. The nil works end-to-end:
# - `pos.nil?` / `pos == nil` / `pos != nil`
# - `pos.inspect` (prints "nil" or the Integer)
# - `while pos = s.index(...)` truthiness (nil is falsy)
#
# A found position is an Integer, and later code can use it as one.

s = "hello world"

# Found and not-found inspect ("6" / "nil").
puts s.index("world").inspect    # 6
puts s.index("xyz").inspect      # nil
puts s.index("hello").inspect    # 0   (real index 0, not nil)

# CRuby's nil-check idiom works as written.
pos = s.index("xyz")
puts pos.nil?                    # true
puts (pos == nil)                # true
puts (pos != nil)                # false

pos = s.index("hello")
puts pos.nil?                    # false (real index 0 is NOT nil)
puts (pos != nil)                # true

# rindex inherits the same shape.
puts "abcdabcd".rindex("c").inspect    # 6
puts "abcdabcd".rindex("z").inspect    # nil

# Walk-all idiom from the issue's GPT-2 BPE example.
body = "header.payload.sig"
i = 0
positions = ""
while true
  pos = body.index(".", i)
  break if pos.nil?
  positions = positions + pos.to_s + ","
  i = pos.to_i + 1
end
puts positions                   # 6,14,
