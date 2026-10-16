# InstructionSequence.compile as iseqw_s_compile_parser takes its
# arguments: a nil file, path or line is the default, the options are
# checked before the source, a source that is no String raises
# TypeError, and a File is read by its path from the start, as UTF-8
# whatever the default external. compile_file takes the same options.
require "tempfile"
ISeq = RubyVM::InstructionSequence

def t(label)
  print label, ": "
  p yield
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "#{e.class}: #{e.message}"
end

t("nil") { ISeq.compile(nil) }
t("symbol") { ISeq.compile(:foo) }
t("integer") { ISeq.new(1) }
t("object to compile_prism") { ISeq.compile_prism(Object.new) }
t("nil file, path and line") { ISeq.compile("[__FILE__, __LINE__]", nil, nil, nil).eval }
t("options as a last Hash") do
  [false, true].map { |frozen| ISeq.compile("'test'", nil, nil, nil, { frozen_string_literal: frozen }).eval.frozen? }
end
t("options true") { ISeq.compile("'test'", nil, nil, nil, true).eval.frozen? }
t("options of a wrong type") { ISeq.compile("1", nil, nil, nil, 1) }
t("a String debug level") { ISeq.compile("", debug_level: "") }
t("a debug level checked first") { ISeq.compile(nil, debug_level: "") }
t("an Integer debug level") { ISeq.compile("", debug_level: 5).class }

Tempfile.create(%w[fsl .rb]) do |f|
  f.write("['foo', \"\#{1}foo\"]\n")
  f.flush
  t("compile_file with keywords") { ISeq.compile_file(f.path, frozen_string_literal: true).eval.map(&:frozen?) }
  t("compile_file with a Hash") do
    [false, true].map { |frozen| ISeq.compile_file(f.path, { frozen_string_literal: frozen }).eval.map(&:frozen?) }
  end
  t("a File at its end") { ISeq.compile_prism(f).eval }
  t("new of a File") { ISeq.new(f).eval }
  f.close
  t("a closed File") { ISeq.compile(f).eval }
end

Tempfile.create(%w[enc .rb]) do |f|
  f.puts "{ 'Þ' => 'Th', 'ß' => 'ss' }"
  f.close
  Encoding.default_external = Encoding::US_ASCII
  t("a UTF-8 file under US-ASCII") { ISeq.compile_file(f.path).eval.then { |h| [h.keys.map(&:encoding).uniq, h] } }
  Encoding.default_external = Encoding::UTF_8
end
