puts (1..Float::INFINITY).lazy.select { |x| x.odd? }.first(5).inspect
puts (1..Float::INFINITY).lazy.select { |x| x % 3 == 0 }.first(4).inspect
puts (1..Float::INFINITY).lazy.reject { |x| x.even? }.first(5).inspect
puts (1..Float::INFINITY).lazy.first(3).inspect
puts (10..Float::INFINITY).lazy.select { |x| x.even? }.first(3).inspect
puts (1..100).lazy.select { |x| x % 7 == 0 }.first(3).inspect
puts (1..Float::INFINITY).lazy.select { |x| x > 5 }.first
