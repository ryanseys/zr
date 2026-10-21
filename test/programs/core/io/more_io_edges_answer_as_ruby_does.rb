def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

File.write("a.txt", "abc\ndef\n")
t(:reopen_path) { f = File.open("a.txt"); f.gets; f.reopen("a.txt"); [f.gets, f.lineno] }
t(:reopen_io_sync) { r, w = IO.pipe; w2 = File.open("o.txt", "w"); w2.sync = true; w.sync = false; w2.reopen(w); [w2.sync, w.sync] }
t(:stderr_reopen_sync) { e = $stderr.dup; $stderr.reopen($stdout); s = $stderr.sync; $stderr.reopen(e); s }
t(:dup_pos) { f = File.open("a.txt"); f.read(2); g = f.dup; [g.read(1), f.read(1)] }
t(:fcntl) { require "fcntl"; f = File.open("a.txt"); [f.fcntl(Fcntl::F_GETFD) & Fcntl::FD_CLOEXEC, f.close_on_exec?] }
t(:fsync) { File.open("b.txt", "w") { |f| f.write("x"); [f.fsync, f.fdatasync, f.flush.class] } }
t(:autoclose) { f = File.open("a.txt"); g = IO.new(f.fileno, autoclose: false); [g.autoclose?, f.autoclose?] }
t(:binmode) { f = File.open("a.txt"); f.binmode; [f.binmode?, f.external_encoding, f.read.encoding] }
t(:set_encoding) { f = File.open("a.txt"); f.set_encoding("ISO-8859-1:UTF-8"); [f.external_encoding, f.internal_encoding] }
t(:set_encoding_by_bom) { File.write("bom.txt", "\xEF\xBB\xBFx"); File.open("bom.txt", "rb") { |f| [f.set_encoding_by_bom, f.read] } }
t(:sysopen) { fd = IO.sysopen("a.txt"); io = IO.for_fd(fd); r = io.read(3); io.close; r }
t(:pipe_enc) { r, w = IO.pipe("UTF-8:ISO-8859-1"); [r.external_encoding, r.internal_encoding] }
t(:pipe_block) { IO.pipe { |r, w| w << "q"; w.close; r.read } }
t(:mkfifo) { File.mkfifo("ff"); File.ftype("ff") }
t(:stat_more) { s = File.stat("a.txt"); [s.blksize.class, s.blocks.class, s.dev.class, s.ino.class, s.uid == Process.uid, s.birthtime.class, s.world_readable?.class, s.setuid?, s.sticky?, s.zero?, s.size?, s.owned?, s <=> s, s.inspect[0, 15]] }
t(:dir_fchdir) { d = Dir.new("."); [Dir.fchdir(d.fileno) { Dir.pwd == File.realpath(".") }, d.chdir { :ok }] }
t(:dir_for_fd) { d = Dir.new("."); Dir.for_fd(d.fileno).class }
t(:file_new_flags) { File.new("c.txt", File::WRONLY | File::CREAT | File::TRUNC, 0o644).tap { _1.write("z") }.close; File.read("c.txt") }
t(:file_open_kw) { File.open("c.txt", mode: "a", perm: 0o600, flags: File::APPEND) { _1 << "y" }; File.read("c.txt") }
t(:file_open_tmpfile) { File.open(".", File::RDWR | File::TMPFILE) rescue $!.class }
t(:lchmod) { File.symlink("a.txt", "ln") rescue nil; File.lchmod(0o644, "ln") rescue $!.class }
t(:identical) { [File.identical?("a.txt", "ln"), File.exist?("ln"), File.world_writable?("a.txt"), File.executable?("/bin/sh"), File.setgid?("a.txt")] }
t(:ioctl) { STDOUT.ioctl(0) rescue $!.class }
t(:advise) { File.open("a.txt") { |f| f.advise(:sequential) } }
t(:wait_priority) { require "io/wait"; r, w = IO.pipe; r.wait_priority(0) }
t(:nonblock) { require "io/nonblock"; r, w = IO.pipe; [r.nonblock?, (r.nonblock { r.nonblock? })] }
t(:write_multi) { r, w = IO.pipe; [w.write("a", :b, 3), w.close, r.read] }
t(:pwrite) { File.open("d.txt", "w+") { |f| f.pwrite("XY", 5); f.rewind; f.read } }
t(:readlines_limit) { File.readlines("a.txt", 2, chomp: true) }
t(:each_byte) { File.open("a.txt") { |f| f.each_byte.first(2) + [f.getbyte, f.readbyte, f.ungetbyte(65), f.getc] } }
t(:lineno_dollar) { File.open("a.txt") { |f| f.gets; f.gets; [f.lineno, $.] } }
t(:spawn_fd) { r, w = IO.pipe; pid = spawn("sh", "-c", "echo fd3 >&3", 3 => w); w.close; Process.wait(pid); r.read }
t(:spawn_close_others) { r, w = IO.pipe; pid = spawn("sh", "-c", "echo x >&#{w.fileno}", close_others: true, err: File::NULL); w.close; Process.wait(pid); [$?.success?, r.read] }
t(:spawn_unsetenv) { IO.popen({"ZQ" => "1"}, ["sh", "-c", "echo ${ZQ:-none} ${HOME:-nohome}"], unsetenv_others: true, &:read) }
t(:spawn_pgroup) { pid = spawn("sleep 0.01", pgroup: true); Process.wait(pid); $?.success? }
t(:spawn_rlimit) { IO.popen(["sh", "-c", "ulimit -n"], rlimit_nofile: 99, &:read) }
t(:spawn_in_file) { IO.popen(["cat"], in: "a.txt", &:read) }
t(:spawn_out_file) { pid = spawn("echo", "fileout", out: ["e.txt", "w"]); Process.wait(pid); File.read("e.txt") }
t(:spawn_env_nil) { ENV["DELME"] = "1"; IO.popen({"DELME" => nil}, "echo ${DELME:-gone}", &:read) }
t(:spawn_array0) { IO.popen([["sh", "argv0name"], "-c", "echo $0"], &:read) }
t(:spawn_shell_meta) { `echo a; echo b | tr a-z A-Z` }
t(:spawn_enoent) { spawn("no_such_cmd_q") }
t(:spawn_eacces) { File.write("noexec.sh", "echo"); spawn("./noexec.sh") }
t(:exec_status_127) { system("sh -c 'exit 127'"); $?.exitstatus }
t(:popen_write) { IO.popen("cat > f.txt", "w") { _1.write("piped") }; File.read("f.txt") }
t(:popen_dash) { IO.popen("-") { |io| io ? io.read : (print "from child"; exit!) } }
t(:wait_any) { pid = spawn("true"); [Process.wait == pid] }
t(:waitall) { 2.times { spawn("true") }; Process.waitall.size }
t(:wait_echild) { Process.wait }
t(:kill_0) { Process.kill(0, $$) }
t(:getpriority) { Process.getpriority(Process::PRIO_PROCESS, 0).class }
t(:sleep_ret) { [sleep(0.01).class, sleep(0)] }
t(:select_timeout) { IO.select(nil, nil, nil, 0.01) }
t(:select_write) { r, w = IO.pipe; IO.select(nil, [w], nil, 0)[1].size }
t(:syscall_kernel) { syscall(-1) rescue $!.class }
t(:closed_stdin_read) { $stdin.read }
t(:io_inspect) { File.open("a.txt") { _1.inspect } }
t(:io_closed_inspect) { f = File.open("a.txt"); f.close; f.inspect }
t(:io_path) { [File.open("a.txt", &:path), STDOUT.path, IO.pipe[0].path] rescue $!.class }
t(:io_to_path) { File.open("a.txt") { _1.to_path } }
