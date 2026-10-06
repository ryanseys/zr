# GC.stat has Symbol keys and no "str_count" entry, as in CRuby. So
# g["str_count"] is nil, and `>=` on nil raises NoMethodError.

arr = []
i = 0
while i < 1000
  arr.push(i.to_s)
  i += 1
end
g = GC.stat
puts "str_count >= 1000: " + (g["str_count"] >= 1000 ? "yes" : "no")
puts "str_bytes > 0: " + (g["str_bytes"] > 0 ? "yes" : "no")
puts "retained: " + arr.length.to_s
