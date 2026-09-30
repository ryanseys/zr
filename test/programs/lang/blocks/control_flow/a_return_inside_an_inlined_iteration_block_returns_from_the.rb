# A `return` inside an inlined iteration block is non-local: it returns from the
# home method, not just the block, so the trailing statement is skipped.
def first_even_times_ten
  proc { [1, 2, 3].each { |x| return x * 10 if x == 2 }; :fell }.call
  :after
end
p first_even_times_ten

