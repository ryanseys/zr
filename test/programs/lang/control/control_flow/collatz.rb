def steps(n)
  count = 0
  while n != 1
    if n % 2 == 0
      n = n / 2
    else
      n = 3 * n + 1
    end
    count = count + 1
  end
  count
end
puts steps(27)
puts steps(1)
puts steps(97)
