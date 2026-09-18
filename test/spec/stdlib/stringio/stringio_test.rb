# frozen_string_literal: true

require "spec_helper"

describe "StringIO programs" do
  it "reads writes and tracks position" do
    result = ze0(<<~'RUBY')
      require "stringio"
      io = StringIO.new
      io.puts "hello"
      io.print "world"
      puts io.string.inspect
      io.rewind
      puts io.gets.inspect
      puts io.read.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "hello\nworld"
      "hello\n"
      "world"
    OUT
  end

  it "string io answers the same off either implementation" do
    result = ze0(<<~'RUBY')
      # stringio -- the differential matrix all three implementations answer:
      # ruby's C gem (the recorded text), zeo's native ext, and the pure port.
      require "stringio"

      def t(label)
        print label, ": "
        p yield
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      s = StringIO.new("line one\nline two\nline three\n")
      t("class") { s.class }
      t("read4") { s.read(4) }
      t("pos") { s.pos }
      t("gets") { s.gets }
      t("lineno") { s.lineno }
      t("gets_chomp") { s.gets(chomp: true) }
      t("gets_limit") { s.gets(3) }
      t("gets_sep") { s.gets("ee") }
      t("rest") { s.read }
      t("eof") { s.eof? }
      t("read_at_eof") { s.read }
      t("read4_at_eof") { s.read(4) }
      t("rewind") { [s.rewind, s.pos, s.lineno] }
      t("each_line") { ls = []; s.each_line { |l| ls << l }; ls }
      t("readlines") { s.rewind; s.readlines(chomp: true) }

      # Bytes and characters.
      b = StringIO.new("héllo")
      t("getc") { b.getc }
      t("getc2") { b.getc }
      t("getbyte") { b.getbyte }
      t("ungetbyte") { b.ungetbyte(0x41); b.read }
      t("ungetc_head") { b.rewind; b.ungetc("XY"); b.read }
      t("each_char") { b.rewind; b.each_char.to_a }
      t("each_byte_n") { b.rewind; b.each_byte.to_a.length }
      t("each_codepoint") { b.rewind; b.each_codepoint.to_a }
      t("readchar_eof") { b.read; b.readchar }
      t("readbyte_eof") { b.readbyte }
      t("getbyte_eof") { b.getbyte }

      # Writing.
      w = StringIO.new
      t("write") { w.write("ab", "cd") }
      t("putc") { w.putc(0x65) }
      t("putc_str") { w.putc("fgh") }
      t("print") { w.print("i", "j") }
      t("puts") { w.puts("k", ["l", "m"]) }
      t("printf") { w.printf("%04d!", 42) }
      t("shovel") { (w << "z" << 9).string }
      t("size") { w.size }
      t("sync") { w.sync }

      # Position games: seek, overwrite mid-string, past-end zero fill.
      o = StringIO.new(+"abcdef")
      t("seek") { [o.seek(2), o.pos] }
      t("overwrite") { o.write("XY"); o.string }
      t("seek_end") { [o.seek(-1, IO::SEEK_END), o.read] }
      t("seek_cur") { o.seek(2); [o.seek(1, IO::SEEK_CUR), o.pos] }
      t("past_end") { o.pos = 9; o.write("!"); o.string }
      t("seek_neg") { o.seek(-1) }
      t("truncate") { [o.truncate(3), o.string] }
      t("truncate_grow") { [o.truncate(6), o.string.bytes] }
      t("truncate_neg") { o.truncate(-2) }

      # Append and read-write modes; mode errors.
      t("append") { a = StringIO.new(+"ab", "a"); a << "c"; a.string }
      t("append_seek") { a = StringIO.new(+"ab", "a"); a.rewind; a.write("Z"); a.string }
      t("readonly_write") { StringIO.new("x", "r").write("y") }
      t("writeonly_read") { StringIO.new(+"x", "w").read }
      t("w_truncates") { StringIO.new(+"long", "w").string }
      t("bad_mode") { StringIO.new(+"x", "q") }
      t("frozen_write") { StringIO.new("frozen".freeze).write("y") }
      t("frozen_mode_w") { StringIO.new("frozen".freeze, "w") }

      # The buffer is SHARED, never a copy.
      sh = +"shared"
      shio = StringIO.new(sh)
      t("shared_read") { shio.read(2) }
      t("shared_mutate") { sh[0] = "S"; shio.read }
      t("string_eq") { shio.string = +"swapped"; [shio.pos, shio.lineno, shio.read] }

      # Paragraph mode, and nil separators.
      para = StringIO.new("one\n\n\ntwo\nstill two\n\nthree\n")
      t("paragraphs") { para.each_line("").to_a }
      t("gets_nil") { para.rewind; para.gets(nil) }

      # readpartial / read_nonblock / sysread.
      r = StringIO.new("abc")
      t("readpartial") { r.readpartial(2) }
      t("readpartial_buf") { buf = +""; r.readpartial(2, buf); buf }
      t("readpartial_eof") { r.readpartial(2) }
      t("read_nonblock_eof") { r.read_nonblock(2) }
      t("read_nonblock_exc") { r.read_nonblock(2, exception: false) }
      t("sysread_eof") { r.sysread(1) }

      # Close halves.
      c = StringIO.new(+"cl")
      t("close_read") { c.close_read; c.read }
      t("closed_read?") { [c.closed_read?, c.closed_write?, c.closed?] }
      t("close_write") { c.close_write; c.write("x") }
      t("closed_all") { [c.closed?, c.string] }
      t("reread_closed") { c.gets }
      t("close") { c2 = StringIO.new; c2.close; [c2.closed?, (c2.string rescue $!.class)] }

      # IO-flavored odds and ends.
      i = StringIO.new("x")
      t("fileno") { i.fileno }
      t("isatty") { i.isatty }
      t("pid") { i.pid }
      t("flush") { i.flush == i }
      t("fsync") { i.fsync }
      t("binmode") { [i.binmode == i, i.external_encoding] }
      t("internal_enc") { i.internal_encoding }
      t("external_enc") { StringIO.new("é").external_encoding }
      t("set_encoding") { e = StringIO.new(+"é"); e.set_encoding("binary"); [e.external_encoding, e.read.bytes.length] }
      t("open_block") { StringIO.open("blk") { |io| io.read(3) } }
      t("marshal") { Marshal.dump(StringIO.new) }
      t("each_with_sep_limit") { StringIO.new("aXbXcX").each_line("X", 2).to_a }
      t("lineno_tracks_gets") { g = StringIO.new("a\nb\nc\n"); g.gets; g.gets; g.lineno }
      t("lineno_eq") { g = StringIO.new("a\nb\n"); g.lineno = 7; g.gets; g.lineno }
      t("tell") { g = StringIO.new("abc"); g.read(1); g.tell }
      t("pos_eq_neg") { StringIO.new("abc").pos = -1 }
      t("inspect_shape") { StringIO.new.inspect.start_with?("#<StringIO:0x") }
    RUBY

    _(result).must_answer <<~'OUT'
      class: StringIO
      read4: "line"
      pos: 4
      gets: " one\n"
      lineno: 1
      gets_chomp: "line two"
      gets_limit: "lin"
      gets_sep: "e three"
      rest: "\n"
      eof: true
      read_at_eof: ""
      read4_at_eof: nil
      rewind: [0, 0, 0]
      each_line: ["line one\n", "line two\n", "line three\n"]
      readlines: ["line one", "line two", "line three"]
      getc: "h"
      getc2: "é"
      getbyte: 108
      ungetbyte: "Alo"
      ungetc_head: "XYhéAlo"
      each_char: ["X", "Y", "h", "é", "A", "l", "o"]
      each_byte_n: 8
      each_codepoint: [88, 89, 104, 233, 65, 108, 111]
      readchar_eof: EOFError: end of file reached
      readbyte_eof: EOFError: end of file reached
      getbyte_eof: nil
      write: 4
      putc: 101
      putc_str: "fgh"
      print: nil
      puts: nil
      printf: nil
      shovel: "abcdefijk\nl\nm\n0042!z9"
      size: 21
      sync: true
      seek: [0, 2]
      overwrite: "abXYef"
      seek_end: [0, "f"]
      seek_cur: [0, 3]
      past_end: "abXYef\u0000\u0000\u0000!"
      seek_neg: Errno::EINVAL: Invalid argument
      truncate: [0, "abX"]
      truncate_grow: [0, [97, 98, 88, 0, 0, 0]]
      truncate_neg: Errno::EINVAL: Invalid argument - negative length
      append: "abc"
      append_seek: "abZ"
      readonly_write: IOError: not opened for writing
      writeonly_read: IOError: not opened for reading
      w_truncates: ""
      bad_mode: ArgumentError: invalid access mode q
      frozen_write: IOError: not opened for writing
      frozen_mode_w: Errno::EACCES: Permission denied
      shared_read: "sh"
      shared_mutate: "ared"
      string_eq: [0, 0, "swapped"]
      paragraphs: ["one\n\n\n", "two\nstill two\n\n", "three\n"]
      gets_nil: "one\n\n\ntwo\nstill two\n\nthree\n"
      readpartial: "ab"
      readpartial_buf: "c"
      readpartial_eof: EOFError: end of file reached
      read_nonblock_eof: EOFError: end of file reached
      read_nonblock_exc: nil
      sysread_eof: EOFError: end of file reached
      close_read: IOError: not opened for reading
      closed_read?: [true, false, false]
      close_write: IOError: not opened for writing
      closed_all: [true, "cl"]
      reread_closed: IOError: not opened for reading
      close: [true, ""]
      fileno: nil
      isatty: false
      pid: nil
      flush: true
      fsync: 0
      binmode: [true, #<Encoding:BINARY (ASCII-8BIT)>]
      internal_enc: nil
      external_enc: #<Encoding:UTF-8>
      set_encoding: [#<Encoding:BINARY (ASCII-8BIT)>, 2]
      open_block: "blk"
      marshal: TypeError: no _dump_data is defined for class StringIO
      each_with_sep_limit: ["aX", "bX", "cX"]
      lineno_tracks_gets: 2
      lineno_eq: 8
      tell: 1
      pos_eq_neg: Errno::EINVAL: Invalid argument
      inspect_shape: true
    OUT
  end

  it "a StringIO held in an ivar takes packed bytes and reads them back whole" do
    result = ze0(<<~'RUBY')
      require "stringio"

      class Bits
        def initialize
          @io = StringIO.new
        end

        def add(byte)
          @io.write([byte].pack("C"))
        end

        def head(s)
          @io << s
        end

        def out
          @io.string
        end
      end

      b = Bits.new
      b.head("hdr\n")
      [0, 8, 0, 255, 0].each { |v| b.add(v) }
      b.head("!")
      p b.out.bytes
      p b.out.bytesize

      io = StringIO.new
      io << "a\0b"
      io.write("\0")
      io.print("x\0y")
      p io.string.bytes
      p io.size
    RUBY

    _(result).must_answer <<~'OUT'
      [104, 100, 114, 10, 0, 8, 0, 255, 0, 33]
      10
      [97, 0, 98, 0, 120, 0, 121]
      7
    OUT
  end

  it "getbyte and each_byte read bytes, so a multi-byte character does not make them skip" do
    result = ze0(<<~'RUBY')
      # `StringIO`'s BYTE-wise reads. Distinct from `getc`'s character-wise ones: a
      # multi-byte encoding must not make a byte reader skip. prism's deserializer
      # walks its buffer entirely through `getbyte`.
      require "stringio"

      s = StringIO.new("ab")
      p s.getbyte
      p s.getbyte
      p s.getbyte
      p s.eof?

      s.rewind
      p s.readbyte
      p s.pos

      begin
        StringIO.new("").readbyte
      rescue EOFError => e
        p [e.class, e.message]
      end

      # A multi-byte character reads one byte at a time here, where `getc` answers
      # the whole character.
      utf8 = StringIO.new("é")
      p utf8.getbyte
      p utf8.getbyte
      p utf8.getbyte
      p StringIO.new("é").getc
    RUBY

    _(result).must_answer <<~'OUT'
      97
      98
      nil
      true
      97
      1
      [EOFError, "end of file reached"]
      195
      169
      nil
      "é"
    OUT
  end

  it "the mode string decides every read, write, truncate and append the StringIO allows" do
    result = ze0(<<~'RUBY')
      # StringIO's mode string decides what it allows, and the whole table is
      # here because every row of it was previously ignored.
      #
      # Append starting at position 0 was DATA CORRUPTION, not a missing error:
      # `StringIO.new("ab", "a").write("c")` answered `"cb"`. Three more rows are
      # surprising enough to pin: `"a"` is NOT readable, `"w"` truncates on open,
      # and append ignores `pos` entirely -- every write goes to the end however
      # the position was set.

      require "stringio"
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { s = StringIO.new(+"abc", "a"); s.write("d"); s.string }
      show { StringIO.new(+"abc", "a").read }
      show { StringIO.new(+"abc", "w").string }
      show { s = StringIO.new(+"abc", "w"); s.write("z"); s.string }
      show { StringIO.new(+"abc", "r").write("y") }
      show { StringIO.new(+"abc", "r").read }
      show { s = StringIO.new(+"abc", "r+"); s.write("z"); s.string }
      show { s = StringIO.new(+"abc", "a+"); s.write("d"); [s.string, (s.rewind; s.read)] }
      show { StringIO.new("frozen", "w") }
      show { StringIO.new("frozen", "r").read }
      show { s = StringIO.new(+"abc", "r"); s.puts("x") }
      show { s = StringIO.new(+"abc", "r"); s.print("x") }
      show { s = StringIO.new(+"abc", "r"); s << "x" }
      show { s = StringIO.new(+"abc", "r"); s.truncate(1) }
      show { s = StringIO.new(+"abc"); s.write("z"); s.string }
    RUBY

    _(result).must_answer <<~'OUT'
      "abcd"
      IOError: not opened for reading
      ""
      "z"
      IOError: not opened for writing
      "abc"
      "zbc"
      ["abcd", "abcd"]
      #<StringIO:0xADDR>
      "frozen"
      IOError: not opened for writing
      IOError: not opened for writing
      IOError: not opened for writing
      IOError: not opened for writing
      "zbc"
    OUT
  end

  it "each_line, readlines and gets take chomp:, and printf is public on the receiver" do
    result = ze0(<<~'RUBY')
      # `StringIO` is meant to be drop-in for an `IO`, which is what makes it the
      # standard way to capture output or feed a parser in a test. Three of IO's
      # methods are missing or mis-scoped on it:
      #
      #   * `each_line(chomp: true)` -- the keyword is rejected as a positional arg
      #     ("wrong number of arguments (given 1, expected 0)"). `readlines`/`gets`
      #     take it too.
      #   * `printf` -- resolves to the PRIVATE `Kernel#printf` rather than a public
      #     `IO#printf`, so an explicit receiver is refused.
      #   * `each_char` -- absent entirely.
      #
      # The shared cause is that zeo's StringIO carries its own hand-written row set
      # rather than inheriting IO's, so a name IO has and StringIO's list omits simply
      # is not there. `each_line` and `readlines` DO exist; only their `chomp:`
      # keyword is unmodelled.

      require 'stringio'

      s = StringIO.new("a\nb\n")
      p s.each_line(chomp: true).to_a

      p StringIO.new("a\nb\n").readlines(chomp: true)

      out = StringIO.new
      out.printf("%05d", 42)
      p out.string

      p StringIO.new("ab").each_char.to_a

      # What already works, so a fix must not disturb it.
      p StringIO.new("a\nb\n").each_line.to_a
      p StringIO.new("a\nb").readlines
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      ["a", "b"]
      "00042"
      ["a", "b"]
      ["a\n", "b\n"]
      ["a\n", "b"]
    OUT
  end

  it "StringIO.open yields the io, answers the block's value, and closes it afterwards" do
    result = ze0(<<~'RUBY')
      # `StringIO.open(string) { |io| ... }` must YIELD the new StringIO to the
      # block and answer the block's value, closing the io afterwards -- the same
      # contract `File.open` has. zeo's row builds the StringIO and returns it,
      # dropping the block entirely, so the answer is the io rather than what the
      # block computed.
      #
      # Found while adding the payload-root class-method probe for value subclasses
      # (`B.open` on a `class B < StringIO`); this is the BASE class, so it is not a
      # subclassing bug. Fix: the `StringIO.open` row has to call the block with the
      # constructed io and return its value.
      require "stringio"

      p StringIO.open("hi") { |f| f.read }
      p StringIO.open("a\nb") { |f| f.readlines }

      # Without a block it answers the io, which zeo already does.
      p StringIO.open("hi").class

      # The io is closed once the block returns.
      io = nil
      StringIO.open("x") { |f| io = f }
      p io.closed?
    RUBY

    _(result).must_answer <<~'OUT'
      "hi"
      ["a\n", "b"]
      StringIO
      true
    OUT
  end

  it "ungetbyte pushes a byte back for the next read to take" do
    result = ze0(<<~'RUBY')
      require "stringio"

      s = StringIO.new("hello")
      p s.read(2)
      p s.ungetbyte(65)
      p s.read
    RUBY

    _(result).must_answer <<~'OUT'
      "he"
      nil
      "Allo"
    OUT
  end

  it "ungetc pushes a character back for the next read to take" do
    result = ze0(<<~'RUBY')
      require "stringio"

      s = StringIO.new("hello")
      p s.read(2)
      p s.getc
      p s.ungetc("Z")
      p s.read
    RUBY

    _(result).must_answer <<~'OUT'
      "he"
      "l"
      nil
      "Zlo"
    OUT
  end

  it "append mode seeks to the end before each write, and a read-only io refuses one" do
    result = ze0(<<~'RUBY')
      # StringIO's write modes: append mode seeks to the END before each write
      # (zeo overwrites from position 0 -- "cb" instead of "abc": data
      # corruption, not a missing error), and a read-only StringIO refuses a
      # write with IOError (zeo writes and answers the byte count). (Found by
      # the 2026-08-24 probe sweep.)
      require "stringio"
      s = StringIO.new(+"ab", "a")
      s.write("c")
      p s.string
      begin
        StringIO.new("x", "r").write("y")
      rescue IOError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "abc"
      not opened for writing
    OUT
  end

  it "subclassing stringio and file" do
    result = ze0(<<~'RUBY')
      # A user subclass of a builtin carries the builtin's native object as a
      # payload. `StringIO` and `File` join Array/String/Hash/StringScanner as
      # payload roots: puma's `IOBuffer < StringIO` and aws-sdk's `ManagedFile <
      # File` are between them the whole aws-sdk-* family's blocker.
      #
      # `File` is the first root whose own methods are mostly INHERITED -- `read`
      # lives on `IO` -- so the payload bridge follows the root's builtin
      # superclasses, and stops before Object (`Buffer.new.class` is `Buffer`, not
      # `StringIO`).

      require "stringio"
      require "tmpdir"
      require "set"

      class Buffer < StringIO
        def dump = "<#{string}>"
      end

      b = Buffer.new("hello")
      p b.dump
      p b.read
      p [b.is_a?(StringIO), b.class, Buffer.superclass]

      class Managed < File
        def open? = !closed?
      end

      path = File.join(Dir.tmpdir, "zeo_value_subclass_example.txt")
      File.write(path, "data")
      f = Managed.new(path)
      p [f.open?, f.read, f.class]
      f.close
      p f.open?
      File.unlink(path)

      class Tags < Set
        def label = "tags(#{size})"
      end

      t = Tags.new([1, 2, 2])
      t << 3
      p [t.to_a.sort, t.label, t.class, t.is_a?(Set)]

      # `Enumerator`: the payload is the enumerator handle, and like `File` there is
      # no empty form -- the block IS the sequence -- so a subclass with its own
      # `initialize` seats one through `super() { |y| ... }`. cucumber-messages'
      # `NdjsonToMessageEnumerator` is that shape; the eighteen aws-sdk `EventStream`
      # classes are the other one, adding a method to the inherited behaviour.
      class Ndjson < Enumerator
        def initialize(lines)
          super() do |y|
            lines.each { |l| y.yield(l.upcase) }
          end
        end
      end

      n = Ndjson.new(["a", "b"])
      p [n.class, n.to_a, n.is_a?(Enumerator), n.next]

      class EventStream < Enumerator
        def event_types = [:records, :stats]
      end

      s = EventStream.new { |y| y.yield 1; y.yield 2 }
      # `map` builds a NEW Array, so it demotes; `to_a` does too. The receiver keeps
      # its own class either way.
      p [s.class, s.event_types, s.to_a, s.map { |x| x * 10 }]

      # CLASS methods inherited from the payload root. Nothing copies a builtin's
      # class-method table rows onto a subclass entry the way materialization copies
      # a user `def self.x`, so without the root probe these are invisible --
      # rubyzip's `DOSTime.from_time` calls the inherited `local` directly.
      class DOSTime < Time
        def self.from_time(t)
          local(t.year, t.month, t.day, t.hour, t.min, t.sec)
        end

        def to_binary_dos_date = day + (month << 5) + ((year - 1980) << 9)
      end

      d = DOSTime.utc(2024, 5, 6, 7, 8, 9)
      # CRuby allocates through the RECEIVER class, so every one of these is a
      # DOSTime, not a Time.
      p [d.class, d.year, d.month, d.day, d.to_binary_dos_date, d.utc?]
      p [DOSTime.now.class, DOSTime.at(0).class, DOSTime.from_time(Time.utc(1999, 3, 4)).class]
      p [DOSTime.respond_to?(:local), DOSTime.respond_to?(:nope)]
      # `_load` is a PRIVATE class method of Time, so it stays unreachable here --
      # exactly as an inherited private class method is in CRuby.
      p DOSTime.respond_to?(:_load)
      # The conversions are the exception: CRuby answers with the BASE class even
      # when the receiver is a subclass.
      class Widen < Array; end
      p [Widen[1, 2].class, Widen.try_convert([1]).class]

      class Stamped < Time
        def initialize(*args)
          super
          @tag = "s"
        end

        attr_reader :tag
      end

      s = Stamped.new(2000, 1, 2)
      p [s.class, s.year, s.month, s.day, s.tag]

      # `Thread`: the `File` shape again -- a blockless thread cannot be built, so
      # a subclass seats the real one through `super`, which is exactly why
      # newrelic_rpm and celluloid subclass it.
      class Traced < Thread
        attr_accessor :busy

        def initialize(*args, &block)
          @busy = false
          super(*args) { |*a| block.call(*a) }
        end

        def celluloid? = true
      end

      t = Traced.new(3) { |n| n * 2 }
      p [t.class, t.value, t.celluloid?, t.is_a?(Thread)]
      t.busy = true
      p t.busy

      # Which inherited class methods re-tag as the subclass is a PER-METHOD fact,
      # not "the result is a root value": `Thread.current` hands back a thread that
      # already exists, and `Enumerator.produce` builds a plain Enumerator, while
      # `Time.now` and `Array[]` allocate through the receiver. All four are CRuby's
      # own answers.
      p [Traced.current.class, Thread.current.class]

      class Seq < Enumerator; end
      p [Seq.produce(1) { |x| x + 1 }.first(2), Seq.produce(1) { |x| x + 1 }.class]

      class Bag < Hash; end
      p [Bag[[[1, 2]]].class, Bag.try_convert({}).class]

      # `Range`: chronic's `Span < Range`. Its class-method table had no `new` row
      # until one was added for exactly this path -- the prerequisite `Enumerator`
      # needed too. `Range.new` demands both endpoints, so no empty payload form.
      class Span < Range
        def width = (self.end - self.begin).to_i
        def +(seconds) = Span.new(self.begin + seconds, self.end + seconds)
        def to_s = "(" + self.begin.to_s + ".." + self.end.to_s + ")"
      end

      sp = Span.new(10, 40)
      p [sp.class, sp.width, sp.begin, sp.end, sp.to_s]
      p [(sp + 5).class, (sp + 5).to_s]
      p [sp.is_a?(Range), sp.include?(20), sp.to_a.size]
      p Span.new(1, 3, true).to_a

      # `Zlib::GzipWriter` takes the same shape as its reader: the subclass's own
      # `initialize` seats the real IO through `super`, and the whole compressor
      # surface is inherited.
      require "zlib"

      class TaggedGz < Zlib::GzipWriter
        def initialize(io)
          super(io)
          @tag = :tagged
        end

        attr_reader :tag
      end

      buf = StringIO.new(+"", "wb")
      gz = TaggedGz.new(buf)
      p gz.class
      p gz.tag
      p gz.is_a?(Zlib::GzipWriter)
      gz.write("hello gzip")
      gz.close
      p Zlib::GzipReader.new(StringIO.new(buf.string, "rb")).read
    RUBY

    _(result).must_answer <<~'OUT'
      "<hello>"
      "hello"
      [true, Buffer, StringIO]
      [true, "data", Managed]
      false
      [[1, 2, 3], "tags(3)", Tags, true]
      [Ndjson, ["A", "B"], true, "A"]
      [EventStream, [:records, :stats], [1, 2], [10, 20]]
      [DOSTime, 2024, 5, 6, 22694, true]
      [DOSTime, DOSTime, DOSTime]
      [true, false]
      false
      [Widen, Array]
      [Stamped, 2000, 1, 2, "s"]
      [Traced, 6, true, true]
      true
      [Thread, Thread]
      [[1, 2], Enumerator]
      [Bag, Hash]
      [Span, 30, 10, 40, "(10..40)"]
      [Span, "(15..45)"]
      [true, true, 31]
      [1, 2]
      TaggedGz
      :tagged
      true
      "hello gzip"
    OUT
  end
end
