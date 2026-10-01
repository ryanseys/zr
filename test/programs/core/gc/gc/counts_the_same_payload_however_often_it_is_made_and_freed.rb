# The bytes the heap counts against its malloc trigger must not
# drift as the same buffers are made and freed. A count that falls
# a little on every round pushes the next collection further away
# every time, until the trigger stops firing at all.

def payload = GC.stat(:malloc_increase_bytes)

def churn
  rows = Array.new(1_000) { |i| { "k#{i}" => "v#{i}" * 20, i => [i] * 40 } }
  rows.clear
  GC.start
  GC.start
  payload
end

churn
first = churn
last = nil
5.times { last = churn }
puts (last - first).abs < 16_384
