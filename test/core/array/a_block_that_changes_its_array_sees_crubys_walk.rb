# A block that grows, shrinks, replaces or freezes the Array it runs
# over sees each element where CRuby's walk has it: select!, reject!,
# delete_if and keep_if keep the Array's length until the walk ends,
# then cut it to what was kept; uniq! keys with its block; sort! works
# on a copy.
a = [3, 1, 2]; a.sort! { |x, y| a << 9 if a.size < 4; x <=> y }; p a
a = [3, 1, 2]; a.sort! { |x, y| a.pop if a.size > 1; x <=> y }; p a
a = [3, 1, 2]; a.sort_by! { |x| a << 9 if a.size < 4; x }; p a
a = [3, 1, 2]; a.sort_by! { |x| a.clear; x }; p a
a = [1, 2, 3]; a.map! { |x| a << 9 if a.size < 5; x * 2 }; p a
a = [1, 2, 3, 4]; a.map! { |x| a.pop; x * 2 }; p a
a = [1, 2, 3, 4]; a.select! { |x| a.pop if x == 1; x.odd? }; p a
a = [1, 2, 3, 4]; a.reject! { |x| a << 5 if a.size < 6; x.even? }; p a
a = [1, 2, 3, 4]; a.keep_if { |x| a.shift if x == 2; true }; p a
a = [1, 1, 2, 3]; a.uniq! { |x| a << 7 if a.size < 6; x }; p a
a = [0, 0, 0]; a.fill { |i| a << 1 if a.size < 5; i }; p a
a = [5, 4, 3, 2, 1]; a.sort! { |x, y| a.replace([9, 9]) if a.size == 5; x <=> y }; p a
a = [3, 1, 2]; b = a.sort { |x, y| a << 9 if a.size < 5; x <=> y }; p a, b
a = [1, 2, 3, 4, 5]; begin; a.reject! { |x| raise "no" if x == 3; x.even? }; rescue => e; p e.message; end; p a
a = [1, 2, 3, 4, 5]; a.delete_if { |x| break if x == 4; x.odd? }; p a
a = [1, -1, 2, -2, 3]; p a.uniq!(&:abs), a, [5].uniq!, [1, 2].uniq!
a = [1, 2, 3]; p a.select! { true }, a.reject! { false }, a.keep_if { true }, a.filter! { _1 > 1 }, a
__END__
[1, 2, 3]
[1, 2, 3]
[1, 2, 3, 9]
[3]
[2, 4, 6, 18, 18]
[2, 4]
[1, 3]
[1, 3, 5, 5]
[2, 3, 4]
[1, 2, 3, 7]
[0, 1, 2, 1, 1]
[1, 2, 3, 4, 5]
[3, 1, 2, 9, 9]
[1, 2, 3]
"no"
[1, 3, 4, 5]
[2, 4, 5]
[1, 2, 3]
[1, 2, 3]
nil
nil
nil
nil
[2, 3]
[2, 3]
[2, 3]
