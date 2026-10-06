require "fileutils"
File.write("a", "same")
File.write("b", "same")
File.write("c", "other")
p FileUtils.compare_file("a", "b"), FileUtils.identical?("a", "c"), FileUtils.cmp("a", "c")
