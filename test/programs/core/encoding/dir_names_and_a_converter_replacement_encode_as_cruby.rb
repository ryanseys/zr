# Dir names come in the given encoding, else the file system's, and go to
# Encoding.default_internal when it is set. A Converter converts its
# replacement once.
require "tmpdir"
r = Object.new
def r.to_str = (($n ||= 0); $n += 1; "fubar")
c = Encoding::Converter.new("us-ascii", "utf-8", replace: r)
p c.replacement, $n
Dir.mktmpdir do |d|
  File.write(File.join(d, "aé.txt"), "")
  p Dir.children(d).map(&:encoding), Dir.new(d, encoding: "euc-jp").children.map(&:encoding)
  Encoding.default_internal = "EUC-JP"
  p Dir.children(d).map(&:encoding), Dir.entries(d).map(&:encoding).uniq, Dir.new(d).children.map(&:encoding)
  Encoding.default_internal = nil
end
