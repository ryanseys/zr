a = [10, 20, 30]
# In-bounds — first / middle / last.
p a.dig(0)
p a.dig(1)
p a.dig(2)
# Negative indices — counts from the end.
p a.dig(-1)
p a.dig(-3)
# This test does not check an out-of-bounds dig. Ruby gives nil there.
