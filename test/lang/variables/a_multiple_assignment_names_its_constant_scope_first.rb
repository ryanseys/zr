# A multiple assignment evaluates each target's receiver or scope
# before the right-hand side, and an attribute target through an
# explicit receiver may not reach a private writer.
def scope_for_it = (puts "scope"; Object)
scope_for_it::QB, c = (puts "value"; [1, 2])
p QB, c

class Opaque
  attr_reader :s

  private attr_writer :s

  def set_both = (self.s, @t = 1, 2; [s, @t])
end
begin
  Opaque.new.s, c = 1, 2
  p :called
rescue NoMethodError => e
  p e.message
end
p Opaque.new.set_both

__END__
scope
value
1
2
"private method 's=' called for an instance of Opaque"
[1, 2]
