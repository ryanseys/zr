# A String can hold NUL bytes. length, bytesize and slicing count all
# the bytes, and do not stop at the first NUL. So `0.chr` has
# `length` 1 and `bytesize` 1.

# Single-byte NUL.
puts 0.chr.length              # 1
puts 0.chr.bytesize            # 1
puts 0.chr.ord                 # 0

# Concat preserves NULs in the middle.
b = 0.chr + 0xc8.chr
puts b.length                  # 2
puts b.bytesize                # 2
puts b[0].ord                  # 0
puts b[1].ord                  # 200 (0xc8)

# Mixed ASCII + NUL + ASCII -- indexing past the NUL.
c = "x" + 0.chr + "y"
puts c.length                  # 3
puts c[0].ord                  # 120 ('x')
puts c[1].ord                  # 0
puts c[2].ord                  # 121 ('y')

# Progressive build with NUL in the middle.
d = ""
d = d + 0x81.chr
d = d + 0x7e.chr
d = d + 0x00.chr
d = d + 0xc8.chr
puts d.length                  # 4
puts d[2].ord                  # 0
puts d[3].ord                  # 200

# Substring across NUL.
e = d[0, 4]
puts e.length                  # 4
puts e[3].ord                  # 200
