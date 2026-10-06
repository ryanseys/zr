# io_reopen gives back what this stream read ahead before it takes the
# other stream's position, so two streams on one open file read on from
# where the reader is.
require "tmpdir"
Dir.mktmpdir do |dir|
  path = File.join(dir, "t")
  File.write(path, "foo\nbar\nbaz\n")
  File.open(__FILE__) do |f|
    f2 = File.open(path)
    f.reopen(f2)
    p f.gets, f.gets
    f.reopen(f2)
    p f.gets
    p f.gets
    f2.close
  end
  File.open(__FILE__) do |f|
    f2 = File.open(path)
    p f2.gets
    f.reopen(f2)
    p f.gets
    p f2.gets
    f2.close
  end
end
