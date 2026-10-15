# Float#truncate floors or ceils in C, so an infinity or NaN raises
# FloatDomainError from truncate's own frame.
def labels(e) = e.backtrace_locations.map(&:label)
[-> { Float::INFINITY.truncate }, -> { (-Float::INFINITY).truncate }, -> { Float::NAN.truncate(1) }, -> { Float::INFINITY.floor }, -> { 1.5.truncate("x") }].each do |c|
  c.call
rescue => e
  p [e.class, e.message, labels(e).first(2)]
end
p 1.75.truncate(1), -1.75.truncate(1), 1.5.truncate, -1.5.truncate, 12.5.truncate(-1)
