# require_relative in a file loaded through a symlink starts from the
# file that the link names, as ruby's rb_current_realfilepath.
$rec = []
Dir.mkdir("links")
link = File.join(Dir.pwd, "links", "link.rb")
File.symlink(File.join(Dir.pwd, "real", "one.rb"), link)
p require_relative(link), $rec
