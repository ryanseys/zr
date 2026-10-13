# A fallback of String#encode that changes the size of the String being
# converted stops the conversion with RuntimeError "string modified": a
# Proc, a Hash's default block, a lambda, and encode!. A change that keeps
# the size goes on (ruby #22330).
def try(l) = (p [l, yield]) rescue p([l, $!.class, $!.message])
s = "あ" * 1000
try(:clear) { s.encode("US-ASCII", fallback: proc { |x| s.clear; "?" }) }
s = "aあb"
try(:append) { s.encode("US-ASCII", fallback: proc { |x| s << "z"; "?" }) }
s = "aあb"
try(:same_size) { s.encode("US-ASCII", fallback: proc { |x| s[0] = "q"; "?" }) }
s = "aあb"
try(:hash) { s.encode("US-ASCII", fallback: Hash.new { |h, k| s.clear; "?" }) }
s = "aあb"
try(:method) { s.encode("ISO-8859-1", fallback: ->(x) { s.replace("zz"); "?" }) }
s = "aあb"
try(:bang) { s.encode!("US-ASCII", fallback: proc { |x| s.clear; "?" }) }
try(:plain) { "aあb".encode("US-ASCII", fallback: proc { "[#{_1}]" }) }
s = "a\xffb".b
try(:binary) { s.encode("UTF-8", fallback: proc { |x| s.clear; "?" }) }
s = "あ".encode("EUC-JP")
try(:euc) { s.encode("ISO-8859-1", fallback: proc { |x| s.clear; "?" }) }
