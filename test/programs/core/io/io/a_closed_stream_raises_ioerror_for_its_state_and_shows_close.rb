# A closed stream answers IOError for its state, not the values it had.
%i[sync binmode binmode? lineno pid autoclose? close_on_exec? fsync fdatasync eof pos external_encoding fileno].each do |name|
  r, = IO.pipe
  r.close
  p [name, (r.public_send(name) rescue $!)]
end
[[:sync=, true], [:lineno=, 1], [:autoclose=, true], [:close_on_exec=, true], [:set_encoding, "utf-8"]].each do |name, arg|
  r, = IO.pipe
  r.close
  p [name, (r.public_send(name, arg) rescue $!)]
end
r, = IO.pipe
r.close
p r.inspect, r.to_io, r.each_line
