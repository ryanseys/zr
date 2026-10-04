# Float() takes an underscore in a hex form only between two digits;
# exit converts its status with NUM2INT; a SystemExit at the top of
# another thread goes on in the main thread.
%w[_0x10 0_x10 0x_10 0x10 0x1_0 0x_10p10 0x10p_10 0x10_p10 0x10p10_ 0x10p10 0x1.8p0 0x1_0p1_0].each do |s|
  p [s, (Float(s) rescue $!.class), Float(s, exception: false)]
end
$rec = []
ready = false
t = Thread.new {
  Thread.pass until ready
  begin
    exit 42
  rescue SystemExit => e
    $rec << :in_thread
    raise e
  end
}
begin
  ready = true
  sleep
rescue SystemExit => e
  $rec << :in_main
  p [e.status, $rec]
end
o = Object.new
def o.to_int = 3
r = [o, 1.9, nil].map do |v|
  begin
    exit(v)
  rescue SystemExit => e
    e.status
  rescue TypeError => e
    e.class
  end
end
p r
begin
  t.value
rescue SystemExit => e
  p e.status
end
