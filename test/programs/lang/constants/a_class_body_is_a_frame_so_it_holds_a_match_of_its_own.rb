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

# --- a class body is a frame, so it is a scope -----------------------------
"abc" =~ /(b)/
class Body
  "xyz" =~ /(y)/
  INSIDE = $1
end
p Body::INSIDE
p probe.call

"abc" =~ /(b)/
module Mod
  "xyz" =~ /(y)/
end
p probe.call

class Sing
  class << self
    "xyz" =~ /(y)/
  end
end
p probe.call

