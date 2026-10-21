# expect, as ruby's pty extension ships it, reads a PTY child's prompt,
# answers it, and gives nil when the pattern never comes. On Linux the
# read past the child's exit fails with EIO instead.
require "pty"
require "expect"
PTY.spawn("sh", "-c", "printf 'name? '; read n; echo hello $n") do |r, w, pid|
  p r.expect(/name\? /, 5)
  w.puts "zr"
  p r.expect(/hello \w+/, 5)&.first&.strip
  begin
    p r.expect(/never/, 0.2)
  rescue Errno::EIO => e
    p e.class
  end
end

