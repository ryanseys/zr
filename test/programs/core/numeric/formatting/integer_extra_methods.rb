# More Integer methods: magnitude (alias for abs), modulo (alias for %),
# remainder (truncated division remainder, differs from % for mixed-sign),
# size (bytes in a machine word = 8), gcdlcm.
puts (-42).magnitude
puts 7.modulo(3)
puts (-7).modulo(3)
puts 7.remainder(3)
puts (-7).remainder(3)
puts 12.gcdlcm(18).inspect
puts 1.size
puts 256.size
