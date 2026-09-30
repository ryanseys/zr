# A String's `I`-wrapper carries its encoding -- `E => true` (UTF-8),
# `E => false` (US-ASCII), `encoding => "<name>"` (other), and NO wrapper
# for ASCII-8BIT. The encoding survives a round-trip.

def wire(x) = Marshal.dump(x).bytes.join(",")
def rt(x) = Marshal.load(Marshal.dump(x))
puts wire("abc")
puts wire("abc".b)
puts wire("abc".encode("US-ASCII"))
puts wire("café")
puts wire("abc".encode("Shift_JIS"))
puts rt("café").encoding.name
puts rt("abc".b).encoding.name
puts rt("abc".encode("Shift_JIS")).encoding.name
puts rt("hello")
