# A `return` in a block inside `class << self` leaves the method that
# holds the body, also when the block runs through a method call and not
# inline.
def a = (class << self; 2.tap { return :tapped }; end; :outer)
p a
def b = (class << self; [1].map { |x| return x + 1 }; end; :outer)
p b
def c = (class << self; [1].each { |x| [x].each { return :deep } }; end; :outer)
p c
pr = proc { class << self; 3.tap { return 3 }; end }
begin
  pr.call
rescue LocalJumpError => e
  p [e.message, e.reason, e.exit_value]
end
