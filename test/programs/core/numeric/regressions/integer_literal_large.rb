mod = 4_294_967_296
puts mod
puts 16_777_621 % mod

hash = 2_166_136_261
data = "spinel"
i = 0
while i < data.length
  hash = (hash * 16_777_619 + data.getbyte(i)) % mod
  i += 1
end

puts hash
