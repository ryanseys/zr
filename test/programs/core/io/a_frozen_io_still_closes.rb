# IO#close checks no freeze, so a frozen stream closes. Other changes to
# a frozen stream raise FrozenError.
file = File.open(__FILE__)
copy = file.dup.freeze
p copy.frozen?, copy.close, copy.closed?
p file.closed?, file.gets.class
p((file.dup.freeze.binmode rescue $!.class))
file.close
r, w = IO.pipe
w.freeze
p w.close, w.closed?
r.close
