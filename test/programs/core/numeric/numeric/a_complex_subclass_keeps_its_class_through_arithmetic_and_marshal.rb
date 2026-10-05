# Complex results are of the receiver's class (CLASS_OF(self)), and the
# private Complex.convert is Kernel#Complex for its receiver.
class CS < Complex; end
c = CS.send(:convert, 1)
p c.class, CS.send(:convert, 1, 2).class, CS.send(:convert, "1+2i").class
p((CS.send(:convert, nil) rescue $!.class))
%i[+ - * / quo fdiv **].each { |m| puts "#{m} #{c.send(m, 2).class} #{c.send(m, Complex(1, 1)).class}" }
p (-c).class, (+c).class, c.conj.class, c.to_c.class, c.coerce(2).map(&:class)
p CS.rect(1, 2).class, CS.polar(1, 2).class
p Marshal.load(Marshal.dump(c)).class, Marshal.load(Marshal.dump(c)) == c
p Complex(1, 2).class
