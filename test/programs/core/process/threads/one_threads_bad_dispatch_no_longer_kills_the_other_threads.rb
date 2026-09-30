# A failing thread surfaces its error at its OWN join; the healthy worker
# completes normally, unaffected.

class Plain
end
worker = Thread.new { 21 * 2 }
bad = Thread.new { Plain.new.send(:missing_in_thread) }
begin
  bad.join
rescue NoMethodError => e
  puts "joined the failure"
end
puts worker.value
