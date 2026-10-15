# Enumerator.produce's each is a loop in C: an error in the walk shows
# Producer#each with no frame of loop, and a StopIteration ends it with
# its result.
def labels(e) = e.backtrace_locations.map(&:label)
begin; Enumerator.produce([]) { }.map(&:first); rescue NoMethodError => e; p labels(e); end
p Enumerator.produce(1) { |x| x < 4 ? x + 1 : raise(StopIteration) }.to_a
p Enumerator.produce { |x| (x || 0) + 1 }.take(3)
p Enumerator.produce(1) { |x| raise StopIteration.new("s") if x > 2; x + 1 }.each { |v| v }
it = Enumerator.produce(1) { |x| x * 2 }
p it.first(4), it.lazy.map { _1 + 1 }.first(2)
