# The chars/split result of a String destructured from a pair, captured (map /
# returned): the auto-splat gives the String param a real String, and its
# String methods work.
r = [["ab", "cd"]].map { |a, b| a.chars }
p r
p [["a,b", "c"]].map { |a, b| a.split(",") }
p [["ab", "cd"]].map { |a, b| a.chars.length }
p [[:x, :y]].map { |a, b| a.to_s }
