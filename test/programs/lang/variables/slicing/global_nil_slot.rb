# A global whose only value is nil reads as nil. So does a global that no
# code assigns.
$foo = nil
p $foo.nil?
p $foo

# never assigned
p $never_written.nil?

# a later write sets the value: this one is an Integer
$n = nil
$n = 5
p $n
p $n + 1

# and a nil string global is nil, not the empty string, so `.nil?` answers
# true
$s = nil
p $s.nil?
$s = "x"
p $s.nil?
p $s

# read through a method
$log = nil
$log_dead = false

def live_write
  puts "no pipe" if $log.nil?
  puts "dead" if $log_dead
end

live_write
$log = "open"
live_write
p $log

# the underscore-prefixed spelling takes the same path
$_x = nil
p $_x.nil?
