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

# --- a class method and a `define_method` body -----------------------------
class Owner
  def self.classy(s)
    s =~ /(y)/
    $1
  end
  define_method(:installed) do |s|
    s =~ /(y)/
    $1
  end
end
"abc" =~ /(b)/
p Owner.classy("xyz")
p probe.call
p Owner.new.installed("xyz")
p probe.call

# --- a scope that fails to match reports the failure, not the inherited one -
def fails(s)
  s =~ /(q)/
  [$~, $1]
end
"abc" =~ /(b)/
p fails("xyz")
p probe.call

