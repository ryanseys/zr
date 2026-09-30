# frozen_string_literal: true

# A raise inside the body leaves the loop's own state behind cleanly.
begin
  for r in [1, 2]
    raise ArgumentError, "stop" if r == 2
  end
rescue ArgumentError => err
  p err.message, r
end

begin
  for n in 5
    p n
  end
rescue NoMethodError => err
  p err.message
end

def first_over(list, limit)
  for item in list
    return item if item > limit
  end
  :none
end

p first_over([1, 2, 3], 1), first_over([1], 9)

