# backtrace carries the real stamped frames; full_message renders the
# uncaught-report shape from them; inspect renders "#<Class: msg>" (or
# the bare class name when the message is empty). Expected output is
# verbatim ruby output (the harness compiles as `-e`, same as the
# oracle's own `-e` labeling).

begin
  raise ArgumentError, "bad"
rescue => e
  p e.backtrace
  p e.inspect
  puts e.full_message
end
p StandardError.new("").inspect
