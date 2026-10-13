# Kernel#caller, #caller_locations, Thread#backtrace and
# Thread#backtrace_locations read the level and the size as C longs
# (NUM2LONG): a Float is cut, an object converts with to_int, and a
# negative one raises ArgumentError.
$stdout.sync = true
class Two
  def to_int = 2
end

def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

def rows = yield

rows do
  rows do
    try(:float) { caller(1.9, 1.2) == caller(1, 1) }
    try(:to_int) { caller(Two.new, Two.new) == caller(2, 2) }
    try(:locations_float) { caller_locations(1.9, 1.2).map(&:to_s) == caller_locations(1, 1).map(&:to_s) }
    try(:locations_to_int) { caller_locations(Two.new).size == caller_locations(2).size }
    try(:backtrace_float) { Thread.current.backtrace(1.1, 1.1) == Thread.current.backtrace(1, 1) }
    try(:backtrace_range) { Thread.current.backtrace(1.1..1.1) == Thread.current.backtrace(1..1) }
    try(:backtrace_locations_float) { Thread.current.backtrace_locations(1.1, 1.1).map(&:to_s) == Thread.current.backtrace_locations(1, 1).map(&:to_s) }
    try(:negative_level) { caller(-1) }
    try(:negative_float) { caller(-1.5) }
    try(:negative_size) { caller(0, -1) }
    try(:backtrace_negative) { Thread.current.backtrace(-1) }
    try(:locations_negative) { Thread.current.backtrace_locations(-1) }
    try(:locations_negative_size) { Thread.current.backtrace_locations(0, -1) }
    try(:string) { caller("1") }
    try(:nil_level) { caller(nil) }
    try(:nil_size) { caller(0, nil).size == caller(0).size }
    try(:huge) { caller(2**70) }
    try(:past_end) { caller(1000) }
    try(:zero_size) { caller(0, 0) }
  end
end
