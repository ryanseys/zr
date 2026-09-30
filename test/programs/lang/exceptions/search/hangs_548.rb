# Four shapes that must end, not hang, at runtime.
# Adam Doppelt's "Puzzles, third edition."
#
# 1. `a.concat(a, a)` -- concat appends every arg. When an arg is
#    the receiver itself, concat uses the arg's length from before
#    the call, so the loop ends.
#
# 2. `/\#{re}/` -- `\#` is a literal `#`, and then `{re}` follows.
#    CRuby treats `/{re}/` as matching the literal text `{re}`
#    (`{...}` without a valid quantifier is literal).
#
# 3. `while () ; 123 ; end` -- the empty `()` is nil, so it is
#    false. `while ()` never enters the body, as in CRuby.
#
# 4. `i += 1; raise; rescue; retry unless i == 7` -- the local `i`
#    keeps its value across each raise and retry. So `i == 7`
#    becomes true and the retry loop ends.

# Repro 1: self-concat with self twice.
a = [1, 2]
a.concat(a, a)
puts a.length      # 6 -- [1,2] + [1,2] + [1,2]

# Repro 2: regex with literal `\#{re}` characters.
re = /foo|bar/
r2 = /\#{re}/
puts "ok2"

# Repro 3: while () never enters.
while () ; 123 ; end
puts "ok3"

# Repro 4: retry-counter keeps its value across retry.
def foo
  i = 0
  begin ; i += 1 ; raise "bar" ; rescue ; retry unless i == 7 ; end
  raise "baz" unless i == 7
rescue
  123
end
puts foo  # 123  (foo's body would also raise "baz" if i != 7; here i == 7
          #       so no raise, and the function falls through. The
          #       outer rescue is dead code for this path.)
