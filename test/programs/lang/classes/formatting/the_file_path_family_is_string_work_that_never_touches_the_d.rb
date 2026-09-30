# The P-B core classes: File, Dir, Time, Process, ENV.
#
# Everything here is zone- and machine-independent on purpose: Time uses a
# fixed epoch read in UTC, paths are built under a scratch directory this
# script creates, and nothing prints a real pid/clock/environment value --
# only facts about them. That is what lets the output be diffed against real
# ruby at all.

# --- File: the pure-path family (string work, never touches the disk) -------
puts File.basename("/home/user/notes.md")
puts File.basename("/home/user/notes.md", ".md")
puts File.basename("/home/user/notes.md", ".*")
puts File.basename("/a/b/")
puts File.dirname("/home/user/notes.md")
puts File.dirname("solo")
puts File.dirname("/x")
p File.extname("archive.tar.gz")
p File.extname(".bashrc")      # a LEADING dot is a name, not an extension
p File.extname("trailing.")    # ...but a TRAILING one is an extension
p File.split("/a/b/c.rb")
puts File.join("a", "b", "c")
puts File.join("a/", "/b")     # the separator at the seam collapses
p File.absolute_path?("/abs")
p File.absolute_path?("rel")

