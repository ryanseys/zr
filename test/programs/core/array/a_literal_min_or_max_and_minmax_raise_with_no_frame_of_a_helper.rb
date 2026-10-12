# A literal's min or max (opt_newarray_send) runs with no frame, and
# Array#minmax runs rb_ary_min and rb_ary_max with none of their own, so
# a failed comparison shows only the frames that ruby shows.
def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue StandardError => e
  frames = e.backtrace_locations.map(&:label).take_while { |l| !l.start_with?("block") }
  puts "#{label}: #{e.class}: #{e.message} #{frames.inspect}"
end

x = "a"
o = Object.new
try("[1, x].max") { [1, x].max }
try("[1, x].min") { [1, x].min }
try("[3, 1, x].max") { [3, 1, x].max }
try("[1.5, x].max") { [1.5, x].max }
try("[x, 1].max") { [x, 1].max }
try("[o, o].min") { [o, o].min.equal?(o) }
try("[1, 2, x].min") { [1, 2, x].min }
try("[1, x].minmax") { [1, x].minmax }
try("[x, 1].minmax") { [x, 1].minmax }
try("a.minmax") { a = [3, x]; a.minmax }
try("a.max") { a = [1, x]; a.max }
try("[1, x].max(1)") { [1, x].max(1) }
try("[3, 1, 2].minmax") { [3, 1, 2].minmax }
try("[].minmax") { [].minmax }
try("[5].minmax") { [5].minmax }
try("[2, 1].minmax {}") { [2, 1].minmax { |a, b| b <=> a } }
try("[1, 9, 4].max") { [1, 9, 4].max }
try("[1, 9, 4].min") { [1, 9, 4].min }
try("['b', 'a'].minmax") { %w[b a c].minmax }
class Counted
  include Comparable
  attr_reader :v

  @calls = 0
  class << self
    attr_accessor :calls
  end

  def initialize(v) = @v = v

  def <=>(other)
    Counted.calls += 1
    v <=> other.v
  end
end
items = [3, 1, 2].map { Counted.new(_1) }
try("minmax of Comparable") { items.minmax.map(&:v) }
try("<=> calls") { Counted.calls }
