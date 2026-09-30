# File.write at the tail of a method body is an expression, the
# method's value. It still writes the file, as it does in a
# statement position.

def store(path, data)
  File.write(path, data)
end

store("spinel_file_write_test.txt", "ok\n")
puts File.read("spinel_file_write_test.txt")
File.delete("spinel_file_write_test.txt")
