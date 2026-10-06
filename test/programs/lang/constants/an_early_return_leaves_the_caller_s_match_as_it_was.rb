# `$~` -- and every read that goes through it (`$1`, `$&`, `` $` ``, `$'`,
# `Regexp.last_match`) -- is FRAME-LOCAL. A scope that matches and returns
# leaves the caller's match exactly as it found it, and a scope that never
# matched reads the one it inherited from where it was ENTERED.
#
# The rule follows the frame: a method, a class or module body and a
# singleton-class body each get a scope of their own; a block, a lambda and a
# `define_method` body share the scope of the frame they run under, because
# that is the frame ruby gives them.

probe = -> { [$~ && $~[0], $1] }

# --- an early return cannot leak the callee's match ------------------------
def early(s)
  return :none unless s =~ /(y)/
  $1
end
"abc" =~ /(b)/
p early("zzz")
p probe.call

