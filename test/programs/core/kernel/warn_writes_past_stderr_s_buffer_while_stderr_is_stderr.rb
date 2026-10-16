# While $stderr is STDERR, warn writes its bytes to descriptor 2 at once,
# as rb_write_error_str's fwrite to C's stderr does: past what STDERR
# itself still buffers. Any other $stderr gets the text through `write`,
# and what that `write` raises passes up through warn.
class Collect
  attr_reader :parts

  def initialize = @parts = []
  def write(*texts) = @parts.concat(texts) && texts.sum(&:bytesize)
end

class Refuse
  def write(*) = raise(IOError, "refused")
end

saved = $stderr
$stderr = Collect.new
warn "kept"
Warning.warn("kept by Warning.warn\n")
warn "two", "lines"
collected = $stderr.parts
$stderr = saved
p collected

$stderr = Refuse.new
begin
  warn "lost"
rescue IOError => e
  $stderr = saved
  puts "warn passed up #{e.message}"
end
$stderr = saved

$stderr.reopen($stdout)
$stdout.write("a")
warn "w"
$stdout.write("b")
$stderr.write("e")
Warning.warn("w2\n")
$stdout.write("c\n")
warn "w3", uplevel: 0
$stdout.write("d" * 70_000)
puts
throw :nowhere
