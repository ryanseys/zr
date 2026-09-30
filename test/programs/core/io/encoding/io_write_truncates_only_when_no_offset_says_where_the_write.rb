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

