# Integer#chr reads itself as an unsigned int before it counts its
# arguments, so a value out of range raises RangeError first.
[-> { (2**64).chr }, -> { 300.chr(1, 2) }, -> { -1.chr(1, 2) }, -> { 65.chr(1, 2) }, -> { (2**64).chr("x") }, -> { 300.chr }].each do |c|
  p c.call
rescue => e
  p [e.class, e.message]
end
p 200.chr, 65.chr, 0x3042.chr("UTF-8")
