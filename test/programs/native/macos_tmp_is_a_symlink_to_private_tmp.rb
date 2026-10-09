# On macOS, /tmp is a symbolic link to /private/tmp.
s = File.stat("/tmp")
p File.realpath("/tmp")
begin; File.realpath("/nope"); rescue => e; p e.message; end
p File.realpath("tmp", "/private")
p File.symlink?("/tmp"), File.symlink?("/private/tmp"), File.symlink?("/nope")
p File.lstat("/tmp").symlink?
p (File.stat("/tmp") <=> File.stat("/private/tmp")), s.inspect.start_with?("#<File::Stat dev=0x")
