def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

File.write("a.txt", "l1\nl2\r\nl3")
t(:read) { [File.read("a.txt"), File.readlines("a.txt", chomp: true), File.foreach("a.txt").count, IO.readlines("a.txt", 2).size] }
t(:binread) { File.binread("a.txt", 3, 1) }
t(:open_modes) { File.open("b.txt", "w+") { |f| f.write("abc"); f.rewind; f.read } }
t(:append) { File.write("b.txt", "x", mode: "a"); File.read("b.txt") }
t(:excl) { File.open("b.txt", File::CREAT | File::EXCL | File::WRONLY) }
t(:textmode) { File.open("a.txt", "rt") { _1.read } }
t(:crlf) { File.open("a.txt", "r:utf-8", universal_newline: true) { _1.read } }
t(:enc_read) { File.write("e.txt", "é".encode("ISO-8859-1")); File.read("e.txt", encoding: "ISO-8859-1:UTF-8") }
t(:bom) { File.write("bom.txt", "﻿hi"); File.read("bom.txt", mode: "r:BOM|UTF-8") }
t(:gets_sep) { File.open("a.txt") { |f| [f.gets(""), f.gets(nil)] } }
t(:gets_limit) { File.open("a.txt") { |f| [f.gets(1), f.gets("l", 5), f.lineno, f.eof?] } }
t(:each_line) { File.open("a.txt") { |f| f.each_line(chomp: true).to_a } }
t(:readpartial) { r, w = IO.pipe; w.write("abc"); [r.readpartial(10), (r.read_nonblock(5) rescue $!.class), r.read_nonblock(5, exception: false)] }
t(:sysrw) { File.open("c.txt", "w") { |f| f.syswrite("sys") }; File.open("c.txt") { |f| [f.sysread(2), f.sysseek(0), f.sysread(3)] } }
t(:pread) { File.open("a.txt") { |f| [f.pread(2, 3), f.pos] } }
t(:stat) { s = File.stat("a.txt"); [s.size, s.file?, s.directory?, s.mode.to_s(8)[-3..].size, s.nlink, s.ftype, File.size?("nope")] }
t(:lstat_link) { File.symlink("a.txt", "lnk") rescue nil; [File.symlink?("lnk"), File.readlink("lnk"), File.realpath("lnk") == File.realpath("a.txt"), File.lstat("lnk").symlink?] }
t(:path_ops) { [File.join("a", "b/", "/c"), File.basename("/x/y.rb", ".rb"), File.extname("a.tar.gz"), File.dirname("/a/b/c", 2), File.split("/a/b"), File.expand_path("~") == Dir.home, File.absolute_path("x", "/r"), File.fnmatch("*.rb", "a.rb"), File.fnmatch("**/*.rb", "a/b/c.rb", File::FNM_PATHNAME)] }
t(:dir) { Dir.mkdir("d") rescue nil; File.write("d/x.rb", ""); File.write("d/.h", ""); [Dir.children("d").sort, Dir.glob("d/*"), Dir.glob("d/*", File::FNM_DOTMATCH).sort, Dir.glob("**/*.rb"), Dir.entries("d").sort, Dir.exist?("d"), Dir.empty?("d")] }
t(:glob_brace) { Dir.glob("{a,c}.txt").sort }
t(:glob_base) { Dir.glob("*.rb", base: "d") }
t(:dir_each) { Dir.open("d") { |d| [d.each_child.sort, d.fileno.class, d.path] } }
t(:flock) { File.open("a.txt") { |f| [f.flock(File::LOCK_EX), f.flock(File::LOCK_UN)] } }
t(:truncate) { File.write("t.txt", "12345"); File.truncate("t.txt", 2); File.read("t.txt") }
t(:utime) { File.utime(Time.at(0), Time.at(100), "t.txt"); File.mtime("t.txt").to_i }
t(:chmod) { File.chmod(0o600, "t.txt"); File.stat("t.txt").mode & 0o777 }
t(:enoent) { File.read("nope.txt") }
t(:eisdir) { File.read("d") }
t(:closed) { f = File.open("a.txt"); f.close; f.read }
t(:select) { r, w = IO.pipe; w << "x"; IO.select([r], nil, nil, 0)&.first&.size }
t(:io_wait) { require "io/wait"; r, w = IO.pipe; w << "x"; [r.ready?.class, r.wait_readable(0).class, r.nread] }
t(:io_timeout) { r, w = IO.pipe; r.timeout = 0.01; r.read(1) }
t(:copy_stream) { IO.copy_stream("a.txt", "cp.txt"); File.size("cp.txt") }
t(:stringio) { require "stringio"; s = StringIO.new(+"ab\ncd"); [s.gets, s.read, s.pos, s.ungetc("x"), s.string] }
t(:fdopen) { IO.for_fd(STDOUT.fileno, autoclose: false).fileno }
t(:sync) { [STDOUT.sync, STDERR.sync, STDIN.tty?, STDOUT.isatty] }
t(:printf) { $stdout.printf("%05.1f\n", 3.14159); $stdout << "a" << 1 << "\n"; $stdout.print("p", "q\n"); putc 65; puts }
t(:ios) { [STDIN.fileno, STDOUT.inspect, $stdin.external_encoding, STDOUT.external_encoding, Encoding.default_external, Encoding.default_internal] }
t(:tempfile) { require "tempfile"; Tempfile.create("x") { |f| f.write("q"); f.flush; File.read(f.path) } }
t(:tmpdir) { require "tmpdir"; Dir.mktmpdir { |d| File.directory?(d) } }
t(:fileutils) { require "fileutils"; FileUtils.mkdir_p("e/f/g"); FileUtils.touch("e/f/g/h"); FileUtils.cp_r("e", "e2"); FileUtils.rm_rf("e"); Dir.glob("e2/**/*").sort }
t(:pathname) { require "pathname"; p = Pathname("/a/b/../c.rb"); [p.cleanpath, p.extname, p.parent, p.relative_path_from(Pathname("/a")), Pathname("x") + "y", Pathname.new(".").children.size > 0] }
t(:argf) { ARGF.class }
t(:io_buffer) { b = IO::Buffer.new(8); b.set_value(:U32, 0, 0xdeadbeef); [b.get_value(:U32, 0), b.size, b.get_string(0, 4).bytes, IO::Buffer.for("abc").get_string] }
t(:io_buffer_rw) { r, w = IO.pipe; b = IO::Buffer.for(+"hey"); b.write(w); w.close; b2 = IO::Buffer.new(3); b2.read(r); b2.get_string }
