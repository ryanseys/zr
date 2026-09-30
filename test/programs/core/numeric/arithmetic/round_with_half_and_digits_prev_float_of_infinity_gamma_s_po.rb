p 1.005.round(2, half: :even), 4.45.round(1, half: :even), 0.285.round(2, half: :down), 25.4.round(-1, half: :even)
p Float::INFINITY.prev_float, (-Float::INFINITY).next_float
p Math.gamma(-0.0), Math.gamma(Float::INFINITY), Math.gamma(Float::NAN).nan?
p Math.log(2, 1), Math.log(2, 2**1000), Math.log(2**2000), Math.log(10**400, 2**2000)
p (1.0..2.0).step(0.1).to_a
p 5.pow(0, 1)
