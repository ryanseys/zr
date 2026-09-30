# Struct method surface
S = Struct.new(:a, :b, :c)
p(S[10, 20, 30])                 # Struct.[]
s = S.new(1, 2, 3)
s[-1] = 99                       # []= negative index
p(s.c)
p(s.entries)
s.reverse_each { |x| print x }; puts
r = s.each_with_index { |x, i| }       # returns receiver
p(r == s)
p(s.compact)
S2 = Struct.new(:a, keyword_init: true)
p(S2.keyword_init?)
p(S.keyword_init?)
p(s.chain([4, 5]).to_a)
t = S.new(1, 1, 2)
p(t.slice_before { |x| x == 1 }.to_a)
p(t.slice_after { |x| x == 1 }.to_a)
e = s.each_entry                 # blockless -> Enumerator
p(e.to_a)
require "set"
p(s.to_set)
