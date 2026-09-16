# (a..b).to_a over two Integers is one fill, not a yield per element:
# the same Array either way, exclusive ends, empty and reversed ranges,
# entries, and a Range whose ends are not both fixnums still walks each.
p (1..5).to_a, (1...5).to_a, (5..1).to_a, (3...3).to_a, (-2..2).to_a, (0..0).to_a, (1..1).entries
p (1..100_000).to_a.sum, (1..100_000).to_a.size, (2**62..2**62 + 2).to_a, ((2**62 - 1)...(2**62 + 1)).to_a
p ("a".."e").to_a, (1.0..3.0).to_a rescue p $!.class
p ((1..).to_a rescue $!.class), (nil..3).to_a rescue p $!.class
class Range
  alias old_each each
  def each(&b)
    $walked = true
    old_each(&b)
  end
end
$walked = false
p (1..3).to_a, $walked
p Range.new(1, 3).to_a, (1..3).to_a.frozen?, (1..3).to_a.equal?((1..3).to_a)

__END__
[1, 2, 3, 4, 5]
[1, 2, 3, 4]
[]
[]
[-2, -1, 0, 1, 2]
[0]
[1]
5000050000
100000
[4611686018427387904, 4611686018427387905, 4611686018427387906]
[4611686018427387903, 4611686018427387904]
TypeError
TypeError
[1, 2, 3]
true
[1, 2, 3]
false
false
