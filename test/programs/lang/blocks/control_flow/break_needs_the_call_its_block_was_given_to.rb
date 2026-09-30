# A `break` leaves the call its block was given to. Once that call has
# returned there is nothing to leave, even while the method the block was
# written in still runs, and the break is a LocalJumpError. A shareable
# Proc is cut off from its method, so neither `break` nor `return` has
# anywhere to go.
def make(&b) = b
def kept
  make { break 1 }.call
rescue LocalJumpError => e
  "kept: #{e.message} (#{e.reason}, #{e.exit_value.inspect})"
end
p kept

def through(&b) = b.call
p through { break 2 }
p [1, 2, 3].each { |x| break x * 10 if x == 2 }
def yielder = yield
p yielder { break 3 }
def forward(&b) = [1].map(&b)
p forward { break 4 }
p loop { break 5 }
p 3.times { break 6 }
def nested = [1].each { [2].each { break 9 }; break 10 }
p nested
p send(:yielder) { break 11 }
p 1.then { break 12 }

pr = proc { break 8 }
begin
  pr.call
rescue LocalJumpError => e
  puts "a proc: #{e.message}"
end

def m = yield
begin
  p m(&Ractor.shareable_proc { break 1 })
rescue LocalJumpError => e
  puts "a shareable break: #{e.message}"
end

def shareable_return
  Ractor.shareable_proc { return 1 }.call
  2
end
begin
  p shareable_return
rescue LocalJumpError => e
  puts "a shareable return: #{e.message}"
end

def plain_return
  pr = proc { return 1 }
  pr.call
  2
end
p plain_return
def kept_return
  make { return 3 }.call
  4
end
p kept_return

