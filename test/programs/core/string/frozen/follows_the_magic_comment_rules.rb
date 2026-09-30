# frozen-string-literal: TRUE
# The magic comment reads as CRuby reads it: `-` and `_` alike, and the
# value in any case. Adjacent strings and a heredoc with no
# interpolation are literals too; an interpolated string is not.
p "x".frozen?
p ("a" "b").frozen?
p <<~HEREDOC.frozen?
  heredoc
HEREDOC
p "i#{1}".frozen?
p "same".equal?("same")
p __FILE__.frozen?
p %w[a b].all?(&:frozen?)

