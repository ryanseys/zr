# native only: Float parsing and libm come from libSystem
p 1.5 + 2, 2 + 1.5, 3 - 0.5, 0.5 - 3, 2 * 1.5, 1.5 * 2, 7 / 2.0, 7.0 / 2, 7 % 2.5, 7.5 % 2, -7.5 % 2, 7.5 % -2, 2.0**10, 2**0.5, 2.0**-1, 1.5.class
p 1.0 == 1, 1 == 1.0, 1 == 1.5, 1.0.eql?(1), 1.0.eql?(1.0), 1.0.equal?(1.0), 0.1 + 0.2 == 0.3, 1.0 <=> 2, 2 <=> 1.0, 1 <=> 1.0, 1.0 <=> "x", 1 < 1.5, 1.5 < 2, 2 > 1.5, 1.5 >= 1.5, 1 <= 1.0, 3 < 2.5
p 0.0 == -0.0, 0.0.eql?(-0.0), (0.0).hash == (-0.0).hash, 1.5.hash == 1.5.hash, 1.5.hash == 2.5.hash, {1.5 => :a}[1.5], [1.0, 2.0].include?(2), [1, 2].include?(2.0)
p 2.5.round, 3.5.round, -2.5.round, 2.4.round, 2.6.round, 2.5.floor, -2.5.floor, 2.5.ceil, -2.5.ceil, 2.7.truncate, -2.7.truncate, 2.7.to_i, -2.7.to_i
p 1.23456.round(2), 1.235.round(2), 2.675.round(2), 1.5.round(1), 1234.5678.round(-2) rescue p $!
p 1.23456.floor(2), -1.23456.floor(2), 1.23456.ceil(2), -1.23456.ceil(2), 1.0.round(2), 1e-10.round(2), 123.456.round(20)
p 5.0.divmod(3), -5.0.divmod(3), 5.5.divmod(-2), 5.0.div(3), 5.0.fdiv(2), 7.divmod(2.0), 7.fdiv(2), 7.div(2.0), 3.7.modulo(1)
p Float::INFINITY, -Float::INFINITY, Float::NAN.nan?, Float::INFINITY.infinite?, (-Float::INFINITY).infinite?, 1.0.infinite?, 1.0.finite?, Float::INFINITY.finite?, Float::NAN == Float::NAN, Float::NAN != Float::NAN, (Float::NAN <=> 1.0), Float::MAX, Float::MIN, Float::EPSILON, Float::DIG, Float::MANT_DIG
p 1.0 / 0, -1.0 / 0, (0.0 / 0.0).nan?, 5.5.abs, -5.5.abs, -5.5.magnitude, 1.5.zero?, 0.0.zero?, -0.0.zero?, 1.5.positive?, -1.5.negative?, 1.5.integer?, 1.5.to_f.equal?(1.5)
begin; 1.0 % 0; rescue => e; p e; end
begin; 1.0 % 0.0; rescue => e; p e; end
begin; 1 % 0.0; rescue => e; p e; end
begin; Float::NAN.to_i; rescue => e; p e; end
begin; Float::INFINITY.to_i; rescue => e; p e; end
begin; (-Float::INFINITY).round; rescue => e; p e; end
begin; 1.5 + "x"; rescue => e; p e; end
begin; 1.5 + nil; rescue => e; p e; end
begin; 1.5 < "x"; rescue => e; p e; end
begin; 1.5 < nil; rescue => e; p e; end
begin; 1 + 1.5.to_s; rescue => e; p e; end
p 10.to_f, -3.to_f, 0.to_f, (2**53).to_f, (2**53 + 1).to_f, 1.5.to_i, 1e10.to_i, -1e10.to_i, 1e18.to_i
p "3.14".to_f, "  -2.5e3xyz".to_f, "abc".to_f, "1_000.5".to_f, ".5".to_f, "5.".to_f, "1e".to_f, "0x1A".to_f, "".to_f, "1__0".to_f, "Infinity".to_f, "-.5".to_f
p Float("3.14"), Float(" 2.5 "), Float("1_000.5"), Float(3), Float(2.5), Float("1e5"), Float(".5"), Float("-1.5e-3")
["5.", "1e", "abc", "", "1__0", "_1", "1_", "Infinity", "1.5x"].each { |s| begin; Float(s); rescue => e; p e; end }
p Float("x", exception: false), Float(nil, exception: false)
begin; Float(nil); rescue => e; p e; end
begin; Float([]); rescue => e; p e; end
p Math.sqrt(16), Math.sqrt(2), Math.sqrt(4.0), Math::PI, Math::E, Math.sin(0), Math.cos(0.0), Math.exp(1), Math.log(Math::E), Math.log(8, 2), Math.log2(8), Math.log10(1000), Math.atan2(1, 1), Math.hypot(3, 4), Math.cbrt(27), Math.tan(0.5), Math.atan(1.0), Math.sinh(1.0), Math.cosh(0), Math.tanh(0.5), Math.asin(1), Math.acos(1)
begin; Math.sqrt(-1); rescue => e; p e, e.class.ancestors[0..2]; end
begin; Math.log(-1); rescue => e; p e; end
begin; Math.sqrt("x"); rescue => e; p e; end
begin; Math.sqrt(nil); rescue => e; p e; end
p [3.5, 1.25, 2.0].sort, [3.5, 1, 2.0].max, [1.5, 2].min, [1.5, 2.5].sum, [1, 2.5].sum, (1.5..3.5).include?(2), 1.5.between?(1, 2), 2.5.clamp(1, 2), 2.5.clamp(1.0, 2.0)
p 1.5.coerce(2), 1.coerce(2.5), 1.5.coerce(2.5), 3.7 % 1, 100.0.to_s, 1e2, 1.0e-2, 1.5e300 * 1e10, -1.5e300 * 1e10, 1e-320, 5e-324 / 2
p 0.1 * 3, 1.1 * 1.1, 100.0 / 3, 2.0 ** 0.5 == Math.sqrt(2), 10.0 ** 20, 10 ** 20.0, 1.0e-7, 1234567.0, 12345678.9, 0.5.round, 1.5.round, 0.5.floor, -0.5.ceil, -0.5.round, -1.5.round
p 3.14.floor, 3.99.ceil, -3.14.floor, -3.99.ceil, 3.0.floor, 3.0.ceil, 12.34.round(1), 12.35.round(1), 12.345.round(2), 0.615.round(2), 0.285.round(2), 1.005.round(2)
p 7.0.div(2), 7.0.modulo(2), -7.0.div(2), 7.5.divmod(2.5)
x = 0.0
10.times { x += 0.1 }
p x, x == 1.0, (x - 1.0).abs < Float::EPSILON * 10
p 2.5.to_s, 2.5.inspect, "#{2.5}", 1e100.to_s, 1.0e-100.inspect, [1.5, [2.5]].inspect, {a: 1.5}.to_s
p 1.5.frozen?, 1.5.dup.equal?(1.5), 1e300.frozen?, (1e300 * 10).equal?(Float::INFINITY), 1e300.class, 1e300.object_id == 1e300.object_id
