# Integer arithmetic that overflows int64 gives a Bignum, as in
# CRuby. It does not wrap and does not raise, so no rescue runs.
#
# Non-overflowing arithmetic must still produce the expected
# result.

# Sanity: non-overflowing arithmetic still works.
puts 100 + 200
puts 1000 - 500
puts 6 * 7

# Each of the three operators overflows into a Bignum.
[:plus, :minus, :mul].each do |op|
  begin
    huge = 9_223_372_036_854_775_000
    case op
    when :plus
      x = huge + 9_223_372_036_854_775_000
    when :minus
      x = -huge - 9_223_372_036_854_775_000
    when :mul
      x = huge * 1000
    end
    puts "no raise from #{op}: #{x}"
  rescue RangeError => e
    puts "#{op}: caught #{e.message}"
  end
end
