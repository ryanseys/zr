# A `sum` block whose value indexes an Array#find result is poly; the sum
# must fold through the block.
table = [["h", 3600], ["m", 60]]
p ["1h", "30m"].sum { |t| t[0...-1].to_i * table.find { |l, _| l == t[-1] }[1] }
