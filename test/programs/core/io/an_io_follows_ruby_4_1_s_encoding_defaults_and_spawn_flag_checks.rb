# set_encoding(nil, nil) leaves a stream to the default external encoding
# of each read, a binary ("rb") one too. A stream opened with only an
# internal encoding converts from the default external encoding of the
# time it opened. set_encoding with two names refuses a NUL byte. The
# spawn flags close_others and unsetenv_others take true, false or nil.
$VERBOSE = nil
$stdout.sync = true
path = File.join(Dir.pwd, "io_enc_defaults_#{$$}.txt")
File.write(path, "x")
def show(label, io) = p [label, io.external_encoding, io.internal_encoding]
begin
  %w[r rb r:utf-8 w r+ rb:iso-8859-1].each do |mode|
    Encoding.default_external = Encoding::ASCII_8BIT
    Encoding.default_internal = Encoding::ISO_8859_2
    io = File.open(path, mode)
    io.set_encoding nil, nil
    Encoding.default_external = Encoding::IBM437
    Encoding.default_internal = Encoding::IBM866
    show("#{mode} from binary", io)
    io.close
    Encoding.default_external = Encoding::ISO_8859_1
    Encoding.default_internal = nil
    io = File.open(path, mode)
    io.set_encoding nil, nil
    Encoding.default_external = Encoding::IBM437
    Encoding.default_internal = Encoding::IBM866
    show("#{mode} from latin1", io)
    io.binmode if mode == "rb"
    show("#{mode} binmode again", io) if mode == "rb"
    io.close
  end
  Encoding.default_internal = nil
  Encoding.default_external = Encoding::IBM866
  io = File.open(path, mode: "r", internal_encoding: "utf-8")
  Encoding.default_external = Encoding::IBM437
  show("internal only", io)
  io.close
  io = File.open(path, mode: "r", internal_encoding: "ibm437")
  show("internal same as default", io)
  io.close
  io = File.open(path, "r")
  [[Encoding::UTF_8, "null\0byte"], ["null\0byte", Encoding::UTF_8], ["null\0byte"], ["utf-8", "utf-16le"]].each do |args|
    io.set_encoding(*args)
    p [:set, args.size, io.external_encoding, io.internal_encoding]
  rescue => e
    p [:set, e.class, e.message]
  end
  io.close
ensure
  File.delete(path)
  Encoding.default_external = Encoding::UTF_8
  Encoding.default_internal = nil
end

[[:close_others, 1], [:close_others, "true"], [:unsetenv_others, 1], [:unsetenv_others, :x], [:close_others, nil], [:unsetenv_others, false]].each do |key, value|
  IO.popen(["true", { key => value }]) { |pipe| pipe.read }
  p [key, value, :ok]
rescue ArgumentError => e
  p [key, e.message]
end
