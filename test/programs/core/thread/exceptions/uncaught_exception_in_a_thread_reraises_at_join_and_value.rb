# CRuby stores the exception and re-raises it in whoever joins
# (`thread.c:1195`). The no-join report_on_exception stderr warning is
# a documented skip.

bad = Thread.new { raise "thread boom" }
begin
  bad.join
rescue RuntimeError => e
  puts "joined error: #{e.send(:message)}"
end
bad2 = Thread.new { raise "thread boom2" }
begin
  bad2.value
rescue RuntimeError => e
  puts "valued error: #{e.send(:message)}"
end
