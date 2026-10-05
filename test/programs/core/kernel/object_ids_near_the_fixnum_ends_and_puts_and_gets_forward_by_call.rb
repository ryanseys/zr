# object_id leaves the fixnum range near its ends. Kernel#puts calls
# $stdout's own puts, or its write when $stdout is the receiver;
# Kernel#gets calls ARGF's own gets.
p (-1).object_id == (2**62 - 1).object_id, (2**62 - 1).object_id, (-2**62).object_id
m = Object.new
def m.write(*a) = STDOUT.write(*a)
def m.puts(*a) = STDOUT.write("P:#{a}\n")
$stdout = m
puts "hi"
$stdout = STDOUT
o = Object.new
def o.write(*a) = STDOUT.write(*a)
$stdout = o
puts "plain"
$stdout = STDOUT
def ARGF.gets(*) = "spec"
p gets
