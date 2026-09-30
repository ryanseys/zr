# The port model relays the failure as CRuby does: a
# `Ractor::RemoteError` whose `#cause` is the original exception.

bad = Ractor.new do
  raise "ractor boom"
end
begin
  bad.value
rescue Ractor::RemoteError => e
  puts "rescued: #{e.send(:message)} / #{e.cause.class} / #{e.cause.send(:message)}"
end
