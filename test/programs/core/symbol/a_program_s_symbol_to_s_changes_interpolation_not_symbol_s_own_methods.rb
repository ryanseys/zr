# A Symbol#to_s that the program writes changes interpolation, format,
# join and String(), which call it, but not Symbol's own methods, which
# read the name as the core holds it.
class Symbol
  def to_s = "X"
end
def show(label)
  p [label, yield]
rescue => e
  p [label, e.class]
end
s = :hello
show(:name) { s.name }
show(:id2name) { s.id2name }
show(:inspect) { s.inspect }
show(:length) { s.length }
show(:size) { s.size }
show(:[]) { s[1] }
show(:upcase) { s.upcase }
show(:succ) { s.succ }
show(:start_with?) { s.start_with?("he") }
show(:end_with?) { s.end_with?("lo") }
show(:empty?) { s.empty? }
show(:=~) { s =~ /l+/ }
show(:match) { s.match(/l+/)&.[](0) }
show(:match?) { s.match?(/X/) }
show(:casecmp) { s.casecmp(:HELLO) }
show(:casecmp?) { s.casecmp?(:HELLO) }
show(:<=>) { s <=> :help }
show(:interp) { "#{s}" }
show(:to_proc) { %w[a].map(&:upcase) }
show(:encoding) { s.encoding }
show(:capitalize) { s.capitalize }
show(:swapcase) { s.swapcase }
show(:downcase) { :HeLLo.downcase }
show(:format) { format("%s", s) }
show(:join) { [s, s].join("-") }
show(:str_plus) { "a" + s.name }
show(:ivar) { Object.new.tap { _1.instance_variable_set(:@a, 1) }.instance_variables }
show(:send) { 1.send(:+, 2) }
show(:sym2str) { String(s) rescue $!.class }
show(:const) { Object.const_get(:String) }
show(:define) { Class.new { define_method(:hi) { 1 } }.new.hi }
show(:respond) { 1.respond_to?(:succ) }
show(:regexp_literal) { /(a|b)+c?d{2,3}/ =~ "xxabcdd" }
show(:struct) { Struct.new(:left, :right).new(1, 2).inspect }
show(:marshal) { Marshal.load(Marshal.dump([:a, { b: :c }])) }
