# IO.write opens with O_WRONLY|O_CREAT and truncates only when no offset
# says where the write goes, as io_s_write does; binwrite writes binary.

path = "iow_tmp.txt"
File.delete(path) if File.exist?(path)
p IO.write(path, "abc", 3)
p File.binread(path)
p IO.write(path, "Z", 1)
p File.binread(path)
p File.write(path, "hey")
p File.binread(path)
p IO.binwrite(path, "\xFF\xFE", 1)
p File.binread(path)
p File.write(path, "more", mode: "a")
p File.binread(path)
p File.write(path, "é", encoding: "UTF-16LE")
p File.binread(path)
p IO.binwrite(path, "q", mode: "a")
p File.binread(path)
begin
  File.write(path, "x", -1)
rescue => e
  p e.class
end
p File.binread(path)
p File.binwrite(path, "done")
p File.read(path)
File.delete(path)
p IO.respond_to?(:written, true)

__END__
3
"\x00\x00\x00abc"
1
"\x00Z\x00abc"
3
"hey"
2
"h\xFF\xFE"
4
"h\xFF\xFEmore"
2
"\xE9\x00"
1
"\xE9\x00q"
Errno::EINVAL
"\xE9\x00q"
4
"done"
false
