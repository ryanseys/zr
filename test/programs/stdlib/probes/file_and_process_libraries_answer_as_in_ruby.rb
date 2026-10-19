# A probe of many methods, each line one call and its answer or its error,
# compared with ruby's.
def t(label)
  r = begin
    yield.inspect
  rescue Exception => e
    "#{e.class}: #{e.message}"
  end
  puts "#{label}: #{r}"
end

require "fileutils"; require "tempfile"; require "tmpdir"; require "pathname"; require "find"; require "stringio"; require "open3"
Dir.mktmpdir do |d|
  Dir.chdir(d) do
    t("mkdir_p") { FileUtils.mkdir_p("a/b/c"); File.write("a/b/c/f.txt", "hi\nthere\n"); Dir.glob("**/*").sort }
    t("cp_r") { FileUtils.cp_r("a", "z"); Dir["z/**/*"].sort }
    t("mv") { FileUtils.mv("z/b/c/f.txt", "z/g.txt"); [File.exist?("z/g.txt"), Dir.children("z").sort] }
    t("ln_s") { File.symlink("a/b", "lnk"); [File.symlink?("lnk"), File.readlink("lnk"), File.realpath("lnk").end_with?("a/b")] }
    t("find") { Find.find("a").to_a.sort }
    t("pathname") { p = Pathname("a/b/../b/c/f.txt"); [p.cleanpath.to_s, p.basename.to_s, p.extname, p.dirname.to_s, p.each_filename.to_a, (Pathname("/x/y") + "../z").to_s, Pathname("a/b").relative_path_from(Pathname("a/c")).to_s] }
    t("pathname io") { p = Pathname("a/b/c/f.txt"); [p.read, p.readlines.size, p.size, p.file?, (p.children rescue $!.class)] }
    t("file ops") { [File.basename("/a/b.rb", ".rb"), File.extname("x.tar.gz"), File.join("a", "/b/", "c"), File.expand_path("x", "/y"), File.split("/a/b"), File.absolute_path?("/a")] }
    t("file stat") { s = File.stat("a/b/c/f.txt"); [s.size, s.file?, s.directory?, s.mode.to_s(8)[-3..] .size, File.zero?("a/b/c/f.txt")] }
    t("io each") { File.open("a/b/c/f.txt") { |f| [f.gets, f.lineno, f.read, f.eof?, f.pos] } }
    t("io modes") { File.open("w.txt", "w+") { |f| f.write("abc"); f.rewind; f.seek(1); [f.read, f.tell] } + [File.read("w.txt", 2, 1)] }
    t("io append") { File.write("w.txt", "d", mode: "a"); [File.read("w.txt"), File.foreach("a/b/c/f.txt").map(&:chomp)] }
    t("tempfile") { tf = Tempfile.new(%w[x .rb]); tf.write("q"); tf.flush; r = [File.extname(tf.path), File.size(tf.path)]; tf.close!; r + [tf.path.nil?] }
    t("tempfile create") { Tempfile.create("y") { |f| f.puts "z"; f.size } }
    t("stringio") { s = StringIO.new(+"a\nb\nc"); [s.gets, s.readlines, s.eof?, (s.string << "d"), s.read, StringIO.new("xyz").each_char.to_a] }
    t("stringio w") { s = StringIO.new; s.printf("%03d", 7); s.puts [1, [2]]; s.print "e", "f"; s << 3; s.string }
    t("open3") { o, e, st = Open3.capture3("sh", "-c", "echo out; echo err >&2; exit 3"); [o, e, st.exitstatus] }
    t("open3 pipe") { Open3.pipeline_r("printf 'b\na\n'", "sort") { |o, _| o.read } }
    t("popen") { IO.popen(["echo", "x y"], &:read) + IO.popen("cat", "r+") { |io| io.write("q"); io.close_write; io.read } }
    t("system") { [system("true"), system("exit 4"), $?.exitstatus, `echo hi`] }
    t("dir") { [Dir.exist?("a"), Dir.entries("a").sort, Dir.glob("a/**/*.txt", base: ".").size, Dir["{a,z}"].sort] }
    t("rm_rf") { FileUtils.rm_rf(%w[a z lnk w.txt]); Dir.children(".") }
  end
end
