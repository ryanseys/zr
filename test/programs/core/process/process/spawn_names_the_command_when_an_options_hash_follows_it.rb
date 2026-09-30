[["no-such-cmd", {}], [{"A" => "1"}, "no-such-cmd", {}], [["no-such-cmd", "argv0"], {}]].each do |args|
  begin
    spawn(*args)
  rescue SystemCallError => e
    p [e.class, e.message]
  end
  p system(*args)
end
