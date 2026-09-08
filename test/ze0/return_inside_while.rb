def first_over(limit)
  i = 0
  while true
    i = i + 1
    if i * i > limit
      return i
    end
  end
end
puts first_over(50)
puts first_over(0)
def early(n)
  return "neg" if n < 0
  "pos"
end
puts early(-1)
puts early(1)
def bare
  return
end
p bare
__END__
8
1
neg
pos
nil
