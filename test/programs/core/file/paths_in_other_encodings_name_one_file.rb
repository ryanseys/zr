# A path in another encoding names the same file in every call: each
# system call takes the path as the system reads it.
require "tmpdir"
Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    %w[EUC-JP Shift_JIS].each do |enc|
      name = "\u{30eb 30d3 30fc}#{enc}".encode(enc)
      File.write(name, "x")
      p [enc, File.exist?(name), File.file?(name), File.size(name), File.size?(name), File.zero?(name)]
      p [File.read(name), File.stat(name).size, File.readable?(name), File.writable?(name)]
      File.chmod(0o600, name)
      p File.stat(name).mode & 0o777
      File.utime(0, 0, name)
      p File.mtime(name).to_i
      $stdin.reopen(name)
      p $stdin.read
      moved = name + "2".encode(enc)
      File.rename(name, moved)
      p [File.exist?(name), File.exist?(moved)]
      File.symlink(moved, name)
      p [File.symlink?(name), File.readlink(name) == moved, File.realpath(name).end_with?("2")]
      File.delete(name, moved)
      p File.exist?(moved)
    end
    dirname = "\u{30eb}d".encode("EUC-JP")
    Dir.mkdir(dirname)
    p [Dir.exist?(dirname), File.directory?(dirname), Dir.empty?(dirname), Dir.entries(dirname).sort]
    File.write(File.join(dirname, "f"), "1")
    p [Dir.children(dirname), Dir.empty?(dirname)]
    Dir.chdir(dirname) { p File.read("f") }
    File.delete(File.join(dirname, "f"))
    Dir.rmdir(dirname)
    p Dir.exist?(dirname)
  end
end
