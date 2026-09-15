# An object's hash comes from its object_id, which the first hash hands
# out, as CRuby's objid_hash does: an object put in a Hash takes the next
# id, and the next object_id asked for counts past it.
h = {Object.new => 1}
p Object.new.object_id
s = Object.new
p s.hash == s.hash, {s => 2}[s], [s].uniq.size, s.object_id

__END__
24
true
2
1
32
