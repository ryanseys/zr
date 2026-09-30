# The second argument already ends in a newline BYTE -- `puts` must
# not double it, and the 0xB5 byte must survive un-promoted.

path = "/tmp/zr_e2e_binputs_#{Process.pid}"
File.open(path, "wb") { |f| f.puts 180.chr, (181.chr + "\n") }
p File.binread(path).bytes
File.delete(path)
