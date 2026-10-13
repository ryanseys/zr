# ruby 4.1: File.ftype and File::Stat#ftype give one frozen US-ASCII
# String per type. Dir#each_child and Dir#scan raise IOError when the
# block closes the directory, as Dir#each does.
require "tmpdir"

def t(label)
  p [label, yield]
rescue Exception => e
  p [label, e.class, e.message]
end

Dir.mktmpdir do |dir|
  File.write(File.join(dir, "a"), "")
  File.write(File.join(dir, "b"), "")
  t(:ftype) { [File.ftype(dir), File.ftype(dir).frozen?, File.ftype(dir).encoding] }
  t(:stat_ftype) { s = File.lstat(File.join(dir, "a")); [s.ftype, s.ftype.frozen?, s.ftype.equal?(File.ftype(File.join(dir, "a")))] }
  t(:same) { File.ftype(dir).equal?(File.ftype(dir)) }
  t(:directory) { File.stat(dir).directory? }
  t(:each_child_close) { n = 0; d = Dir.open(dir); d.each_child { n += 1; d.close }; :no }
  t(:each_child_count) { n = 0; d = Dir.open(dir); (d.each_child { n += 1; d.close } rescue nil); n }
  t(:scan_close) { d = Dir.open(dir); d.scan { |*| d.close }; :no }
  t(:each_close) { d = Dir.open(dir); d.each { d.close }; :no }
  t(:each_child_ok) { Dir.open(dir) { |d| d.each_child.sort } }
end
