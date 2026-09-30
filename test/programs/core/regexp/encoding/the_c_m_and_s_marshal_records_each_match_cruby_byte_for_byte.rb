# `/` (regexp source + option byte, `I`-wrapped for encoding), `c`/`m`
# (class/module reference), and `S` (Struct: class symbol, member count,
# member/value pairs).

def wire(x) = Marshal.dump(x).bytes.join(",")
def rt(x) = Marshal.load(Marshal.dump(x))
puts wire(/ab.c/im)
r = rt(/a\d+b/i)
puts r.source
puts r.options
puts wire(String)
p rt(String)
p rt(Comparable)
S = Struct.new(:a, :b)
puts wire(S.new(1, 2))
st = rt(S.new(10, "x"))
p [st.a, st.b]
