# Anonymous `*` and `**` parameters forward into calls, array literals and
# hash literals exactly as CRuby forwards them. An empty `**` sends no
# keywords, so a callee with only positional parameters accepts the call.

def show(*a, **k) = [a, k]
def pos2(x, y) = [x, y]
def kw_only(a:, b: 0) = [a, b]

# 1. `*` and `**` together into one call, with keywords present and absent.
def both(*, **) = show(*, **)
p both
p both(1, 2)
p both(a: 1)
p both(1, a: 2, b: 3)

# 2. An empty `**` adds no argument, so a positional-only callee works.
def into_pos(*, **) = pos2(*, **)
p into_pos(1, 2)

# 3. `**` alone into a keyword-only callee, with an optional keyword absent.
def into_kw(**) = kw_only(**)
p into_kw(a: 5)
p into_kw(a: 5, b: 6)

# 4. Leading positional parameters ahead of the anonymous rests.
def lead(a, *) = show(a, *)
def lead_kw(a, b = :dflt, *, **) = show(b, a, *, **)
p lead(:x)
p lead(:x, 1, 2)
p lead_kw(1)
p lead_kw(1, 2, 3, z: 4)

# 5. A `*` without `**` takes keywords as a trailing hash and passes it on
#    as a positional hash.
def rest_only(*) = show(*)
p rest_only(1, k: 2)

# 6. An empty splat into a callee with all optional parameters.
def opt(a = :none, b = :none) = [a, b]
def empty_fwd(*) = opt(*)
p empty_fwd
p empty_fwd(1)

# 7. Literals: `[*]`, `{**}` and both mixed with other elements.
def arr(*) = [:head, *, :tail]
def hsh(**) = {first: 0, **}
def hsh_over(**) = {a: :old, **, z: :last}
p arr, arr(1, 2)
p hsh, hsh(a: 1)
p hsh_over(a: :new)

# 8. The forwarded values are new containers; a change to them does not
#    change the caller's array or hash.
def grab(*, **) = [[*], {**}]
args = [1, 2]
opts = {k: 1}
r = grab(*args, **opts)
r[0] << 3
r[1][:j] = 2
p args, opts, r

# 9. `...` with keywords present and absent and an empty argument list.
def dots(...) = show(...)
p dots
p dots(1)
p dots(1, k: 2)

# 10. Forwarding to a receiver and through two levels.
class Box
  def put(*a, **k) = [:put, a, k]
end
def via(box, *, **) = box.put(*, **)
def outer(*, **) = via(Box.new, *, **)
p outer
p outer(1, q: 2)
