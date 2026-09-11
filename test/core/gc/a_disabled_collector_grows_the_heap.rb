# While GC.disable holds, the heap grows instead of collecting when its
# cells run out, so GC.count does not move; GC.enable lets it collect
# again.
p GC.disable
before = GC.count
kept = Array.new(300_000) { Object.new }
p GC.count == before, kept.size
p GC.disable
p GC.enable, GC.enable
GC.start
p GC.count > before

__END__
false
true
300000
true
true
false
true
