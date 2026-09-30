# block_given? in a yield-using method, called from a site that
# either omits the block (false) or supplies a literal block
# (true).
def f
  puts block_given?
end
f
f { }
