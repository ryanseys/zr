# rb_struct_s_members reads the row the class holds, so a member is
# bound by what `Struct.new` was given and never by a `members` the
# class or the instance went on to define. Data reads its own row the
# same way. What each of those methods answers is still theirs.
Row = Struct.new(:a, :b) do
  def self.members = [:zzz, :yyy, :xxx]
  def members = [:only_mine]
end
r = Row.new(1, 2)
p r.to_a, r.size, [r.a, r.b]
p Row.members, r.members
p r.each.to_a, r.deconstruct_keys(nil), r.dig(:a), r.inspect
p Row.allocate.to_a
Kw = Struct.new(:a, :b, keyword_init: true) do
  def self.members = [:zzz]
end
p Kw.new(a: 1, b: 2).to_a
Pair = Data.define(:a, :b) do
  def self.members = [:zzz, :yyy, :xxx]
end
q = Pair.new(a: 1, b: 2)
p q.to_h, q.members, Pair.members
p q.deconstruct_keys(nil), q.deconstruct_keys([:a])
p q.inspect, q.with(b: 9).to_h, q == Pair.new(a: 1, b: 2)
