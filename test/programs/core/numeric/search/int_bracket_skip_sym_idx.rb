# `row[:id]` on a parameter of unknown type is a hash or array
# subscript, not Integer bit indexing. The index type decides this.

# Genuine bit indexing — must still work.
n = 0b1010
puts n[0]                # 0
puts n[1]                # 1
puts n[2]                # 0
puts n[3]                # 1

# Hash-subscript shape on a parameter of unknown type. No code calls
# from_raw, so the program only has to compile and run.
def from_raw(row)
  row[:id] || 0
end

puts "compiled-cleanly"
