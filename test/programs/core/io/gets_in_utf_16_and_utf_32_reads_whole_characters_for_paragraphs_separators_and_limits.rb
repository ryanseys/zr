# IO#gets on a UTF-16 or UTF-32 stream with no conversion reads whole
# characters, as ruby 4.1 does (#20819): paragraph mode skips and
# matches whole newline characters, a wide separator ends a line only on
# a character start, a limit takes the character it ends in, and chomp
# and lineno agree. Pipes split a character across two writes.
$stdout.sync = true
require "tmpdir"
Dir.mktmpdir do |dir|
  path = File.join(dir, "w")
  content = "\n\n\n\nhello\n\n\n\nworld"
  encs = [Encoding::UTF_32BE, Encoding::UTF_32LE, Encoding::UTF_16BE, Encoding::UTF_16LE]
  encs.each do |e|
    encoded = content.encode(e)
    File.binwrite(path, encoded)
    File.open(path, "rb", encoding: e) { |f| p [e, :para, f.gets(""), f.gets("")] }
    [1, "\n\n\n\nhello".encode(e).bytesize + 1].each do |split|
      IO.pipe do |r, w|
        r.binmode
        r.set_encoding(e)
        t = Thread.new { w.binmode; w.write(encoded.byteslice(0, split)); sleep 0.01; w.write(encoded.byteslice(split..)); w.close }
        a = [r.gets(""), r.gets("")]
        t.join
        p [e, :pipe, split, a]
      end
    end
    sep = "\u{3042}".encode(e)
    File.binwrite(path, "one\u{3042}two\u{3042}three".encode(e))
    File.open(path, "rb", encoding: e) { |f| p [e, :sep, f.gets(sep), f.gets(sep), f.gets(sep)] }
    width = "A".encode(e).bytesize
    File.binwrite(path, "\n\nA\n\nB".encode(e))
    (1..width + 1).each do |limit|
      File.open(path, "rb", encoding: e) { |f| p [e, :plimit, limit, f.gets("", limit)] }
    end
    File.open(path, "rb", encoding: e) { |f| p [e, :chomp, f.gets("", width * 3, chomp: true)] }
    File.open(path, "rb", encoding: e) { |f| p [e, :nl, f.gets, f.gets, f.gets, f.readlines] }
    File.open(path, "rb", encoding: e) { |f| p [e, :lim2, f.gets(2), f.gets(3), f.gets(nil, 5)] }
    File.binwrite(path, "A\u{3042}B".encode(e))
    (1..width + 1).each do |limit|
      File.open(path, "rb", encoding: e) { |f| p [e, :slimit, limit, f.gets(sep, limit)] }
    end
  end
end

require "tmpdir"

def piped(e, encoded, split, &blk)
  IO.pipe do |r, w|
    r.binmode
    r.set_encoding(e)
    t = Thread.new { w.binmode; w.write(encoded.byteslice(0, split)); sleep 0.01; w.write(encoded.byteslice(split..)); w.close }
    a = blk.call(r)
    t.join
    a
  end
end

e = Encoding::UTF_16BE
enc = "\n\n\n\nh\n\nworld".encode(e)
p piped(e, enc, "\n\n\n\nh\n".encode(e).bytesize - 1) { |r| [r.gets("", 1000), r.gets("", 1000)] }
enc = "\n\n\n\nh#{'x' * 10_000}\n\nworld".encode(e)
p piped(e, enc, "\n\n\n\nh".encode(e).bytesize - 1) { |r| [r.gets(""), r.gets("")].map(&:size) }
e = Encoding::UTF_32BE
enc = "#{'x' * 2_048}\n\nworld".encode(e)
p piped(e, enc, 8_193) { |r| [r.gets(""), r.gets("")].map(&:size) }

Dir.mktmpdir do |dir|
  path = File.join(dir, "w")
  [Encoding::UTF_16LE, Encoding::UTF_32LE, Encoding::UTF_16BE].each do |e|
    File.binwrite(path, "\n\n\na\nb\n\n\n\nc\r\nd\n\n".encode(e))
    File.open(path, "rb", encoding: e) { |f| p [e, f.gets("", chomp: true), f.gets("", chomp: true), f.gets("", chomp: true)] }
    File.open(path, "rb", encoding: e) { |f| p [e, f.readlines("")] }
    File.open(path, "rb", encoding: e) { |f| p [e, f.each_line("", chomp: true).to_a] }
    File.open(path, "rb", encoding: e) { |f| p [e, f.each_line(chomp: true).to_a] }
    File.open(path, "rb", encoding: e) { |f| p [e, f.gets(""), f.lineno, f.gets("", 3), f.lineno] }
    File.binwrite(path, "\n\nab".encode(e).b + "\x00".b)
    File.open(path, "rb", encoding: e) { |f| x = f.gets(""); p [e, x, x.valid_encoding?, f.gets("")] }
    File.open(path, "rb", encoding: e) { |f| x = f.gets(nil, 3); p [e, x, f.gets(1), f.gets(1), f.gets(1)] }
  end
  # A UTF-16 file with a BOM read as the dummy UTF-16.
  File.binwrite(path, "﻿\n\nab\n\ncd".encode(Encoding::UTF_16BE))
  File.open(path, "rb", encoding: "UTF-16") { |f| p [:dummy, (f.gets("") rescue $!), (f.gets("") rescue $!)] }
  File.open(path, "rb", encoding: "BOM|UTF-16") { |f| p [:bom, f.external_encoding, f.gets(""), f.gets("")] }
  # A conversion to UTF-8.
  File.binwrite(path, "\n\nab\n\n\ncd".encode(Encoding::UTF_16LE))
  File.open(path, "rb", encoding: "UTF-16LE:UTF-8") { |f| p [:conv, f.gets(""), f.gets("")] }
  File.open(path, "r", encoding: "UTF-16LE:UTF-8") { |f| p [:convt, f.gets(""), f.gets("")] }
end
