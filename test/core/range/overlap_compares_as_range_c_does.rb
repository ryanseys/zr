pairs = [[0..2, 1..3], [0..2, 3..4], [0...3, 3..4], [0.., ..0], [..0, ..5], [..0, 1..], [5..1, 0..9], [1...1, 1..1], ["a".."c", "b".."z"], [1..2, "a".."b"], [nil..nil, 1..2], [(1..), (3..)], [1.0..2.5, 2.5..3]]
pairs.each { |a, b| p [a, b, a.overlap?(b), b.overlap?(a)] }
begin; (1..2).overlap?(3); rescue TypeError => e; p e.message; end
class R < Range; def begin = raise("begin"); def end = raise("end"); end
p R.new(1, 3).overlap?(R.new(2, 4))

__END__
[0..2, 1..3, true, true]
[0..2, 3..4, false, false]
[0...3, 3..4, false, false]
[0.., ..0, true, true]
[..0, ..5, true, true]
[..0, 1.., false, false]
[5..1, 0..9, false, false]
[1...1, 1..1, false, false]
["a".."c", "b".."z", true, true]
[1..2, "a".."b", false, false]
[nil..nil, 1..2, true, true]
[1.., 3.., true, true]
[1.0..2.5, 2.5..3, true, true]
"wrong argument type Integer (expected Range)"
true
