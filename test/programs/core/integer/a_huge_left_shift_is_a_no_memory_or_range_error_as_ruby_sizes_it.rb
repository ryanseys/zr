# A left shift too wide for memory: CRuby refuses a count of 2**67 or
# more, and a result of LONG_MAX bytes or more, with a RangeError; below
# that it allocates the result's digits, and an allocator that cannot
# supply them raises NoMemoryError, which no `rescue => e` takes.
def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue StandardError, NoMemoryError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

try("1 << 2**60") { 1 << 2**60 }
try("1 << fixnum max") { 1 << (2**62 - 1) }
try("-5 << 2**61") { -5 << 2**61 }
try("256 >> -(2**61)") { 256 >> -(2**61) }
try("2**70 << 2**60") { (2**70) << 2**60 }
try("-(2**70) >> -(2**60)") { -(2**70) >> -(2**60) }

try("256 << 2**64") { 256 << 2**64 }
try("256 << 2**65") { 256 << 2**65 }
try("1 << 2**66 - 128") { 1 << (2**66 - 128) }
try("1 << 2**66 - 64") { 1 << (2**66 - 64) }
try("1 << 2**66") { 1 << 2**66 }
try("1 << 2**67 - 1") { 1 << (2**67 - 1) }
try("1 << 2**67") { 1 << 2**67 }
try("1 << 2**100") { 1 << 2**100 }
try("256 >> -(2**64)") { 256 >> -(2**64) }
try("256 >> -(2**100)") { 256 >> -(2**100) }
try("2**70 << 2**64") { (2**70) << 2**64 }
try("2**70 >> -(2**100)") { (2**70) >> -(2**100) }
try("send << 2**64") { 256.public_send(:<<, 2**64) }

# Shifts out to the right, and a zero, need no memory.
try("256 >> 2**64") { 256 >> 2**64 }
try("-256 >> 2**64") { -256 >> 2**64 }
try("256 << -(2**64)") { 256 << -(2**64) }
try("-(2**70) << -(2**100)") { -(2**70) << -(2**100) }
try("0 << 2**100") { 0 << 2**100 }
try("0 << 2**62") { 0 << 2**62 }
try("1 << 2**10 has bits") { (1 << 2**10).bit_length }

# The rescue list sees NoMemoryError, which is no StandardError, and
# goes on to the next entry.
def uncaught
  yield
rescue StandardError, nil => e # rubocop:disable Lint/RescueType
  puts "rescued #{e.class}"
end

begin
  uncaught { 256 << 2**64 }
rescue TypeError => e
  puts "#{e.class}: #{e.message}; cause #{e.cause.class}"
end
begin
  uncaught { 256 << 2**67 }
rescue TypeError => e
  puts "not reached: #{e.message}"
end
