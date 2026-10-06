# expect, as ruby's pty extension ships it, reads a PTY child's prompt,
# answers it, and gives nil when the pattern never comes.
require "pty"
require "expect"
PTY.spawn("sh", "-c", "printf 'name? '; read n; echo hello $n") do |r, w, pid|
  p r.expect(/name\? /, 5)
  w.puts "zr"
  p r.expect(/hello \w+/, 5)&.first&.strip
  p r.expect(/never/, 0.2)
end

