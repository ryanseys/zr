# rb_cloexec_fcntl_dupfd: fcntl(F_DUPFD) gives a copy that closes on
# exec, as every descriptor ruby makes does.
require "fcntl"
File.open(__FILE__) do |f|
  p f.close_on_exec?
  g = IO.new(f.fcntl(Fcntl::F_DUPFD))
  p g.close_on_exec?
  p g.fileno > f.fileno
  g.close
  g = IO.new(f.fcntl(Fcntl::F_DUPFD, 40))
  p g.fileno >= 40
  p g.close_on_exec?
  g.close
  d = f.dup
  p d.close_on_exec?
  f.reopen(d)
  p f.close_on_exec?
  d.close
end
IO.pipe do |r, w|
  p [r.close_on_exec?, w.close_on_exec?]
  r.close_on_exec = false
  p r.close_on_exec?
  c = IO.new(r.fcntl(Fcntl::F_DUPFD))
  p c.close_on_exec?
  c.close
end
