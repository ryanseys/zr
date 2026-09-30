# Guards the exception-handling push/pop discipline: three INDEPENDENT
# `begin` blocks in sequence, the last a bare re-raise with nothing
# currently being handled -- if an earlier block's handling state were
# ever left in place (e.g. on an unusual exit path), this would incorrectly
# re-raise a STALE exception instead of falling back to a fresh
# `RuntimeError`.

begin
  raise "first"
rescue => e
  puts "1: #{e.send(:message)}"
end
begin
  raise "second"
rescue => e
  puts "2: #{e.send(:message)}"
end
begin
  raise
rescue => e
  puts "3: [#{e.send(:message)}]"
end
