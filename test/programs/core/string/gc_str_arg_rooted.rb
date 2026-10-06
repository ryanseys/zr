# String#bytes and String#codepoints make a new array before they read the
# receiver. The receiver here is a new interpolation result. A GC at that
# point does not free it, so the result is complete (a Doom port reads
# its Colormap rows this way).
total = 0
lens = 0
keep = []
200.times do |i|
  n = 3000 + (i % 7) * 500
  b = "row#{i}-#{'x' * n}".bytes
  total += b.sum
  lens += b.length
  keep << b if i % 10 == 0
end
puts total
puts lens

cps = 0
clen = 0
200.times do |i|
  n = 2000 + (i % 5) * 700
  c = "cp#{i}-#{'y' * n}".codepoints
  cps += c.sum
  clen += c.length
  keep << c if i % 10 == 0
end
puts cps
puts clen
puts keep.length
