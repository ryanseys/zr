# `File.binread(path).bytes` gives every byte of binary data, also
# a 0x00 byte in the middle (as in .nes ROM files).
#
# Uses a cwd-relative path so that zr and the CRuby reference resolve
# to the same file (the harness runs each test from the project
# root). `/tmp/...` can land in different places on the two sides.

# Set up a binary file with embedded NULs via a shell command.
path = "spinel_binread_test.bin"
`printf 'AB\\000CD\\000EF' > #{path}`

# The byte count is the file size, NULs included.
arr = File.binread(path).bytes
puts arr.length               # 8
puts arr[0]                   # 65 (A)
puts arr[1]                   # 66 (B)
puts arr[2]                   # 0  (NUL)
puts arr[3]                   # 67 (C)
puts arr[4]                   # 68 (D)
puts arr[5]                   # 0  (NUL)
puts arr[6]                   # 69 (E)
puts arr[7]                   # 70 (F)

# `File.binread` alone returns a String of the file's bytes.
puts File.binread(path)[0, 2] # AB

File.delete(path) if File.exist?(path)
