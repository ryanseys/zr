# An array literal of hash literals (`[{n: 3}, {n: 1}]`) holds
# hashes, and each element reads back as a Hash.
arr = [{n: 3}, {n: 1}, {n: 2}]
puts arr.length          # 3
puts arr[0][:n].to_s     # 3
puts arr[1][:n].to_s     # 1
puts arr[2][:n].to_s     # 2

mixed = [{a: 1}, {b: "x"}]
puts mixed.length        # 2
