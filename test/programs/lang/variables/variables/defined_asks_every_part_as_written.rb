# `defined?` asks about each part as it is written. A call with any
# receiver, `self` among them, is asked as an explicit call, so a private
# method -- a private writer too -- is not there; a writer that is, is a
# "method". An Array or a Hash literal is defined only when every part of
# it is, and parentheses ask about what they hold.
class K
  def pub = 1

  def run
    [defined?(self.priv), defined?(priv), defined?(self.prot), defined?(prot), defined?(self.w = 1), defined?(self.pw = 1),
     defined?(K.new.prot), defined?(K.new.priv), defined?(self.pub), defined?(self[1] = 2)]
  end

  def w=(v); end
  def []=(k, v); end

  private

  def priv = 1
  def pw=(v); end

  protected

  def prot = 1
end
p K.new.run

o = K.new
p defined?(o.w = 1), defined?(o[1] = 2), defined?(o.pw = 1), defined?(o.zz = 1)
p defined?([1, [2, Nope]]), defined?([1, [2, Array]]), defined?([]), defined?([@zz]), defined?([$zzz]), defined?([nope_m])
p defined?(1.+(Nope)), defined?(puts(Nope)), defined?(String.new(Array))
a = [1]
p defined?([*a])
p defined?({a: 1}), defined?({a: Nope}), defined?({Nope => 1}), defined?({**Nope}), defined?({a: nope_m})
x = 1
p defined?([{a: Nope}]), defined?({x:}), defined?([{**{b: 1}}]), defined?({a: [Nope]})
p defined?("#{Nope}"), defined?(1..Nope), defined?(!Nope), defined?(Nope && 1), defined?((Nope)), defined?((String))
p defined?(x = Nope), defined?(@a ||= 1), defined?((c, d = 1, 2))

