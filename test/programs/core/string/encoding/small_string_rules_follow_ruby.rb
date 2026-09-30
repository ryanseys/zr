# Small String rules, each as ruby answers it.
def t = yield rescue [$!.class, $!.message]

o = Object.new
def o.to_str = "x"
def o.==(v) = (p [:asked, v]; true)
S = Class.new(String)

p t { s = +"aaabbb"; s.squeeze!("a"); s }, t { (+"a").prepend(1) }, t { "lit".freeze.send(:initialize, "x") }
p t { "x" == o }, t { (+"a".encode("US-ASCII")).append_as_bytes("b").encoding }, t { ["ab"].pack("H*").unpack1("H*").encoding }
p t { r = []; "abc".unpack("C*") { r << _1 }.inspect + r.inspect }, t { ["a\t"].pack("M") }, t { [1].pack("m") }
p t { q = S.new("zzq").freeze; (-q).class }, t { (-"zzq".dup).class }, t { ({S.new("a") => 1}).keys[0].class }

