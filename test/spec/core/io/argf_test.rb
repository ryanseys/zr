# frozen_string_literal: true

require "spec_helper"

describe "IO: ARGF" do
  it "ARGF reads on across its files as io.c does" do
    result = zr(<<~'RUBY')
      # ARGF reads on across its files as io.c's does: a length reads into the
      # next file, readpartial ends a file with "", and close moves on.
      File.write("/tmp/zr_af1", "abc\ndef\n")
      File.write("/tmp/zr_af2", "ghé\nij")
      def a = ARGF.class.new("/tmp/zr_af1", "/tmp/zr_af2")
      f = a
      p [f.read(2), f.read(2), f.read(5), f.read(100), f.read(1)]
      f = a
      p [f.read(2).encoding, f.read.encoding]
      f = a
      p [f.read(0), f.readpartial(3), f.readpartial(100), f.readpartial(100), f.readpartial(100), (f.readpartial(1) rescue $!)]
      f = a
      p [f.gets, f.close, f.gets, f.filename, f.closed?, f.lineno]
      f = a
      p [f.skip.filename, f.gets, f.skip.gets]
      f = a
      f.gets
      f.rewind
      p [f.gets, f.lineno]
      f = a
      f.readlines
      p [f.gets, f.read, f.filename, (f.pos rescue $!)]
      File.delete("/tmp/zr_af1", "/tmp/zr_af2")
    RUBY

    _(result).must_answer <<~'OUT'
      ["ab", "c\n", "def\ng", "h\xC3\xA9\nij", nil]
      [#<Encoding:BINARY (ASCII-8BIT)>, #<Encoding:UTF-8>]
      ["", "abc", "\ndef\n", "", "gh\xC3\xA9\nij", #<EOFError: end of file reached>]
      ["abc\n", ARGF, "ghé\n", "/tmp/zr_af2", false, 1]
      ["/tmp/zr_af1", "abc\n", "ghé\n"]
      ["abc\n", 1]
      [nil, "", "-", #<Errno::ESPIPE: Illegal seek @ rb_io_tell - <STDIN>>]
    OUT
  end

  it "a line a limit cuts counts no line, in IO and in the program's ARGF" do
    result = zr(<<~'RUBY')
      # A line that a limit cuts short counts no line, in IO and in the
      # program's ARGF; another ARGF counts every piece.
      File.write("/tmp/zr_ln", "abc\ndef\nxy")
      f = File.open("/tmp/zr_ln")
      p [f.gets(2), f.lineno, f.gets(2), f.lineno, f.gets(3), f.lineno, f.gets(5), f.lineno]
      f = File.open("/tmp/zr_ln")
      p [f.gets(nil, 2), f.lineno, f.gets(nil), f.lineno]
      ARGV.replace(["/tmp/zr_ln"])
      x = []
      ARGF.each_line(2) { x << [_1, ARGF.lineno] }
      p x
      g = ARGF.class.new("/tmp/zr_ln")
      p g.each_line(2).first(3), g.lineno
      File.delete("/tmp/zr_ln")
    RUBY

    _(result).must_answer <<~'OUT'
      ["ab", 0, "c\n", 1, "def", 1, "\n", 2]
      ["ab", 0, "c\ndef\nxy", 1]
      [["ab", 0], ["c\n", 1], ["de", 1], ["f\n", 2], ["xy", 2]]
      ["ab", "c\n", "de"]
      3
    OUT
  end
end
