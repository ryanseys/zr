# The path helpers check their arguments as rb_get_path does, and
# expand_path keeps the slashes that start a path.
p((File.basename("a.rb", nil) rescue $!), (File.basename("a.rb", 1) rescue $!), File.basename("a.rb", ".*"))
p File.expand_path("//a"), File.expand_path("a", "//b"), File.expand_path("///a//b/"), File.expand_path("a/..", "/"),
  File.expand_path("..", "//"), File.expand_path("/a/../../b")
p((File.join("a\0", "b") rescue $!), (File.join("a", ["b\0"]) rescue $!), (File.absolute_path?(1) rescue $!), File.absolute_path?("/a"))
p((File.exist?("a".encode("utf-16le")) rescue $!), (File.join("a", "b".encode("utf-16le")) rescue $!))
