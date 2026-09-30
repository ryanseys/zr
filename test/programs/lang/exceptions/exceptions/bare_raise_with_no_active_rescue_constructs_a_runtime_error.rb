# Bare `raise` (re-raise) outside any active `rescue` clause -- real
# Ruby constructs a fresh `RuntimeError` with an EMPTY message rather
# than erroring (oracle-verified: `ruby -e 'begin; raise; rescue => e;
# puts "[#{e.message}]"; end'` -> `"[]"`).

begin
  raise
rescue => e
  puts "[#{e.message}]"
end
