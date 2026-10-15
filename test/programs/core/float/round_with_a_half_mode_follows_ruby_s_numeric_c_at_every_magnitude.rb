# Float#round with half: :down or :even uses numeric.c's round_half_down
# and round_half_even, also with no digits. Their check after the
# rounding takes 2**53 one down for :down, and an infinity is NaN for
# :even, which FloatDomainError names.
values = [0.5, 1.5, 2.5, -0.5, -1.5, -2.5, 2.675, 1.005, 0.125, 0.375,
          4503599627370495.5, 4503599627370496.5, 9007199254740992.0, 9007199254740993.0,
          -9007199254740992.0, 1e16, 1e20, 123.456, -123.456, 5e-324]
values.each do |v|
  row = [nil, :up, :down, :even].map { |half| v.round(half: half) }
  row += [1, 2].flat_map { |digits| [:up, :down, :even].map { |half| v.round(digits, half: half) } }
  puts "#{v}: #{row.inspect}"
end
[Float::INFINITY, -Float::INFINITY, Float::NAN].each do |v|
  [nil, :up, :down, :even].each do |half|
    p v.round(half: half)
  rescue FloatDomainError => e
    puts "#{v} #{half.inspect}: #{e.message}"
  end
  p [1, 2].map { |digits| v.round(digits, half: :even) }
end
