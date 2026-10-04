# A stream that names no encodings takes the defaults as
# rb_io_ext_int_to_encs does: the external one is fixed when the
# internal default converts from it, also when the two are the same.
require "tmpdir"

Dir.mktmpdir do |dir|
  path = File.join(dir, "text.txt")
  File.write(path, "line\n")
  verbose, $VERBOSE = $VERBOSE, nil

  Encoding.default_external = Encoding::IBM866
  Encoding.default_internal = Encoding::IBM866
  %w[r r+ w a].each do |mode|
    io = File.open(path, mode)
    Encoding.default_external = Encoding::UTF_8
    p [mode, io.external_encoding, io.internal_encoding]
    io.close
    Encoding.default_external = Encoding::IBM866
  end
  File.binwrite(path, "line\n")

  Encoding.default_external = Encoding::BINARY
  Encoding.default_internal = Encoding::UTF_8
  File.open(path) do |io|
    p [io.external_encoding, io.internal_encoding, io.gets.encoding]
  end
  File.open(path) do |io|
    io.set_encoding(Encoding::IBM866)
    p [io.external_encoding, io.internal_encoding, io.gets.encoding]
  end

  Encoding.default_external = Encoding::UTF_8
  Encoding.default_internal = nil
  File.open(path) do |io|
    Encoding.default_external = Encoding::IBM437
    Encoding.default_internal = Encoding::IBM866
    io.set_encoding(nil, nil)
    p [io.external_encoding, io.internal_encoding]
  end
  Encoding.default_external = Encoding::UTF_8
  Encoding.default_internal = nil
  $VERBOSE = verbose
end
