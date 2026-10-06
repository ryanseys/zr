require "tmpdir"

Dir.mktmpdir do |dir|
  File.write(File.join(dir, "rq_raises.rb"), "raise 'uh oh'\n")
  File.write(File.join(dir, "rq_ok.rb"), "RQ_OK = [Ractor.main?, Ractor.current == Ractor.main].freeze\n")
  File.write(File.join(dir, "rq_syntax.rb"), "def (\n")
  $LOAD_PATH.unshift(dir)

  # The error of the required file comes back to the ractor.
  p(Ractor.new do
    require "rq_raises"
  rescue => e
    [e.class, e.message]
  end.value)

  # The file runs on the main ractor; the ractor sees its constant after.
  p Ractor.new { [require("rq_ok"), RQ_OK, Ractor.main?] }.value
  p $LOADED_FEATURES.grep(/rq_/).map { File.basename(it) }

  # A second require of the same feature gives false.
  p Ractor.new { require "rq_ok" }.value

  # A missing feature raises LoadError in the ractor.
  p(Ractor.new do
    require "rq_missing_feature"
  rescue LoadError => e
    [e.class, e.path]
  end.value)

  # A syntax error comes back as a SyntaxError.
  p(Ractor.new do
    require "rq_syntax"
  rescue SyntaxError => e
    e.class
  end.value)

  # The ractor is still not the main ractor after its require.
  p Ractor.new { require "rq_ok"; [Ractor.main?, Ractor.current == Ractor.main] }.value

  # A failed require leaves no feature behind.
  p $LOADED_FEATURES.grep(/rq_raises|rq_syntax/)
end
