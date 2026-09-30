path = "spinel_file_predicate_test.txt"
File.write(path, "x")

puts File.directory?(".")
puts File.directory?("./")
puts File.directory?(path)
puts File.file?(path)
puts File.file?(".")
puts File.directory?("spinel_missing_predicate_path")
puts File.file?("spinel_missing_predicate_path")

File.delete(path)
