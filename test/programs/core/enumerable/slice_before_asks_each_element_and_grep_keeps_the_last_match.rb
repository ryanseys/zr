# slice_before asks its pattern about every element, the first one too;
# grep with a Regexp and no block matches Symbols and to_str values
# without touching $~, and no other element matches.
seq = [false, true, false, false, false, true, false]
arg = Object.new; arg.define_singleton_method(:===) { |_| seq.shift }
p [7, 6, 5, 4, 3, 2, 1].slice_before(arg).to_a
calls = []
p [1, 2, 3].slice_before { |x| calls << x; x == 2 }.to_a, calls
p [:a, 'b', 'z', :c, 42, nil].grep(/[a-d]/), $~
o = Object.new; def o.to_str = 'hello'
p [o].grep(/ll/).first.equal?(o), [o].grep_v(/zz/).size
t = Object.new; def t.to_ary = [:a, :b]
n = Object.new; def n.to_ary = nil
p [1, t, 2].flat_map { _1 }, [n].flat_map { _1 }.size
'set last match' =~ /set last (.*)/
p [:a, 'b', 'z', :c, 42, nil].grep(/[a-d]/)
p $1
'set last match' =~ /set last (.*)/
p [:a, 'b', 'z', :c, 42, nil].grep_v(/[a-d]/)
p $1
['ab'].grep(/(b)/) { p $1 }
p $1
p [BasicObject.new, "a"].grep_v(/a/).size, [BasicObject.new].grep(/a/)
