# An if/else expression whose branches both build a Regexp gives a
# Regexp, and `pattern.match?(...)` on it matches.

def check(use_a)
  pattern = if use_a
              Regexp.new("aaa")
            else
              Regexp.new("bbb")
            end
  puts pattern.match?("xaaay") ? "match" : "no match"
end

check(true)    # match    (uses /aaa/)
check(false)   # no match (uses /bbb/, body has no "bbb")

# Dynamic-source arm: each Regexp.new(<expr>) builds its pattern at
# run time, and the local holds the Regexp.
def check_dyn(prefix, body)
  pattern = if prefix == "x"
              Regexp.new(prefix + "aaa")
            else
              Regexp.new(prefix + "bbb")
            end
  puts pattern.match?(body) ? "dyn-match" : "dyn-no-match"
end

check_dyn("x", "xaaa-yes")     # dyn-match
check_dyn("y", "ybbb-yes")     # dyn-match
check_dyn("x", "nope")         # dyn-no-match
