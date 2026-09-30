# The options of an open are checked as rb_io_extract_modeenc checks
# them: each of mode, perm, textmode and binmode once, no decorator in
# binary mode, and a reader of an ASCII-incompatible encoding in binary
# mode unless it converts.
path = "/tmp/zr_spec_open_options.txt"
File.write(path, "x")
def opened(*args, **options)
  File.open(*args, **options) { |f| f.read.size }
rescue => e
  e
end
p opened(path, "rb", newline: :universal)
p opened(path, "rt", binmode: true)
p opened(path, binmode: true, textmode: true)
p opened(path, "rb", binmode: true)
p opened(path, "rt", textmode: true)
p opened(path, "r", mode: "r")
p opened(path, "r", 0644, perm: 0600)
p opened(path, mode: "r", flags: File::RDONLY)
p opened(path, "w", flags: File::EXCL)
p opened(path, "r", newline: :bogus)
p opened(path, "r", invalid: :bogus)
p opened(path, "r", xml: :bogus)
p opened(path, "r:utf-16le")
p((File.read(path, encoding: "utf-16le") rescue $!))
p File.read(path, mode: "r:utf-8:-")
File.delete(path)
