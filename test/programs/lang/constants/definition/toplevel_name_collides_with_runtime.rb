# A top-level method can have the same name as an internal helper of the
# runtime, like the methods below. The user method wins.
def str_hash
  1
end
def poly_add(a, b)
  a + b
end
def gc_stat = "mine"
def box_it(x) = [x]
def my_helper(v) = v * 2
def plain = 7
p str_hash
p poly_add(1, 2)
p gc_stat
p box_it(3)
p my_helper(4)
p plain
alias str_hash2 str_hash
p str_hash2
module M
  def self.str_hash = 9
end
p M.str_hash
