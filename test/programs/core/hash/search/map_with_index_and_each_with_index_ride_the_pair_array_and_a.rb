# hash.map.with_index / hash.each.with_index iterate the [key, value]
# pairs. A block that ends in puts still runs puts for each pair.
h = { a: 1, b: 2 }
h.map.with_index { |(k, v), i| puts "#{i}:#{k}" }
h.each.with_index { |(k, v), i| puts "#{i}=#{v}" }
[10, 20].map.with_index { |v, i| puts "#{i}->#{v}" }
