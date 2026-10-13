# ruby 4.1: Symbol#to_s returns the symbol's one frozen name String, the
# same object each time, and name and id2name are its aliases. A change
# to it raises FrozenError; there is no "will be frozen" warning.
$VERBOSE = true
Warning[:deprecated] = true

s = :abc.to_s
p s, s.frozen?, s.equal?(:abc.to_s), s.equal?(:abc.name), s.equal?(:abc.id2name)
p s.encoding, :"é".to_s.encoding, :"é".to_s.frozen?
p s.equal?(-"abc"), s == "abc"
p :abc.method(:name) == :abc.method(:to_s), :abc.method(:id2name).unbind == Symbol.instance_method(:to_s)
p Symbol.instance_method(:name).original_name, Symbol.instance_method(:id2name).original_name

begin
  s << "d"
rescue FrozenError => e
  p e.message, e.receiver.equal?(s)
end
begin
  :abc.to_s.upcase!
rescue => e
  p e.class
end

# A copy, an interpolation and a + are fresh, unfrozen Strings.
d = s.dup
d << "d"
p d, s
p "#{:abc}".frozen?, (:abc.to_s + "").frozen?, :abc.to_s.+@.frozen?
p :abc.to_s.clone.frozen?, :abc.to_s.clone(freeze: false).frozen?

# The same holds for an operator, a setter and a dynamic symbol.
p %i[+ []= foo? @iv $gv].map { |sym| [sym.to_s, sym.to_s.frozen?] }
p "dyn#{1}".to_sym.to_s.frozen?

# A singleton method on the name is refused, as on any frozen String.
begin
  def s.extra = 1
rescue => e
  p e.class
end

# A redefined to_s changes interpolation, not the core's own reads.
class Symbol
  alias plain_to_s to_s
  def to_s = "<#{plain_to_s}>"
end
p "#{:x}", :x.inspect, :x.name, :x.length
