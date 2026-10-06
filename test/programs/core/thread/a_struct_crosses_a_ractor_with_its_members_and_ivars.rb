Warning[:experimental] = false
S = Struct.new(:member) do
  def initialize(*)
    super
    @ivar = "ivar"
  end
  attr_reader :ivar
end
D = Data.define(:a, :b)
K = Struct.new(:x, :y, keyword_init: true)

obj = S.new("member")
copy = Ractor.new { Ractor.receive }.send(obj).value
p [copy.class, copy.member, copy.ivar, copy.member.equal?(obj.member), copy.ivar.equal?(obj.ivar)]

d = D.new(a: [1], b: "x")
p [Ractor.shareable?(d), d.frozen?]
dc = Ractor.new { Ractor.receive }.send(d).value
p [dc, dc.frozen?, dc.a.equal?(d.a), dc.a.frozen?]

s = D.new(a: 1, b: :x)
p [Ractor.shareable?(s), Ractor.new { Ractor.receive }.send(s).value.equal?(s)]

k = K.new(x: [1], y: 2)
kc = Ractor.new { Ractor.receive }.send(k).value
p [kc, kc.x.equal?(k.x)]

# A cycle through a struct member comes out a cycle.
c = S.new(nil)
c.member = c
cc = Ractor.new { Ractor.receive }.send(c).value
p [cc.member.equal?(cc), cc.equal?(c)]

# make_shareable freezes members.
m = Ractor.make_shareable(S.new([+"a"]))
p [m.frozen?, m.member.frozen?, m.member[0].frozen?, Ractor.shareable?(m)]
p Ractor.shareable?(S.new(1).freeze)
p Ractor.shareable?(S.new([1]).freeze)
p Ractor.shareable?(D.new(a: [1], b: 1))
md = Ractor.make_shareable(D.new(a: [+"q"], b: 1))
p [md.a.frozen?, md.a[0].frozen?, Ractor.shareable?(md)]

# copy: true makes a new graph.
cp = Ractor.make_shareable(S.new([+"z"]), copy: true)
p [cp.member, Ractor.shareable?(cp)]

# A move takes the struct away.
mv = K.new(x: [1, 2], y: 3)
got = Ractor.new { Ractor.receive }.send(mv, move: true).value
p got
begin
  mv.x
rescue Ractor::MovedError => e
  p e.class
end
