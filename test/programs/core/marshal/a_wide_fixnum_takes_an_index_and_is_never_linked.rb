# Marshal.dump writes an Integer past 31 bits that is still a Fixnum as
# a new Bignum record each time: it takes an object index, so later links
# count it, but no record links back to it. A real Bignum object is
# linked when it comes again.
s = +"shared"
p Marshal.dump([2**40, s, 2**41, s, 2**40])
x = 2**40
p Marshal.dump([x, x, s, s])
p Marshal.dump([2**62 - 1, -2**62, 2**30, -2**30 - 1, 2**30 - 1])
big = 2**70
p Marshal.dump([big, s, big, s])
p Marshal.dump([2**62, 2**62])
p Marshal.dump({ 2**40 => s, s => 2**40 })
loaded = Marshal.load(Marshal.dump([2**40, s, 2**41, s, 2**40, big, big]))
p loaded, loaded[1].equal?(loaded[3]), loaded[5].equal?(loaded[6])
p Marshal.load(Marshal.dump(2**40..2**41)), Marshal.load(Marshal.dump([-2**62, s, s]))
