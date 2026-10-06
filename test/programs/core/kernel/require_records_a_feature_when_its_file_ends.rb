# A required file's feature goes into $LOADED_FEATURES when the file ends,
# after what the file added itself. A listed name with a native extension
# provides the bare name. A wrapped load's public, private and
# define_method act on the wrapper module, with a warning under -w.
require "tmpdir"
require "stringio"

Dir.mktmpdir do |tmp|
  paths, loaded = $:.dup, $".dup

  provide = File.realdirpath("provide.rb", tmp)
  File.write(File.join(tmp, "target.rb"), "raise __FILE__\n")
  File.write(provide, "$\" << 'target.rb'\n")
  $:.replace([tmp])
  p require("provide")
  p require("target")
  p $".pop == provide
  p $".pop

  # A file that requires another lists the inner one first.
  File.write(File.join(tmp, "outer.rb"), "require 'inner'\n")
  File.write(File.join(tmp, "inner.rb"), "")
  p require("outer")
  p $".last(2).map { File.basename(it) }

  # A file that fails is not listed.
  File.write(File.join(tmp, "fails.rb"), "raise 'no'\n")
  begin
    require "fails"
  rescue RuntimeError => e
    p [e.message, $".any? { it.end_with?("fails.rb") }]
  end
  $:.replace(paths)
  $".replace(loaded)

  [["foo.so"], ["foo.o"], ["foo.bundle"], ["foo"], ["a/foo.rb", "b/foo.rb"]].each do |listed|
    $LOAD_PATH.clear
    $LOADED_FEATURES.replace(listed)
    begin
      p [listed, require("foo")]
    rescue LoadError => e
      p [listed, e.message]
    end
  end
  $:.replace(paths)
  $".replace(loaded)

  File.write(File.join(tmp, "wrapped.rb"), "def a; end\npublic :a\nprivate :a\ndefine_method(:b) { 1 }\np self.class\n")
  old_err = $stderr
  $stderr = StringIO.new
  $VERBOSE = true
  p load(File.join(tmp, "wrapped.rb"), true)
  $VERBOSE = false
  text = $stderr.string
  $stderr = old_err
  puts text.gsub(tmp, "TMP")
  p Object.private_method_defined?(:a), Object.method_defined?(:b)
end
