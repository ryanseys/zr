# A string with embedded NUL bytes is not cut at the first NUL:
#
#   - an s[a, n] slice reads past a NUL that comes after a.
#   - s.bytes[i] includes the bytes after the first NUL.
#
# Concat also keeps the NULs.

nul = 0.chr
s = "abc" + nul + "def"
puts "len=#{s.length}"
puts "slice_full=#{s[0, 7].length}"
puts "slice_after_nul=#{s[4, 3].length}"
puts "slice_around_nul=#{s[2, 3].length}"
puts "b0=#{s.bytes[0]}"
puts "b3=#{s.bytes[3]}"
puts "b4=#{s.bytes[4]}"
puts "b6=#{s.bytes[6]}"
puts "bytes_len=#{s.bytes.length}"
