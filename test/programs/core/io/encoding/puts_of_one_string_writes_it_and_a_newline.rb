# puts with one String argument writes its bytes and a newline unless
# it ends in one, into the same buffer the other forms fill, so the
# output keeps its order across puts, print, write and $stdout swaps.
$stdout.puts "one"
puts "two\n"
puts ""
print "three"
puts "four"
$stdout.write("five", "\n")
puts "six", "seven"
puts ["eight", ["nine"]], nil, 10, :eleven
puts "twelve\n\n"
puts "thirteen".encode("UTF-16LE").force_encoding("BINARY").bytesize
puts "héllo", "日本".encode("Shift_JIS").force_encoding("BINARY").bytes.size
class Quiet
  def write(*parts) = ($seen ||= []) << parts.join
end
old = $stdout
$stdout = Quiet.new
puts "fourteen"
puts "fifteen\n"
$stdout = old
p $seen
r, w = IO.pipe
w.sync = false
w.puts "sixteen"
w.puts "seventeen\n"
w.puts ""
w.flush
w.close
p r.read
s = String.new("mutable")
puts s
s << "!"
puts s
p (STDOUT.puts("x".freeze)), $stdout.puts
STDERR.puts "eighteen"

