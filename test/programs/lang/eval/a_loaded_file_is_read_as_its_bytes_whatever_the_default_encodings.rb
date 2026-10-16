# load and require read a file's bytes as UTF-8 source, as ruby's
# parser does: the default external and internal encodings never
# transcode it, and a magic comment still sets its encoding.
require "tmpdir"

Dir.mktmpdir do |dir|
  utf8 = File.join(dir, "utf8.rb")
  File.write(utf8, "$utf8 = { 'Þ' => 'Th', 'ß' => 'ss' }\n")
  latin = File.join(dir, "latin.rb")
  File.binwrite(latin, "# encoding: iso-8859-1\n$latin = \"\xDE\"\n".b)
  required = File.join(dir, "required.rb")
  File.write(required, "$required = 'à'\n")

  verbose, $VERBOSE = $VERBOSE, nil
  Encoding.default_external = Encoding::US_ASCII
  Encoding.default_internal = Encoding::UTF_8
  $VERBOSE = verbose
  load utf8
  load latin
  require required
  iseq = RubyVM::InstructionSequence.compile_file(utf8)
  $VERBOSE = nil
  Encoding.default_internal = nil
  Encoding.default_external = Encoding::UTF_8
  $VERBOSE = verbose

  p $utf8, $utf8.keys.map(&:encoding)
  p $latin.encoding, $latin.bytes
  p $required, $required.encoding
  p iseq.eval
end
