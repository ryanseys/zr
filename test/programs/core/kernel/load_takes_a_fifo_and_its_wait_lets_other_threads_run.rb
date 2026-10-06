# load and require take any path that is there and no directory, as
# rb_file_load_ok does: a FIFO loads, and while its read waits for a
# writer, the other threads run and one can raise in the loader.
require "tmpdir"
Dir.mktmpdir do |dir|
  fifo = File.join(dir, "f.rb")
  File.mkfifo(fifo)
  main = Thread.current
  3.times do |i|
    Thread.new do
      Thread.pass until main.stop?
      main.raise(IOError, "stopped #{i}")
    end
    begin
      load(fifo)
    rescue IOError => e
      p e.message
    end
  end
  # A writer gives the FIFO its code.
  writer = Thread.new { File.write(fifo, "$loaded = :from_fifo\n") }
  load(fifo)
  writer.join
  p $loaded
  # A directory still does not load.
  begin
    load(dir)
  rescue LoadError => e
    p e.class
  end
end
