require "tmpdir"
path = File.join(Dir.tmpdir, "zr_spawn_keep_#{$$}.txt")
File.open(path, "w") do |file|
  Process.wait Process.spawn("ruby", "-e", "f = IO.new(#{file.fileno}, 'w'); f.print(:bang); f.flush", file.fileno => file.fileno)
end
p File.read(path)
IO.pipe do |r, w|
  r.close_on_exec = false
  w.close_on_exec = false
  pid = Process.spawn("ruby", "-e", "fd = IO.for_fd(#{w.fileno}); fd.autoclose = false; fd.write 'abc'; fd.close")
  w.close
  p r.read
  Process.wait(pid)
end
IO.pipe do |r, w|
  r.close_on_exec = false
  w.close_on_exec = false
  pid = Process.spawn("ruby", "-e", "sleep 0.3", close_others: true)
  w.close
  p r.read(1)
  Process.wait(pid)
end
IO.pipe do |r, w|
  pid = Process.spawn("ruby", "-e", "sleep 0.3")
  w.close
  p r.read(1)
  Process.wait(pid)
end
File.delete(path)
