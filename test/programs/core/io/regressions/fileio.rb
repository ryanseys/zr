# Test basic File I/O.
# Uses cwd-relative paths so the harness (which runs each test from
# the project root) and the CRuby reference both write to the same
# place on every platform — `/tmp/...` does not resolve the same
# way on all platforms.

# Write a file
File.write("spinel_test.txt", "Hello from Spinel!\nLine 2\n")

# Read the file
content = File.read("spinel_test.txt")
puts content

# File.exist?
puts File.exist?("spinel_test.txt")  # true
puts File.exist?("spinel_nonexistent.txt")  # false

# Clean up
File.delete("spinel_test.txt")
puts File.exist?("spinel_test.txt")  # false

puts "done"
