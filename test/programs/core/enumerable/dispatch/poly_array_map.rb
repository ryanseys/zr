# `.map { ... }` on a mixed-element array (`[1, "two", :three]`)
# gives an Array of the block results. `.length` and `[i]` work on
# that result.

# (1) mixed Array → Integer Array (int-return block).
arr = [1, "two", :three, 4.5]
out = arr.map { |x| x.to_s.length }
puts out.length      # 4
puts out[0]          # 1
puts out[1]          # 3
puts out[2]          # 5
puts out[3]          # 3

# (2) mixed Array → String Array (string-return block).
strs = arr.map { |x| x.to_s }
puts strs.length     # 4
puts strs[0]         # 1
puts strs[1]         # two
puts strs[2]         # three
puts strs[3]         # 4.5

# (3) mixed Array → Integer Array (different int expression).
sizes = arr.map { |x| x.to_s.length * 2 }
puts sizes.length    # 4
puts sizes[0]        # 2
puts sizes[3]        # 6
