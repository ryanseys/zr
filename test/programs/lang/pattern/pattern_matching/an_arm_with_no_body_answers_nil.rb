# frozen_string_literal: true

# An arm with no body answers nil.
p(case 1
  in Integer
  end)

def first_string(list)
  case list
  in [*, String => s, *] then return s
  in [] then :empty
  else :none
  end
end

p first_string([1, "hit", 2]), first_string([]), first_string([1])

