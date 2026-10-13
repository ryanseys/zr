# A method that defines many methods on its own class while it runs grows
# that class's method table. Its frame still names it in a backtrace, and
# the frames of the methods around it do too: each keeps the entry of its
# time, as a CRuby frame keeps its method entry.
class Grower
  def grow(count)
    count.times { |i| Grower.define_method(:"m#{i}") { i } }
    # Fill the heap so that a freed table would hold other bytes.
    filler = Array.new(3000) { |i| ",#{i}" * (20 + (i % 600)) }
    raise "grown"
  rescue => e
    [filler&.size, e.backtrace_locations.map(&:label).first(3)]
  end

  def outer = grow(300)
end

p Grower.new.outer
p Grower.new.m299

# Methods of Object, as a spec runner's own `describe` is, while a block
# adds top-level methods.
def run_block = yield

p(run_block do
  200.times { |i| Object.send(:define_method, :"top#{i}") { i } }
  junk = Array.new(3000) { |i| ",#{i}" * (20 + (i % 600)) }
  begin
    raise ArgumentError, "after #{junk.size}"
  rescue => e
    e.backtrace_locations.map(&:label).first(3)
  end
end)
p top199

# A module function's singleton grows while its method runs.
module Counter
  module_function

  def run
    150.times { |i| Counter.define_singleton_method(:"c#{i}") { i } }
    Array.new(3000) { |i| ",#{i}" * (20 + (i % 600)) }
    caller_locations(0, 2).map(&:label)
  end
end
p Counter.run
p Counter.c149
