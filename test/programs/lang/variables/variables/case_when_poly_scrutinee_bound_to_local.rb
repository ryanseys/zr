# `case v when X then ... end` bound to a local via `r = ...`.
# The scrutinee `v` can be of any type, and the result is an
# Integer. The scrutinee keeps its own type: it does not take the
# type of the result. With no `else`, a miss gives nil.

def classify(v)
  r = case v when Range then 1 end
  r
end
puts classify(200..299)             # 1 (Range matches)
puts classify(404)                  # (blank: no when match -> nil)

# Case-when result bound to local with mixed branches and poly scrutinee.
def label(v)
  r = case v
      when Range   then "range"
      when Integer then "int"
      else "other"
      end
  r
end
puts label(200..299)                # range
puts label(404)                     # int
puts label("hi")                    # other
