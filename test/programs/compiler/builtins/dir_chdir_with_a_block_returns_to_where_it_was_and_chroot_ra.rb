# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

Dir.mktmpdir do |dir|
  Dir.open(dir) do |d|
    inside = d.chdir { File.basename(Dir.pwd) }
    puts "Dir#chdir block: #{inside == File.basename(dir)}"
  end
end
# A directory that exists: a user who is not root gets EPERM on every OS.
# For a missing one, Linux looks the path up first and gives ENOENT.
begin
  Dir.chroot("/")
rescue SystemCallError => e
  puts "Dir.chroot: #{e.class}"
end
