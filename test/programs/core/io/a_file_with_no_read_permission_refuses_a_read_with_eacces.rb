# A file whose mode gives no read permission refuses File.read with
# EACCES and the path. root may read any file, so the test needs a user
# that is not root.
File.write("ro.txt", "")
File.chmod(0, "ro.txt")
begin
  File.read("ro.txt")
rescue SystemCallError => e
  p [e.class, e.message]
end
