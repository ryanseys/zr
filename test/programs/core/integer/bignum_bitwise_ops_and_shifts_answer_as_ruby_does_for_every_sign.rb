# &, |, ^, <<, >> and to_f of long Integers answer as ruby does: every
# sign of each operand, operands of different lengths, values on limb
# and fixnum edges, shifts across limb boundaries, and a negative value
# shifted right, which floors.
require "zlib"

edges = [0, 1, 2**29, 2**30 - 1, 2**30, 2**60 - 1, 2**61, 2**62 - 1, 2**62, 2**63, 2**64 - 1, 2**90 + 7, 3**200, 7**400, 2**3000 - 1, (2**1000) * (3**300)]
values = edges.flat_map { |v| [v, -v, v + 1, -(v + 1)] }.uniq
out = []
values.each do |a|
  values.each do |b|
    out << (a & b) << (a | b) << (a ^ b)
  end
  [0, 1, 29, 30, 31, 59, 60, 61, 64, 90, 1000, 5000].each do |n|
    out << (a << n) << (a >> n) << (a >> -n) << (a << -n)
  end
  out << ~a << a.to_f << a.bit_length
end
puts out.size, Zlib.crc32(out.join(","))
p (2**200) & 0xFFFF, (-(2**200)) & 0xFFFF, (2**200 + 12345) & 0xFFFF, (-(2**200 + 12345)) & -1
p (-(2**200)) >> 199, (-(2**200)) >> 200, (-(2**200)) >> 201, (-(2**200) - 1) >> 200, (2**200) >> 500, (-(2**200)) >> 500
p (3**500).to_f, (-(3**500)).to_f, (2**1024 - 1).to_f, ((2**53 + 1) << 100).to_f, ((2**53 + 3) << 100).to_f
p 1 << 200, -1 << 200, (2**200) << 0, (2**200 | 1) >> 0
