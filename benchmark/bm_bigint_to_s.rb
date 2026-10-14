# Decimal digits of long Integers, from 50 to 6,000 limbs of 30 bits,
# with a few in bases 7 and 36: each digit string shows as its length
# and a sum of a few of its bytes.
sum = 0
[50, 200, 800, 3_000, 6_000].each do |limbs|
  a = (3**((30 * limbs) / 1.585).floor) | 1
  rounds = 1_200_000 / limbs / limbs + 1
  rounds.times do
    text = a.to_s
    sum += text.size + text.getbyte(0) + text.getbyte(-1) + text.getbyte(text.size / 2)
    sum += (-a).to_s(7).size + a.to_s(36).getbyte(1)
  end
end
puts sum
