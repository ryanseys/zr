# &:name calls only public methods. Hash#to_proc is a lambda of one
# argument. Integer#pow refuses a nil modulus, and << refuses a bignum.
class Pp
  def initialize = @a = []
  public def pub = @a << :pub
  protected def pro = @a << :pro
  private def pri = @a << :pri
end
o = Pp.new
p o.tap(&:pub).class
p((o.tap(&:pro) rescue $!.message[/\w+ method '\w+'/]), (o.tap(&:pri) rescue $!.message[/\w+ method '\w+'/]))
p [o].map(&:pub).size
pr = { a: 1 }.to_proc
p pr.arity, pr.parameters, pr.lambda?, pr.source_location, pr.call(:a)
p((2.pow(5, nil) rescue $!.class), (2.pow(5, "12") rescue $!.class), 2.pow(5), 2.pow(5, 7))
p(("" << -2**70 rescue $!), ("" << 2**70 rescue $!), (+"".concat(-2**70) rescue $!))
