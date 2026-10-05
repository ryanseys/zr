# An open, a glob or a Dir.new that finds no free descriptor (EMFILE)
# collects, which closes the Files that the program dropped, and tries
# once more, as rb_gc_for_fd does (test_dir.rb's test_glob_gc_for_fd).
require "tmpdir"
Dir.mktmpdir do |root|
  ("a".."e").each { |name| File.write(File.join(root, name), "") }
  Process.setrlimit(Process::RLIMIT_NOFILE, 50)
  begin
    fs = []
    tap { tap { tap { (0..100).each { fs << File.open(IO::NULL) } } } }
  rescue Errno::EMFILE => e
    p e.class
  ensure
    fs.clear
  end
  p Dir.glob("*", base: root).sort
  p File.open(IO::NULL).closed?, Dir.new(root).children.sort.size
end
