# Array#product on two Integer arrays gives the Cartesian product.
puts [1, 2].product([3, 4]).inspect
puts [1, 2, 3].product([10, 20]).inspect
# Empty other → empty product.
puts [1, 2].product([]).inspect
