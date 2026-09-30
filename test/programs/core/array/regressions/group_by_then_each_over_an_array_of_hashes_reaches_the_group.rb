# Array#group_by, then Hash#each, on an array of Hashes with Symbol
# keys. group_by gives a Hash from each block result to an array of
# rows. In the each block, `rows.map`, `rows.sum` and `rows.size`
# all work on that array.
#
# Float interpolation shows 4.0 as "4.0", as Float#to_s does.

scores = [
  { shop: "ginza", score: 5 },
  { shop: "ginza", score: 4 },
  { shop: "shibuya", score: 3 },
  { shop: "shibuya", score: 5 }
]

scores.group_by { _1[:shop] }.each do |shop, rows|
  avg = rows.map { _1[:score] }.sum.to_f / rows.size
  puts "#{shop}: #{avg}"
end
