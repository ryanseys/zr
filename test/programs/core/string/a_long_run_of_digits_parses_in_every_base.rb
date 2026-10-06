# String#to_i and Integer() read a run of digits longer than one chunk
# in every base, with a sign, upper case and underscores.
(2..36).each do |base|
  digits = "0123456789abcdefghijklmnopqrstuvwxyz"[0, base]
  text = (digits[1..] + digits[0]) * ((100 / base) + 3)
  n = text.to_i(base)
  grouped = text.chars.each_slice(3).map(&:join).join("_")
  puts [base, n.bit_length, n.to_s(base) == text, "-#{text}".to_i(base) == -n,
        text.upcase.to_i(base) == n, grouped.to_i(base) == n, Integer(text, base) == n].join(" ")
end
p ("12" * 40).to_i(3)
p Integer("1" * 40, 3)
p "#{'2' * 17}x".to_i(3)
p "#{'2' * 18}3".to_i(3)
p "  +#{'7' * 30}".to_i(8)
