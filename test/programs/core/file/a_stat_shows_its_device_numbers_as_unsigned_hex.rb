# File::Stat#inspect shows dev and rdev in unsigned hex, as stat_inspect
# prints a dev_t, even where the platform's dev_t is signed and the number
# reads as negative.
require "tmpdir"

[IO::NULL, Dir.tmpdir, __FILE__].each do |path|
  text = File.stat(path).inspect
  p [text.match?(/\A#<File::Stat dev=0x\h+, /), text.match?(/ rdev=0x\h+, /)]
end
