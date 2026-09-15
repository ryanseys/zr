e = (+"hello world").gsub!(1)
p e.class
class P < String; end
e2 = P.new("hello").gsub!("l")
p e2.class
p((+"hello").each_line.to_a)
begin; (+"a").replace(1); rescue TypeError => e; p e.message; end
begin; (+"a").replace(nil); rescue TypeError => e; p e.message; end
o = Object.new; def o.to_str = "conv"
p((+"a").replace(o))
p (+"abc").gsub!(/b/).to_a

__END__
Enumerator
Enumerator
["hello"]
"no implicit conversion of Integer into String"
"no implicit conversion of nil into String"
"conv"
["b"]
