# Block-body local plus a non-local return from inside the block.
def block_local_return
  proc { [1, 2, 3].each { |x| y = x * 10; return y if x == 2 }; :fell }.call
end
p block_local_return

