# `File.join` collapses a separator at the seam rather than doubling it, and
# flattens a nested Array argument.

puts File.join("a", "b", "c")
puts File.join("a/", "b")
puts File.join("a", "/b")
puts File.join("a/", "/b")
puts File.join("/a", "b")
puts File.join("a", ["b", "c"])
p File.absolute_path?("/abs")
p File.absolute_path?("rel")
