p [[1, 2]].map { |row| row.each_index.map { |c| c } }
# each_with_index.sum inside an outer map:
p [[10, 20, 30]].map { |row| row.each_with_index.sum { |v, i| v * i } }
# => [80]

# each_index.map on a local array:
a = [1, 2]
p a.each_index.map { |c| c }
# => [0, 1]
