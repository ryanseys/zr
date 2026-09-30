# `block_given?` for `&block` parameters.
#
# `block_given?` gives the right answer also in a method that
# captures the block only via `&block` and never yields. This holds
# for instance methods, class-level methods and top-level methods.
#
# This test exercises the no-block-passed observable through the
# receiverless default-padding path and the explicit `self.block_given?`
# spelling.

# 1. Top-level `&block` method, called without a block — block_given?
#    must return false.
def top(&block)
  if block_given?
    puts "1-yes"
  else
    puts "1-no"
  end
end

top                       #=> 1-no

# 2. Same shape with a regular arg before &block — find_block_param_name
#    must skip the int param and pick the trailing proc-typed slot.
def top2(label, &block)
  if block_given?
    puts label + "-yes"
  else
    puts label + "-no"
  end
end

top2("2")                 #=> 2-no

def top3(&block)
  if self.block_given?
    puts "3-yes"
  else
    puts "3-no"
  end
end

def top4(&block)
  if self.block_given?
    puts "4-yes"
  else
    puts "4-no"
  end
end

top3                      #=> 3-no
top4 {}                   #=> 4-yes

puts "done"
