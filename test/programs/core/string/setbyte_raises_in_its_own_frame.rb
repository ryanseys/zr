# String#setbyte raises IndexError and FrozenError from its own frame, so
# the backtrace starts at 'String#setbyte', as for a C method in ruby.
def labels(error) = error.backtrace_locations.first(2).map(&:label)

class Holder
  def initialize(text)
    @buf = text
    @buf.setbyte(0, 7)
  end
end

[-> { Holder.new("".b) }, -> { Holder.new("ab".freeze) }, -> { "ab".b.setbyte(-3, 1) }, -> { "ab".b.setbyte(2, 1) }].each do |code|
  code.call
rescue IndexError, FrozenError => e
  p [e.class, e.message, labels(e)]
end

s = +"ab"
p s.setbyte(-1, 0x7a), s.setbyte(0, 0x179), s
