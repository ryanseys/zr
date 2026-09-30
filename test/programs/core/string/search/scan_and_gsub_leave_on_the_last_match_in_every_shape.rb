text = "one 1, two 22, three 333"
# No block: the whole matches, then the groups; $~ is the last match.
p text.scan(/\d+/)
p [$~[0], $~.pre_match.size, $~.post_match]
p text.scan(/(\w+) (\d+)/)
p [$~[1], $~[2], $~.begin(2), $~.captures, $~.size]
p text.scan(/(\w+) (x)?(\d)/)
p $~.to_a
# A String pattern, an empty match, and no match at all: $~ follows.
p text.scan("e")
p [$~[0], $~.begin(0)]
p "aXbX".scan(/X?/)
p [$~[0], $~.begin(0)]
p text.scan(/zzz/)
p $~
p text.scan(/\d+/) { |d| }
p $~[0]
# With a block, $~ is each match in turn, and the answer is the receiver.
seen = []
r = text.scan(/(\w+) (\d+)/) { |w, d| seen << [w, d, $~.begin(0), $~[2]] }
p seen
p r.equal?(text)
"zzz".scan(/q/) { }
p $~
# gsub with a block and with a Hash: $~ inside, and after.
p text.gsub(/\d+/) { |d| "#{$~.begin(0)}:#{d.size}" }
p [$~[0], $~.begin(0)]
p text.gsub(/(\w+) (\d+)/, '\2-\1')
p $~[1]
p "héllo wörld".scan(/\w+/)
p "héllo wörld".scan(/./).size
p "aaa".scan(/a*/)
p "abc".scan(/(?<x>b)/)
p [$~[:x], $~.names]
p "x".scan(/y/).frozen?
