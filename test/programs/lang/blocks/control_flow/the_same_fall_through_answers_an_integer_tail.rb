def tail_int(n)
  proc { return 5 if n < 0; 10 }.call
end
p tail_int(1)
p tail_int(-1)

