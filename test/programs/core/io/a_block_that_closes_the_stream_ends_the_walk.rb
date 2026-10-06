# Each character's walk checks the stream after the block: a block that
# closes it ends the walk with IOError, though bytes wait in the buffer.
require "tmpdir"
Dir.mktmpdir do |dir|
  path = File.join(dir, "t")
  File.write(path, "ab\ncd")
  # CRuby's each_char crashes on a text-mode file that the block closes.
  [:each_codepoint].each do |name|
    seen = []
    File.open(path, "rt") do |f|
      f.public_send(name) do |c|
        seen << c
        f.close if c == "\n" || c == 10
      end
    rescue IOError => e
      p [name, seen, e.message]
    end
  end
  [:each_char, :each_codepoint].each do |name|
    IO.pipe do |r, w|
      w.print("abc def")
      w.close
      seen = []
      r.public_send(name) do |c|
        seen << c
        r.close if c == " " || c == 32
      end
    rescue IOError => e
      p [name, seen, e.message]
    end
  end
  # A block that closes nothing reads to the end.
  File.open(path) { |f| p f.each_char.to_a.size }
end
