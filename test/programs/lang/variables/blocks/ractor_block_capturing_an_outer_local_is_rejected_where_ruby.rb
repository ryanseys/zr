# Ruby's `Ractor::IsolationError`, raised by `Ractor.new` itself and catchable
# there, not a compile error. The verdict rides on
# the Proc value (`RProc::with_outer_capture`), so a literal block and a
# `&proc` argument reach the same raise.

x = 5
begin
  Ractor.new { x + 1 }
rescue => e
  puts "raised: #{e.class}: #{e.send(:message)}"
end
puts "still running"
