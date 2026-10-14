# Products of long Integers around the lengths where zr's method
# changes (32 limbs of 30 bits, then each split), with every limb all
# ones, a power of two, signs mixed and unequal lengths: each product
# shows as its residues, its bit length and the ends of its hex digits.
BITS = 30

def show(label, n)
  hex = n.abs.to_s(16)
  puts "#{label}: #{n % 1_000_000_007} #{n % 4_294_967_291} #{n.bit_length} #{hex[0, 16]}..#{hex[-16..]}"
end

def mixed(limbs, seed) = (seed**((BITS * limbs) / Math.log2(seed)).floor) | (1 << ((BITS * limbs) - 1))

[31, 32, 33, 65, 163, 400].each do |limbs|
  ones = (1 << (BITS * limbs)) - 1
  power = 1 << ((BITS * limbs) - 1)
  a = mixed(limbs, 3)
  b = mixed(limbs, 7)
  show("#{limbs} ones^2", ones * ones)
  show("#{limbs} ones*2^k", ones * power)
  show("#{limbs} a*b", a * b)
  show("#{limbs} -a*b", -a * b)
  show("#{limbs} a*-b", a * -b)
  show("#{limbs} a*a", a * a)
  show("#{limbs} a*b/3", a * mixed(limbs / 3 + 1, 5))
  show("#{limbs} a*small", a * mixed(2, 11))
  puts "#{limbs} exact: #{(a * b) / b == a && (a * b) % a == 0}"
end

# Digits of long Integers around the length where to_s splits a value
# in two (80 limbs, then each split again): all nines and runs of zero
# digits in the middle, which the lower half must pad, signs mixed, and
# bases that are not powers of two. Each shows its length, ends, byte
# sum and whether it reads back.
def digits(label, n, base)
  text = n.to_s(base)
  puts "#{label} in #{base}: #{text.size} #{text[0, 12]}..#{text[-12..]} #{text.sum} #{Integer(text, base) == n} #{text.encoding}"
end

[79, 80, 81, 161, 403, 1000].each do |limbs|
  digits_wide = (BITS * limbs * 0.30103).floor
  a = mixed(limbs, 3)
  [10, 3, 7, 36].each do |base|
    digits("#{limbs} a", a, base)
    digits("#{limbs} -a", -a, base)
  end
  digits("#{limbs} nines", (10**digits_wide) - 1, 10)
  digits("#{limbs} 10^k", 10**digits_wide, 10)
  digits("#{limbs} 10^k+1", (10**digits_wide) + 1, 10)
  digits("#{limbs} -(10^k+7)", -((10**digits_wide) + 7), 10)
  digits("#{limbs} 2^k", 1 << (BITS * limbs), 10)
  digits("#{limbs} 36^k-1", (36**(digits_wide / 2)) - 1, 36)
end
