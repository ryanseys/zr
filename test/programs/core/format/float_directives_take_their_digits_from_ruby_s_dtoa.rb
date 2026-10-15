# %e, %f and %g take their digits from ruby's dtoa: double arithmetic
# first, where a remainder within its error bound of one half is a tie
# to even, then the exact value; an integer below 10**15 keeps the zeros
# before a tie. Each line is a value, its directive and the text.
values = [
  0.69 / 6, 2.675, 2.345, 1.005, 0.125, 0.25, 9.045000000000005,
  9996.250000000005, 9.248349999999995, 7.919050000000001, 211680500.0,
  1.7976931348623157e308, 0.1 + 0.2, 5e-324, 2.2250738585072014e-308,
  1e22, 1e23, 123456789012345.0, 999999.5, 0.5, 1.5, 2.5, 0.05, 0.005,
  9.9999999, 99.95, 0.0, 1e-5, 123.456, 1e15, 1e16, 4.35, 0.015, 1.0 / 3,
]
directives = %w[%.0f %.1f %.2f %.3f %.10f %f %#.0f %.0e %.2e %e %#.0e %.1g %.3g %.5g %.6G %g %#g %#.3g %.0g %.17g %.20f]
values.each do |v|
  puts directives.map { |d| "#{d}=#{format(d, v)}" }.join(" ")
end

puts format("%12.5g|%-12.5g|%012.5g|%+.3e|% .2f", 7.919050000000001, 7.919050000000001, 7.919050000000001, -2.5, 0.125)
puts format("%.2f|%.1e|%g", -0.69 / 6, -0.0, -1e-10)
puts format("%.1100f", 0.1).size, format("%.3e", 1e300), format("%5.1f|%-8.3e|", 1e-7, 123456.0)

sum = 0
3000.times do |i|
  x = ((i * 7919) % 100_003 + 0.5) / 10.0**(i % 7)
  [x, x.next_float, x.prev_float, x * 1e-200, x * 1e200].each do |y|
    sum += format("%.#{i % 6}f", y).sum + format("%.#{i % 6}e", y).sum + format("%.#{i % 6 + 1}g", y).sum
  end
end
p sum
