# Symbol#inspect gives the symbol with its `:` prefix, for a literal and
# for a local.
puts :hello.inspect          # :hello

sym = :world
puts sym.inspect             # :world

puts "done"
