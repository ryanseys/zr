# Past DBL_DIG places the power of ten a scaled round would use is not
# exact, so ruby rounds the exact value the double holds. `ceil(n)`
# takes no correction step, unlike `floor(n)`.
p 66471.846.ceil(3)
p [1.0.round(15), 1.0.round(16), 0.1.round(15), 0.1.round(16), 0.1.round(17)]
p [1.23456789012345678.round(16), 1.23456789012345678.floor(16), 1.23456789012345678.ceil(16)]
p [5e-16.round(15), 5e-16.round(15, half: :even), 5e-16.round(15, half: :down)]
p [1.0e20.round(5), 1.0e-300.round(5), 0.0.round(5), (-0.0).round(5)]
p [(-1.5).round(15), (-0.1).ceil(16), (-0.1).floor(16)]
p [1.5.round(1000), 1.5.floor(1000), 1.5.ceil(1000), 1.5.truncate(1000)]
p [0.30000000000000004.round(16), 0.30000000000000004.round(17)]
__END__
66471.847
[1.0, 1.0, 0.1, 0.1, 0.1]
[1.2345678901234567, 1.2345678901234567, 1.2345678901234567]
[1.0e-15, 1.0e-15, 1.0e-15]
[1.0e+20, 0.0, 0.0, -0.0]
[-1.5, -0.1, -0.1000000000000001]
[1.5, 1.5, 1.5, 1.5]
[0.3, 0.30000000000000004]
