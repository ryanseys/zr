# A shift count past the word moves every bit out; the machine's own
# shift would take the count mod 64.
p 5 << -64, -5 << -64, 5 << -63, -5 << -63, 5 << -62, 8 << -2, 1 << -1
p 5 >> 64, -5 >> 64, 5 >> 63, -5 >> 62, 8 >> 2
p 5 << -(2**70), -5 << -(2**70)

__END__
0
-1
0
-1
0
2
0
0
-1
0
-1
2
0
-1
