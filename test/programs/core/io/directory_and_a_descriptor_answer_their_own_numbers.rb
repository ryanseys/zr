# A directory is an open descriptor of its own: #fileno answers the
# same number every time, and a closed directory answers nothing at
# all. A stream answers the flags fcntl reads from its descriptor, and
# a closed stream refuses that too.
require "tmpdir"

def t = yield rescue [$!.class, $!.message]

Dir.mktmpdir do |dir|
  d = Dir.new(dir)
  p d.fileno == d.fileno
  p d.fileno > 2
  d.close
  p t { d.fileno }
  p t { d.read }

  e = Dir.for_fd(File.open(dir).fileno)
  p e.fileno.is_a?(Integer)
  e.close

  f = File.open(File.join(dir, "y"), "w")
  p f.fcntl(3, 0) & 3
  p f.fcntl(3) & 3
  p f.fcntl(1, 0).is_a?(Integer)
  f.close
  p t { f.fcntl(1, 0) }

  File.open(File.join(dir, "y")) { |r| p r.fcntl(3) & 3 }
end

