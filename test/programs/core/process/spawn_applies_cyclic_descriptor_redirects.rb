# A spawn whose redirects form a cycle of descriptors applies them in an
# order where no dup2 replaces one that a later one still reads.
RUBY = "ruby"
[-1, 1].each do |step|
  pipes = Array.new(5) { IO.pipe }
  ios = pipes.flatten
  h = {}
  ios.length.times { |i| h[ios[i]] = ios[(i + step) % ios.length] }
  h2 = h.invert
  wios = pipes.map { |r, w| w }
  child_wfds = wios.map { |w| h2[w].fileno }
  pid = spawn(RUBY, "-e", "[#{child_wfds.join(',')}].each {|fd| IO.new(fd, 'w').puts fd }", h)
  p pipes.map { |r, w| r.gets == "#{h2[w].fileno}\n" }
  Process.wait pid
  ios.each(&:close)
end
r, w = IO.pipe
pid = spawn("ruby", "-e", "STDOUT.puts :to_err_via_child", out: w, err: [:child, :out])
w.close
p r.read
Process.wait pid
