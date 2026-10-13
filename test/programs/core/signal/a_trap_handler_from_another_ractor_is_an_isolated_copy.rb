# The main ractor runs every trap handler. So a Proc that another ractor
# gives to Signal.trap is isolated first: the copy reaches no outer local,
# its self is nil, and the ractor's own Proc does not change.
Warning[:experimental] = false

def outcome
  yield
rescue => e
  [e.class, e.message]
end

# A block that reads an outer local cannot be isolated.
p(Ractor.new do
  count = 1
  outcome { Signal.trap(:USR1) { count } }
end.value)

# A block that uses the method's block cannot be isolated either.
p(Ractor.new do
  k = Class.new { def arm = Signal.trap(:USR1) { yield } }
  outcome { k.new.arm { 1 } }
end.value)

# A refusal installs nothing.
p Signal.trap(:USR1, "DEFAULT")

# The handler runs in the main ractor with nil as self.
p(Ractor.new do
  Signal.trap(:USR1) { puts "handler self: #{self.inspect}, main: #{Ractor.current == Ractor.main}" }
end.value)
Process.kill(:USR1, Process.pid)
sleep 0.1
Signal.trap(:USR1, "DEFAULT")

# trap keeps a copy, not the ractor's Proc. The copy is shareable but
# not frozen, and it keeps the class and the kind of the Proc.
class Handler < Proc; end
p(Ractor.new do
  given = proc { self }
  Signal.trap(:USR2, given)
  kept = Signal.trap(:USR2, "DEFAULT")
  [kept.equal?(given), kept.class, kept.call, given.call.class, kept.frozen?, Ractor.shareable?(kept)]
end.value)
p(Ractor.new do
  given = Handler.new { :handler }
  Signal.trap(:USR2, given)
  kept = Signal.trap(:USR2, "DEFAULT")
  [kept.class, kept.call]
end.value)
p(Ractor.new do
  given = lambda { |x| x * 2 }
  Signal.trap(:USR2, given)
  kept = Signal.trap(:USR2, "DEFAULT")
  [kept.equal?(given), kept.lambda?, kept.call(21)]
end.value)

# A Method's or a Symbol's Proc is copied too, and keeps what it calls.
p(Ractor.new do
  given = 1.method(:+).to_proc
  Signal.trap(:USR2, given)
  kept = Signal.trap(:USR2, "DEFAULT")
  [kept.equal?(given), kept.call(2), kept.lambda?, kept.frozen?, Ractor.shareable?(kept), kept.binding.class]
end.value)
p(Ractor.new do
  given = :upcase.to_proc
  Signal.trap(:USR2, given)
  kept = Signal.trap(:USR2, "DEFAULT")
  [kept.equal?(given), kept.call("a"), kept.frozen?, Ractor.shareable?(kept)]
end.value)

# The copy takes no instance variable, and its dup is shareable too.
p(Ractor.new do
  Signal.trap(:USR2) { :x }
  kept = Signal.trap(:USR2, "DEFAULT")
  [outcome { kept.instance_variable_set(:@a, 1) }, Ractor.shareable?(kept.dup), kept.dup.frozen?, kept.clone.frozen?]
end.value)

# The copy leaves the Proc's instance variables behind.
p(Ractor.new do
  given = proc { :x }
  given.instance_variable_set(:@note, 1)
  Signal.trap(:USR2, given)
  kept = Signal.trap(:USR2, "DEFAULT")
  [kept.instance_variables, given.instance_variables]
end.value)

# Any copy of a shareable Proc is shareable, frozen or not.
shared = Ractor.shareable_proc { :shared }
p [Ractor.shareable?(shared.dup), shared.dup.frozen?, Ractor.shareable?(shared.clone), shared.clone.frozen?]
p Ractor.shareable?(proc { :plain }.dup)

# A shareable Proc is kept as it is.
p(Ractor.new do
  given = Ractor.shareable_proc { :shared }
  Signal.trap(:USR2, given)
  kept = Signal.trap(:USR2, "DEFAULT")
  [kept.equal?(given), kept.call]
end.value)

# The isolated copy has no Binding.
p(Ractor.new do
  Signal.trap(:USR2) { :x }
  kept = Signal.trap(:USR2, "DEFAULT")
  outcome { kept.binding }
end.value)

# In the main ractor, trap keeps the Proc itself.
given = proc { self }
Signal.trap(:USR2, given)
kept = Signal.trap(:USR2, "DEFAULT")
p [kept.equal?(given), kept.call == self]

# A String command needs no isolation.
p(Ractor.new do
  Signal.trap(:USR2, "p :command")
  Signal.trap(:USR2, "DEFAULT")
end.value)
