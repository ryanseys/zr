# A corpus of `should be true` expressions. Each line is an
# independent equality predicate, and CRuby returns true for all
# twelve.

p ({} == {})                                     # 01
p ({a: 1} == {a: 1})                             # 02
p ({:a= => 1} == {:"a=" => 1})                   # 03
p ({:a! => 1} == {:"a!" => 1})                   # 04
p ({:a? => 1} == {:"a?" => 1})                   # 05
a = [1] ; a.shift ; a << :foo ; p (a == [:foo])  # 06
p ([42, { foo: :bar }].dig(1, :foo) == :bar)     # 07
a2 = [1, 2, 3, 4, 5] ; p ((a2[2, 3] = 10) == 10) # 08
p ("hello".chars == ['h', 'e', 'l', 'l', 'o'])   # 09
p "abc\r\n".chomp(nil) == "abc\r\n"              # 10
p ((/(.)(.)(.)/ =~ "abc") == 0)                  # 11
p ((1..).send(:include?, 2.4) == true)           # 12
