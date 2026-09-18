# frozen_string_literal: true

require "spec_helper"

describe "IO: encodings" do
  it "file closes and stats through io" do
    result = ze0(<<~'RUBY')
      # File#close, File#stat and File#to_path are IO's rows: a File has no
      # rows of its own for them. IO has no p and no codepoints.

      File.open(__FILE__) { |f| p [f.stat.size > 0, f.to_path == __FILE__] }
      f = File.new(__FILE__)
      p f.close, f.closed?, f.close
      begin
        f.stat
      rescue IOError => e
        p e
      end
      p File.instance_method(:close).owner, File.instance_method(:stat).owner, File.instance_method(:to_path).owner
      p $stdout.respond_to?(:p), $stdin.respond_to?(:codepoints)

    RUBY

    _(result).must_answer <<~'OUT'
      [true, true]
      nil
      true
      nil
      #<IOError: closed stream>
      IO
      IO
      IO
      false
      false
    OUT
  end

  it "full write buffer joins text of any encoding" do
    result = ze0(<<~'RUBY')
      # A write that fills the buffer joins text in any two encodings: the
      # buffer holds bytes.
      $stdout.write "é".b * 4095
      puts "é" * 10
      $stdout.write "\n"
      p $stdout.write("x".b * 9000, "日")

    RUBY

    _(result).must_answer <<~'OUT'
      ééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé

      xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx日9003
    OUT
  end

  it "IO::Buffer reads typed values, shares a slice, maps a file and transfers straight to an IO" do
    result = ze0(<<~'RUBY')
      # IO::Buffer: typed value access, slices over shared backing, masks, file
      # mapping, and direct IO transfer. Addresses are scrubbed (the one
      # nondeterminism); PAGE_SIZE is platform-dependent so only its shape prints.
      $stderr.reopen(IO::NULL)
      SCRUB = ->(s) { s.gsub(/0x\h{9,}/, "0xN") }

      # ---- constants and the error tree.
      p IO::Buffer::PAGE_SIZE >= 4096
      p IO::Buffer::PAGE_SIZE % 4096 == 0
      p IO::Buffer::DEFAULT_SIZE
      p [IO::Buffer::EXTERNAL, IO::Buffer::INTERNAL, IO::Buffer::MAPPED, IO::Buffer::SHARED,
         IO::Buffer::LOCKED, IO::Buffer::PRIVATE, IO::Buffer::READONLY]
      p [IO::Buffer::LITTLE_ENDIAN, IO::Buffer::BIG_ENDIAN, IO::Buffer::NETWORK_ENDIAN]
      p IO::Buffer::HOST_ENDIAN == IO::Buffer::LITTLE_ENDIAN
      p [IO::Buffer::LockedError.superclass, IO::Buffer::AllocationError.superclass,
         IO::Buffer::AccessError.superclass, IO::Buffer::InvalidatedError.superclass,
         IO::Buffer::MaskError.superclass]
      p IO::Buffer.ancestors[0..2]

      # ---- construction.
      p IO::Buffer.new(16).size
      p IO::Buffer.new(0).size
      begin
        IO::Buffer.new(-1)
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      p [IO::Buffer.size_of(:U32), IO::Buffer.size_of([:U32, :U8]), IO::Buffer.size_of(:f64)]
      begin
        IO::Buffer.size_of(:bogus)
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      p IO::Buffer.string(5) { |b| b.set_string("abcde") }

      # ---- predicates.
      b = IO::Buffer.new(16)
      p [b.valid?, b.null?, b.empty?, b.external?, b.internal?, b.mapped?, b.shared?,
         b.locked?, b.readonly?, b.private?]
      p [IO::Buffer.new(0).null?, IO::Buffer.new(0).empty?]

      # ---- typed values.
      b.set_value(:U32, 0, 0xdeadbeef)
      p [b.get_value(:U32, 0), b.get_value(:u32, 0)]
      p b.set_value(:U8, 0, 256)
      p b.set_value(:U8, 1, -1)
      p b.get_values([:U8, :U8], 0)
      p b.set_values([:U8, :u16], 4, [7, 513])
      p b.get_values([:U8, :u16], 4)
      w = IO::Buffer.new(16)
      w.set_value(:u64, 0, 2**63 + 5)
      p [w.get_value(:u64, 0), w.get_value(:s64, 0)]
      w.set_value(:U128, 0, 2**100)
      p w.get_value(:U128, 0)
      w.set_value(:f32, 0, 1.5)
      p w.get_value(:f32, 0)
      w.set_value(:F64, 8, -2.25)
      p w.get_value(:F64, 8)
      begin
        b.get_value(:U32, 14)
      rescue ArgumentError => e
        p [e.class, e.message]
      end

      # ---- strings.
      s = IO::Buffer.new(8)
      p s.set_string("hi")
      p s.get_string
      p s.get_string(0, 2, Encoding::UTF_8).encoding
      begin
        s.set_string("way too long to fit here")
      rescue ArgumentError => e
        p [e.class, e.message]
      end

      # ---- slices share the backing.
      sl = b.slice(4, 8)
      p sl.size
      sl.set_value(:U8, 0, 42)
      p b.get_value(:U8, 4)
      p [b.slice.size, b.slice(8).size]
      begin
        b.slice(12, 8)
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      begin
        b.slice(-1, 2)
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      r = IO::Buffer.new(8)
      r.set_value(:U8, 0, 7)
      rs = r.slice(0, 4)
      r.resize(16)
      p [r.size, r.get_value(:U8, 0), rs.get_value(:U8, 0), rs.valid?]

      # ---- free / null / transfer.
      f = IO::Buffer.new(8)
      f.free
      p [f.valid?, f.null?, f.size]
      t = IO::Buffer.new(8)
      t.set_value(:U8, 0, 9)
      t2 = t.transfer
      p [t2.get_value(:U8, 0), t.null?, t.valid?]

      # ---- locked.
      l = IO::Buffer.new(8)
      p l.locked { |x| [x.equal?(l), l.locked?] }
      p l.locked?
      begin
        l.locked { l.locked { } }
      rescue IO::Buffer::LockedError => e
        p [e.class, e.message]
      end
      begin
        l.locked { l.resize(16) }
      rescue IO::Buffer::LockedError => e
        p [e.class, e.message]
      end
      begin
        l.locked { l.free }
      rescue IO::Buffer::LockedError => e
        p [e.class, e.message]
      end

      # ---- readonly.
      ro = IO::Buffer.for("readonly str")
      p [ro.size, ro.readonly?]
      p ro.get_string(0, 8)
      begin
        ro.set_value(:U8, 0, 1)
      rescue IO::Buffer::AccessError => e
        p [e.class, e.message]
      end
      begin
        ro.clear
      rescue IO::Buffer::AccessError => e
        p [e.class, e.message]
      end

      # ---- copy.
      a = IO::Buffer.new(8)
      src = IO::Buffer.for("abcdefgh").dup
      p a.copy(src)
      p a.get_string
      p a.copy(src, 4, 2)
      p a.get_string
      p a.copy(src, 0, 4, 4)
      p a.get_string
      begin
        a.copy(src, 6, 4)
      rescue ArgumentError => e
        p [e.class, e.message]
      end

      # ---- comparison.
      c1 = IO::Buffer.for("abc").dup
      c2 = IO::Buffer.for("abd").dup
      c3 = IO::Buffer.for("abc").dup
      p [c1 <=> c2, c2 <=> c1, c1 <=> c3]
      p [c1 == c3, c1 == c2]
      p [c1 <=> IO::Buffer.for("ab").dup, IO::Buffer.for("ab").dup <=> c1]
      p [c1 < c2, c1 >= c3, c1.between?(c3, c2)]
      begin
        c1 <=> "abc"
      rescue TypeError => e
        p [e.class, e.message]
      end

      # ---- bitwise + masks.
      m = IO::Buffer.for("\x0f\xf0\xff\x00").dup
      k = IO::Buffer.for("\xff\xff\x0f\x0f").dup
      p (m & k).get_string.bytes
      p (m | k).get_string.bytes
      p (m ^ k).get_string.bytes
      p (~m).get_string.bytes
      p (m & IO::Buffer.for("\x01\x02").dup).get_string.bytes
      mm = IO::Buffer.for("\x0f\xf0").dup
      mm.and!(IO::Buffer.for("\xff\x00").dup)
      p mm.get_string.bytes
      mm.or!(IO::Buffer.for("\x00\x01").dup)
      p mm.get_string.bytes
      mm.xor!(IO::Buffer.for("\xff\xff").dup)
      p mm.get_string.bytes
      mm.not!
      p mm.get_string.bytes
      mm.and!(IO::Buffer.for("\x01").dup)
      p mm.get_string.bytes
      begin
        mm & IO::Buffer.new(0)
      rescue IO::Buffer::MaskError => e
        p [e.class, e.message]
      end
      begin
        mm.and!(IO::Buffer.new(0))
      rescue IO::Buffer::MaskError => e
        p [e.class, e.message]
      end

      # ---- iteration.
      e = IO::Buffer.for("\x01\x02\x03\x04").dup
      acc = []
      e.each(:U8) { |off, v| acc << [off, v] }
      p acc
      acc = []
      e.each(:u16) { |off, v| acc << [off, v] }
      p acc
      acc = []
      e.each(:U8, 1, 2) { |off, v| acc << [off, v] }
      p acc
      p e.each(:U8).class
      p e.values(:U8)
      p e.values(:u16, 2)
      acc = []
      e.each_byte { |x| acc << x }
      p acc
      p e.each_byte.to_a

      # ---- clear.
      p IO::Buffer.for("abcdefgh").dup.clear(0x2a).get_string
      p IO::Buffer.for("abcdefgh").dup.clear(0, 2).get_string
      p IO::Buffer.for("abcdefgh").dup.clear(9, 2, 4).get_string
      p IO::Buffer.for("ab").dup.clear.get_string.bytes

      # ---- hexdump and inspect.
      h = IO::Buffer.for("0123456789abcdefghij").dup
      puts h.hexdump
      puts h.hexdump(4)
      puts h.hexdump(4, 8)
      puts h.hexdump(0, 20, 8)
      p SCRUB.(IO::Buffer.new(4).inspect)
      p SCRUB.(IO::Buffer.new(4).slice(1, 2).inspect)
      p SCRUB.(IO::Buffer.for("literal").inspect)
      p SCRUB.(IO::Buffer.for("literal").dup.inspect)
      fz = IO::Buffer.new(4)
      fz.free
      p SCRUB.(fz.inspect)
      p SCRUB.(IO::Buffer.new(4).to_s)
      lk = IO::Buffer.new(4)
      lk.locked { p SCRUB.(lk.inspect.lines.first) }
      big = IO::Buffer.new(300)
      p big.inspect.lines.length
      p big.inspect.lines.last

      # ---- direct IO.
      path = "/tmp/zeo_io_buffer_fixture.txt"
      File.write(path, "ABCDEFGHIJKLMNOPQR")
      fh = File.open(path)
      rb = IO::Buffer.new(10)
      p rb.read(fh)
      p rb.get_string
      rb2 = IO::Buffer.new(10)
      rb2.clear(0x2e)
      p rb2.pread(fh, 3, 4, 6)
      p rb2.get_string
      wpath = "/tmp/zeo_io_buffer_fixture_w.txt"
      File.write(wpath, "")
      wh = File.open(wpath, "r+")
      wsrc = IO::Buffer.for("0123456789").dup
      p wsrc.write(wh)
      p wsrc.write(wh, 3, 7)
      wh.flush
      p File.read(wpath)
      p wsrc.pwrite(wh, 0, 3, 5)
      wh.flush
      p File.read(wpath)
      closed = File.open(path)
      closed.close
      begin
        rb.read(closed)
      rescue IOError => e
        p [e.class, e.message]
      end

      # ---- map.
      mp = IO::Buffer.map(File.open(path, "r"), nil, 0, IO::Buffer::READONLY)
      p [mp.size, mp.readonly?, mp.mapped?, mp.get_string(0, 4)]
      p SCRUB.(mp.inspect.lines.first)
      rw = IO::Buffer.map(File.open(path, "r+"))
      p [rw.size, rw.readonly?]
      rw.set_string("ZZ")
      p File.read(path)[0, 4]
      p IO::Buffer.map(File.open(path, "r+"), nil, 0, IO::Buffer::PRIVATE).private?

      # ---- for block form: writable view, write-back at exit.
      mut = +"mutable str"
      res = IO::Buffer.for(mut) { |bb| p [bb.readonly?, bb.size, bb.external?]; bb.set_string("X"); :blockresult }
      p res
      p mut

      # ---- dup and initialize_copy.
      d = IO::Buffer.for("dup me").dup
      p [d.readonly?, d.internal?, d.get_string]
      orig = IO::Buffer.new(4)
      orig.set_value(:U8, 0, 5)
      cp = orig.dup
      cp.set_value(:U8, 0, 9)
      p [orig.get_value(:U8, 0), cp.get_value(:U8, 0)]
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      65536
      [1, 2, 4, 8, 32, 64, 128]
      [4, 8, 8]
      true
      [RuntimeError, RuntimeError, RuntimeError, RuntimeError, ArgumentError]
      [IO::Buffer, Comparable, Object]
      16
      0
      [ArgumentError, "Size can't be negative!"]
      [4, 5, 8]
      [ArgumentError, "Invalid type name!"]
      "abcde"
      [true, false, false, false, true, false, false, false, false, false]
      [true, true]
      [3735928559, 4022250974]
      1
      2
      [0, 255]
      7
      [7, 513]
      [9223372036854775813, -9223372036854775803]
      1267650600228229401496703205376
      1.5
      -2.25
      [ArgumentError, "Type extends beyond end of buffer! (offset=14 > size=16)"]
      2
      "hi\x00\x00\x00\x00\x00\x00"
      #<Encoding:UTF-8>
      [ArgumentError, "Specified offset+length is bigger than the buffer size!"]
      8
      42
      [16, 8]
      [ArgumentError, "Specified offset+length is bigger than the buffer size!"]
      [ArgumentError, "Offset can't be negative!"]
      [16, 7, 7, true]
      [true, true, 0]
      [9, true, true]
      [true, true]
      false
      [IO::Buffer::LockedError, "Buffer already locked!"]
      [IO::Buffer::LockedError, "Cannot resize locked buffer!"]
      [IO::Buffer::LockedError, "Buffer is locked!"]
      [12, true]
      "readonly"
      [IO::Buffer::AccessError, "Buffer is not writable!"]
      [IO::Buffer::AccessError, "Buffer is not writable!"]
      8
      "abcdefgh"
      2
      "abcdabgh"
      4
      "efghabgh"
      [ArgumentError, "Specified offset+length is bigger than the buffer size!"]
      [-1, 1, 0]
      [true, false]
      [1, -1]
      [true, true, true]
      [TypeError, "wrong argument type String (expected IO::Buffer)"]
      [15, 240, 15, 0]
      [255, 255, 255, 15]
      [240, 15, 240, 15]
      [240, 15, 0, 255]
      [1, 0, 1, 0]
      [15, 0]
      [15, 1]
      [240, 254]
      [15, 1]
      [1, 1]
      [IO::Buffer::MaskError, "Zero-length mask given!"]
      [IO::Buffer::MaskError, "Zero-length mask given!"]
      [[0, 1], [1, 2], [2, 3], [3, 4]]
      [[0, 513], [2, 1027]]
      [[1, 2], [2, 3]]
      Enumerator
      [1, 2, 3, 4]
      [1027]
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      "********"
      "ab\x00\x00\x00\x00\x00\x00"
      "ab\t\t\t\tgh"
      [0, 0]
      0xADDR  30 31 32 33 34 35 36 37 38 39 61 62 63 64 65 66 0123456789abcdef
      0xADDR  67 68 69 6a                                     ghij
      0xADDR  34 35 36 37 38 39 61 62 63 64 65 66 67 68 69 6a 456789abcdefghij
      0xADDR  34 35 36 37 38 39 61 62                         456789ab
      0xADDR  30 31 32 33 34 35 36 37 01234567
      0xADDR  38 39 61 62 63 64 65 66 89abcdef
      0xADDR  67 68 69 6a             ghij
      "#<IO::Buffer 0xN+4 INTERNAL>\n0xADDR  00 00 00 00                                     ...."
      "#<IO::Buffer 0xN+2 SLICE>\n0xADDR  00 00                                           .."
      "#<IO::Buffer 0xN+7 EXTERNAL READONLY SLICE>\n0xADDR  6c 69 74 65 72 61 6c                            literal"
      "#<IO::Buffer 0xN+7 INTERNAL>\n0xADDR  6c 69 74 65 72 61 6c                            literal"
      "#<IO::Buffer 0xN+0 NULL>"
      "#<IO::Buffer 0xN+4 INTERNAL>"
      "#<IO::Buffer 0xN+4 INTERNAL LOCKED>\n"
      18
      "(and 44 more bytes not printed)"
      10
      "ABCDEFGHIJ"
      4
      "......DEFG"
      10
      3
      "0123456789789"
      5
      "5678956789789"
      [IOError, "closed stream"]
      [18, true, true, "ABCD"]
      "#<IO::Buffer 0xN+18 EXTERNAL MAPPED FILE SHARED READONLY>\n"
      [18, false]
      "ZZCD"
      true
      [false, 11, true]
      :blockresult
      "Xutable str"
      [false, true, "dup me"]
      [5, 9]
    OUT
  end

  it "the mode argument of IO.new over a descriptor decides the external encoding" do
    result = ze0(<<~'RUBY')
      # `IO.new(fd, mode, **opts)` -- the same mode and the same options `File.open`
      # takes, and they mean the same things.
      #
      # zeo's row was `(fd, mode?)`: the mode was READ and then dropped, no option was
      # ever looked at, and a third argument was `wrong number of arguments (given 3,
      # expected 1..2)`. So a handle over a descriptor always reported UTF-8 whatever
      # it was asked for, and irb's
      #
      #   IO.open(STDOUT.to_i, 'w', external_encoding: enc, internal_encoding: "-")
      #
      # could not be built at all -- which is where `IRB.start` died.
      require "tmpdir"
      require "fileutils"

      DIR = Dir.mktmpdir("zeo_io_open_opts")
      SRC = File.join(DIR, "src.txt")
      File.binwrite(SRC, "hello\nworld\n")

      # Every row gets a descriptor of its own, and whatever the row builds owns it:
      # closing one fd twice is a real error, not a test detail.
      def row(name, mode = "r")
        fd = IO.sysopen(SRC, mode)
        made = nil
        begin
          value, made = yield fd
          puts "#{name}\t#{value.inspect}"
        rescue StandardError => e
          puts "#{name}\t#{e.class}: #{e.message}"
        ensure
          if made
            made.close
          else
            begin
              IO.for_fd(fd).close
            rescue SystemCallError
              nil
            end
          end
        end
      end

      def encs(io)
        [[io.external_encoding&.name, io.internal_encoding&.name], io]
      end

      # --- the mode argument -------------------------------------------------------
      row("no mode")            { |fd| encs(IO.new(fd)) }
      row("mode r")             { |fd| encs(IO.new(fd, "r")) }
      row("mode rb")            { |fd| encs(IO.new(fd, "rb")) }
      row("mode r:enc")         { |fd| encs(IO.new(fd, "r:EUC-JP")) }
      row("mode r:ext:int")     { |fd| encs(IO.new(fd, "r:EUC-JP:UTF-8")) }
      # A `-` where the internal encoding goes asks for NO transcoding. There is no
      # encoding by that name, so looking one up would warn about correct spelling.
      row("mode r:ext:-")       { |fd| encs(IO.new(fd, "r:EUC-JP:-")) }
      row("mode: keyword")      { |fd| encs(IO.new(fd, mode: "r:EUC-JP")) }
      row("mode as O_ flags")   { |fd| encs(IO.new(fd, File::RDONLY)) }
      # `b` claims the external slot only when nothing NAMED an encoding.
      row("mode rb:enc")        { |fd| io = IO.new(fd, "rb:UTF-8"); [[io.external_encoding.name, io.binmode?], io] }

    RUBY

    _(result).must_answer <<~'OUT'
      no mode	["UTF-8", nil]
      mode r	["UTF-8", nil]
      mode rb	["ASCII-8BIT", nil]
      mode r:enc	["EUC-JP", nil]
      mode r:ext:int	["EUC-JP", "UTF-8"]
      mode r:ext:-	["EUC-JP", nil]
      mode: keyword	["EUC-JP", nil]
      mode as O_ flags	["UTF-8", nil]
      mode rb:enc	["UTF-8", true]
    OUT
  end

  it "external_encoding: and internal_encoding: on IO.new are read, not dropped" do
    result = ze0(<<~'RUBY')
      # `IO.new(fd, mode, **opts)` -- the same mode and the same options `File.open`
      # takes, and they mean the same things.
      #
      # zeo's row was `(fd, mode?)`: the mode was READ and then dropped, no option was
      # ever looked at, and a third argument was `wrong number of arguments (given 3,
      # expected 1..2)`. So a handle over a descriptor always reported UTF-8 whatever
      # it was asked for, and irb's
      #
      #   IO.open(STDOUT.to_i, 'w', external_encoding: enc, internal_encoding: "-")
      #
      # could not be built at all -- which is where `IRB.start` died.
      require "tmpdir"
      require "fileutils"

      DIR = Dir.mktmpdir("zeo_io_open_opts")
      SRC = File.join(DIR, "src.txt")
      File.binwrite(SRC, "hello\nworld\n")

      # Every row gets a descriptor of its own, and whatever the row builds owns it:
      # closing one fd twice is a real error, not a test detail.
      def row(name, mode = "r")
        fd = IO.sysopen(SRC, mode)
        made = nil
        begin
          value, made = yield fd
          puts "#{name}\t#{value.inspect}"
        rescue StandardError => e
          puts "#{name}\t#{e.class}: #{e.message}"
        ensure
          if made
            made.close
          else
            begin
              IO.for_fd(fd).close
            rescue SystemCallError
              nil
            end
          end
        end
      end

      def encs(io)
        [[io.external_encoding&.name, io.internal_encoding&.name], io]
      end

      # --- the options Hash --------------------------------------------------------
      row("external_encoding:")  { |fd| encs(IO.new(fd, external_encoding: "EUC-JP")) }
      row("internal_encoding:")  { |fd| encs(IO.new(fd, external_encoding: "EUC-JP", internal_encoding: "UTF-8")) }
      row("internal_encoding: -"){ |fd| encs(IO.new(fd, external_encoding: "EUC-JP", internal_encoding: "-")) }
      row("internal_encoding: nil") { |fd| encs(IO.new(fd, external_encoding: "EUC-JP", internal_encoding: nil)) }
      row("encoding:")           { |fd| encs(IO.new(fd, encoding: "EUC-JP")) }
      row("encoding: ext:int")   { |fd| encs(IO.new(fd, encoding: "EUC-JP:UTF-8")) }
      row("encoding: ext:-")     { |fd| encs(IO.new(fd, encoding: "EUC-JP:-")) }
      row("binmode:")            { |fd| encs(IO.new(fd, binmode: true)) }
      row("textmode:")           { |fd| encs(IO.new(fd, textmode: true)) }
      row("path:")               { |fd| io = IO.new(fd, path: "labelled"); [io.path, io] }
      row("autoclose: false")    { |fd| io = IO.new(fd, autoclose: false); [io.autoclose?, io] }
      # An option nobody knows is ignored, not refused.
      row("unknown option")      { |fd| io = IO.new(fd, no_such_option: 1); [io.class, io] }

    RUBY

    _(result).must_answer <<~'OUT'
      external_encoding:	["EUC-JP", nil]
      internal_encoding:	["EUC-JP", "UTF-8"]
      internal_encoding: -	["EUC-JP", nil]
      internal_encoding: nil	["EUC-JP", nil]
      encoding:	["EUC-JP", nil]
      encoding: ext:int	["EUC-JP", "UTF-8"]
      encoding: ext:-	["EUC-JP", nil]
      binmode:	["ASCII-8BIT", nil]
      textmode:	["UTF-8", nil]
      path:	"labelled"
      autoclose: false	false
      unknown option	IO
    OUT
  end

  it "a mode and an options hash together give irb the handle it opens stdout with" do
    result = ze0(<<~'RUBY')
      # `IO.new(fd, mode, **opts)` -- the same mode and the same options `File.open`
      # takes, and they mean the same things.
      #
      # zeo's row was `(fd, mode?)`: the mode was READ and then dropped, no option was
      # ever looked at, and a third argument was `wrong number of arguments (given 3,
      # expected 1..2)`. So a handle over a descriptor always reported UTF-8 whatever
      # it was asked for, and irb's
      #
      #   IO.open(STDOUT.to_i, 'w', external_encoding: enc, internal_encoding: "-")
      #
      # could not be built at all -- which is where `IRB.start` died.
      require "tmpdir"
      require "fileutils"

      DIR = Dir.mktmpdir("zeo_io_open_opts")
      SRC = File.join(DIR, "src.txt")
      File.binwrite(SRC, "hello\nworld\n")

      # Every row gets a descriptor of its own, and whatever the row builds owns it:
      # closing one fd twice is a real error, not a test detail.
      def row(name, mode = "r")
        fd = IO.sysopen(SRC, mode)
        made = nil
        begin
          value, made = yield fd
          puts "#{name}\t#{value.inspect}"
        rescue StandardError => e
          puts "#{name}\t#{e.class}: #{e.message}"
        ensure
          if made
            made.close
          else
            begin
              IO.for_fd(fd).close
            rescue SystemCallError
              nil
            end
          end
        end
      end

      def encs(io)
        [[io.external_encoding&.name, io.internal_encoding&.name], io]
      end

      # --- mode AND options together: the shape irb needs --------------------------
      row("mode + opts")         { |fd| encs(IO.new(fd, "r", external_encoding: "EUC-JP", internal_encoding: "-")) }
      row("open + mode + opts")  { |fd| encs(IO.open(fd, "r", external_encoding: "EUC-JP", internal_encoding: "-")) }
      row("for_fd + mode + opts"){ |fd| encs(IO.for_fd(fd, "r", external_encoding: "EUC-JP", internal_encoding: "-")) }

    RUBY

    _(result).must_answer <<~'OUT'
      mode + opts	["EUC-JP", nil]
      open + mode + opts	["EUC-JP", nil]
      for_fd + mode + opts	["EUC-JP", nil]
    OUT
  end

  it "IO.new refuses a bad access mode and an unknown encoding name" do
    result = ze0(<<~'RUBY')
      # `IO.new(fd, mode, **opts)` -- the same mode and the same options `File.open`
      # takes, and they mean the same things.
      #
      # zeo's row was `(fd, mode?)`: the mode was READ and then dropped, no option was
      # ever looked at, and a third argument was `wrong number of arguments (given 3,
      # expected 1..2)`. So a handle over a descriptor always reported UTF-8 whatever
      # it was asked for, and irb's
      #
      #   IO.open(STDOUT.to_i, 'w', external_encoding: enc, internal_encoding: "-")
      #
      # could not be built at all -- which is where `IRB.start` died.
      require "tmpdir"
      require "fileutils"

      DIR = Dir.mktmpdir("zeo_io_open_opts")
      SRC = File.join(DIR, "src.txt")
      File.binwrite(SRC, "hello\nworld\n")

      # Every row gets a descriptor of its own, and whatever the row builds owns it:
      # closing one fd twice is a real error, not a test detail.
      def row(name, mode = "r")
        fd = IO.sysopen(SRC, mode)
        made = nil
        begin
          value, made = yield fd
          puts "#{name}\t#{value.inspect}"
        rescue StandardError => e
          puts "#{name}\t#{e.class}: #{e.message}"
        ensure
          if made
            made.close
          else
            begin
              IO.for_fd(fd).close
            rescue SystemCallError
              nil
            end
          end
        end
      end

      def encs(io)
        [[io.external_encoding&.name, io.internal_encoding&.name], io]
      end

      # --- what is refused ---------------------------------------------------------
      # An access mode naming nothing is refused at the call, not on the first read.
      row("bad access mode")     { |fd| encs(IO.new(fd, "zz")) }
      # The read/write bits asked for must be a subset of the descriptor's own.
      row("mode the fd cannot serve") { |fd| encs(IO.new(fd, "w")) }
      row("O_RDWR over a read-only fd") { |fd| encs(IO.new(fd, File::RDWR)) }
      row("encoding named twice"){ |fd| encs(IO.new(fd, "r:EUC-JP", encoding: "UTF-8")) }
      row("mode is not a String"){ |fd| encs(IO.new(fd, Object.new)) }
      begin
        IO.new("/etc/hosts")
      rescue TypeError => e
        puts "fd is not an Integer\t#{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      bad access mode	ArgumentError: invalid access mode zz
      mode the fd cannot serve	Errno::EINVAL: Invalid argument
      O_RDWR over a read-only fd	Errno::EINVAL: Invalid argument
      encoding named twice	ArgumentError: encoding specified twice
      mode is not a String	TypeError: no implicit conversion of Object into String
      fd is not an Integer	no implicit conversion of String into Integer
    OUT
  end

  it "IO.open over a descriptor yields the handle and closes it after the block" do
    result = ze0(<<~'RUBY')
      # `IO.new(fd, mode, **opts)` -- the same mode and the same options `File.open`
      # takes, and they mean the same things.
      #
      # zeo's row was `(fd, mode?)`: the mode was READ and then dropped, no option was
      # ever looked at, and a third argument was `wrong number of arguments (given 3,
      # expected 1..2)`. So a handle over a descriptor always reported UTF-8 whatever
      # it was asked for, and irb's
      #
      #   IO.open(STDOUT.to_i, 'w', external_encoding: enc, internal_encoding: "-")
      #
      # could not be built at all -- which is where `IRB.start` died.
      require "tmpdir"
      require "fileutils"

      DIR = Dir.mktmpdir("zeo_io_open_opts")
      SRC = File.join(DIR, "src.txt")
      File.binwrite(SRC, "hello\nworld\n")

      # Every row gets a descriptor of its own, and whatever the row builds owns it:
      # closing one fd twice is a real error, not a test detail.
      def row(name, mode = "r")
        fd = IO.sysopen(SRC, mode)
        made = nil
        begin
          value, made = yield fd
          puts "#{name}\t#{value.inspect}"
        rescue StandardError => e
          puts "#{name}\t#{e.class}: #{e.message}"
        ensure
          if made
            made.close
          else
            begin
              IO.for_fd(fd).close
            rescue SystemCallError
              nil
            end
          end
        end
      end

      def encs(io)
        [[io.external_encoding&.name, io.internal_encoding&.name], io]
      end

      # --- the block form still closes --------------------------------------------
      fd = IO.sysopen(SRC, "r")
      p IO.open(fd, "r:EUC-JP") { |io| [io.external_encoding.name, io.read(5)] }

    RUBY

    _(result).must_answer <<~'OUT'
      ["EUC-JP", "hello"]
    OUT
  end

  it "a write handle built over a descriptor carries its encoding and writes" do
    result = ze0(<<~'RUBY')
      # `IO.new(fd, mode, **opts)` -- the same mode and the same options `File.open`
      # takes, and they mean the same things.
      #
      # zeo's row was `(fd, mode?)`: the mode was READ and then dropped, no option was
      # ever looked at, and a third argument was `wrong number of arguments (given 3,
      # expected 1..2)`. So a handle over a descriptor always reported UTF-8 whatever
      # it was asked for, and irb's
      #
      #   IO.open(STDOUT.to_i, 'w', external_encoding: enc, internal_encoding: "-")
      #
      # could not be built at all -- which is where `IRB.start` died.
      require "tmpdir"
      require "fileutils"

      DIR = Dir.mktmpdir("zeo_io_open_opts")
      SRC = File.join(DIR, "src.txt")
      File.binwrite(SRC, "hello\nworld\n")

      # Every row gets a descriptor of its own, and whatever the row builds owns it:
      # closing one fd twice is a real error, not a test detail.
      def row(name, mode = "r")
        fd = IO.sysopen(SRC, mode)
        made = nil
        begin
          value, made = yield fd
          puts "#{name}\t#{value.inspect}"
        rescue StandardError => e
          puts "#{name}\t#{e.class}: #{e.message}"
        ensure
          if made
            made.close
          else
            begin
              IO.for_fd(fd).close
            rescue SystemCallError
              nil
            end
          end
        end
      end

      def encs(io)
        [[io.external_encoding&.name, io.internal_encoding&.name], io]
      end

      # --- a write handle ----------------------------------------------------------
      DST = File.join(DIR, "dst.txt")
      File.binwrite(DST, "")
      wfd = IO.sysopen(DST, "w")
      w = IO.new(wfd, "w", external_encoding: "EUC-JP", internal_encoding: "-")
      p [w.external_encoding.name, w.internal_encoding&.name]
      w.write("written")
      w.close
      p File.read(DST)

      FileUtils.remove_entry(DIR)
      puts "ran to the end"
    RUBY

    _(result).must_answer <<~'OUT'
      ["EUC-JP", nil]
      "written"
      ran to the end
    OUT
  end

  it "IO.write truncates only when no offset says where the write goes" do
    result = ze0(<<~'RUBY')
      # IO.write opens with O_WRONLY|O_CREAT and truncates only when no offset
      # says where the write goes, as io_s_write does; binwrite writes binary.

      path = "iow_tmp.txt"
      File.delete(path) if File.exist?(path)
      p IO.write(path, "abc", 3)
      p File.binread(path)
      p IO.write(path, "Z", 1)
      p File.binread(path)
      p File.write(path, "hey")
      p File.binread(path)
      p IO.binwrite(path, "\xFF\xFE", 1)
      p File.binread(path)
      p File.write(path, "more", mode: "a")
      p File.binread(path)
      p File.write(path, "é", encoding: "UTF-16LE")
      p File.binread(path)
      p IO.binwrite(path, "q", mode: "a")
      p File.binread(path)
      begin
        File.write(path, "x", -1)
      rescue => e
        p e.class
      end
      p File.binread(path)
      p File.binwrite(path, "done")
      p File.read(path)
      File.delete(path)
      p IO.respond_to?(:written, true)

    RUBY

    _(result).must_answer <<~'OUT'
      3
      "\x00\x00\x00abc"
      1
      "\x00Z\x00abc"
      3
      "hey"
      2
      "h\xFF\xFE"
      4
      "h\xFF\xFEmore"
      2
      "\xE9\x00"
      1
      "\xE9\x00q"
      Errno::EINVAL
      "\xE9\x00q"
      4
      "done"
      false
    OUT
  end

  it "mode is checked before the descriptor" do
    result = ze0(<<~'RUBY')
      # CRuby asks whether a handle is OPEN for the direction before it touches
      # the descriptor, so a read of a write-only handle is an `IOError` naming
      # the mode -- never the kernel's `EBADF`, and never a made-up answer.
      #
      # Zeo asked at three rows and not at the other seventeen. Four of the
      # unguarded ones did not even raise: `getc` answered a NUL character,
      # `getbyte` answered 0, `readchar` and `readbyte` answered the same, and
      # `eof?` answered `true`. A byte that is not there, reported as data.
      #
      # The guard sits in the read FUNNEL (`with_buffered_file`) rather than at
      # each row, plus the few rows that reach the descriptor another way. That
      # is the difference between fixing seventeen rows and stopping the
      # eighteenth being written.
      #
      # `each_byte` is NOT here: it is a decided divergence, and
      # `tests/each_byte_on_a_write_only_handle.rb` records it.

      require "tmpdir"

      def show(name)
        r = yield
        puts "#{name}\t#{r.inspect}"
      rescue Exception => e
        puts "#{name}\t#{e.class}: #{e.message.sub(/ - .*/, '')}"
      end

      Dir.mktmpdir do |dir|
        path = File.join(dir, "f")
        File.write(path, "abcd\nefgh\n")

        # A WRITE-only handle refuses every read.
        File.open(path, "w") do |f|
          %w[read gets getc getbyte readchar readbyte readline readlines
             readpartial sysread read_nonblock each_line each_char
             each_codepoint eof?].each do |m|
            show(m) do
              case m
              when "readpartial", "sysread", "read_nonblock" then f.send(m, 2)
              when /^each/ then f.send(m) { |_| }
              else f.send(m)
              end
            end
          end
        end

        # A READ-only handle refuses every write.
        File.write(path, "abcd\n")
        File.open(path, "r") do |f|
          %w[write print << puts printf putc syswrite write_nonblock
             truncate].each do |m|
            show(m) do
              case m
              when "printf" then f.printf("%s", "x")
              when "putc" then f.putc(65)
              when "truncate" then f.truncate(1)
              else f.send(m, "x")
              end
            end
          end
        end

        # The refusals changed nothing on disk.
        show("content") { File.read(path) }

        # A READ-WRITE handle refuses neither.
        File.open(path, "r+") do |f|
          show("rw read") { f.read }
          show("rw write") { f.write("z") }
          show("rw eof?") { f.eof? }
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      read	IOError: not opened for reading
      gets	IOError: not opened for reading
      getc	IOError: not opened for reading
      getbyte	IOError: not opened for reading
      readchar	IOError: not opened for reading
      readbyte	IOError: not opened for reading
      readline	IOError: not opened for reading
      readlines	IOError: not opened for reading
      readpartial	IOError: not opened for reading
      sysread	IOError: not opened for reading
      read_nonblock	IOError: not opened for reading
      each_line	IOError: not opened for reading
      each_char	IOError: not opened for reading
      each_codepoint	IOError: not opened for reading
      eof?	IOError: not opened for reading
      write	IOError: not opened for writing
      print	IOError: not opened for writing
      <<	IOError: not opened for writing
      puts	IOError: not opened for writing
      printf	IOError: not opened for writing
      putc	IOError: not opened for writing
      syswrite	IOError: not opened for writing
      write_nonblock	IOError: not opened for writing
      truncate	IOError: not opened for writing
      content	"abcd\n"
      rw read	"abcd\n"
      rw write	1
      rw eof?	true
    OUT
  end

  it "partial read and the path levels follow cruby" do
    result = ze0(<<~'RUBY')
      # A partial read takes what one read(2) gives rather than waiting for
      # the whole length, which is why a reader of a pipe does not stop until
      # the writer closes it. Beside it: ungetc of an Integer puts that
      # codepoint back, absolute_path leaves a leading tilde where
      # expand_path spells it out, and dirname refuses a negative level.
      require "tmpdir"

      def t = yield rescue [$!.class, $!.message]

      r, w = IO.pipe
      w.write "x"
      p r.readpartial(100)
      w.write "yz"
      p r.sysread(100)
      p r.readpartial(0)
      w.close
      p t { r.readpartial(10) }
      r.close

      Dir.mktmpdir do |dir|
        path = File.join(dir, "note.txt")
        File.write(path, "hello\n")
        File.open(path) do |f|
          p f.getc
          p f.ungetc(65)
          p f.read
        end
        File.open(path) do |f|
          f.getc
          f.ungetbyte(66)
          p f.read
        end
      end

      p File.absolute_path("~").end_with?("/~")
      p File.absolute_path?("~")
      p File.expand_path("~").start_with?("/")
      p t { File.dirname("a/b", -1) }
      p File.dirname("a/b/c", 2)
      p File.dirname("a/b/c", 0)
      p File.dirname("/a/b", 5)

    RUBY

    _(result).must_answer <<~'OUT'
      "x"
      "yz"
      ""
      [EOFError, "end of file reached"]
      "h"
      nil
      "Aello\n"
      "Bello\n"
      true
      false
      true
      [ArgumentError, "negative level: -1"]
      "a"
      "a/b/c"
      "/"
    OUT
  end

  it "puts of one string writes it and a newline" do
    result = ze0(<<~'RUBY')
      # puts with one String argument writes its bytes and a newline unless
      # it ends in one, into the same buffer the other forms fill, so the
      # output keeps its order across puts, print, write and $stdout swaps.
      $stdout.puts "one"
      puts "two\n"
      puts ""
      print "three"
      puts "four"
      $stdout.write("five", "\n")
      puts "six", "seven"
      puts ["eight", ["nine"]], nil, 10, :eleven
      puts "twelve\n\n"
      puts "thirteen".encode("UTF-16LE").force_encoding("BINARY").bytesize
      puts "héllo", "日本".encode("Shift_JIS").force_encoding("BINARY").bytes.size
      class Quiet
        def write(*parts) = ($seen ||= []) << parts.join
      end
      old = $stdout
      $stdout = Quiet.new
      puts "fourteen"
      puts "fifteen\n"
      $stdout = old
      p $seen
      r, w = IO.pipe
      w.sync = false
      w.puts "sixteen"
      w.puts "seventeen\n"
      w.puts ""
      w.flush
      w.close
      p r.read
      s = String.new("mutable")
      puts s
      s << "!"
      puts s
      p (STDOUT.puts("x".freeze)), $stdout.puts
      STDERR.puts "eighteen"

    RUBY

    _(result).must_answer <<~'OUT', stderr: "eighteen\n"
      one
      two

      threefour
      five
      six
      seven
      eight
      nine

      10
      eleven
      twelve

      16
      héllo
      4
      ["fourteen\n", "fifteen\n"]
      "sixteen\nseventeen\n\n"
      mutable
      mutable!
      x

      nil
      nil
    OUT
  end

  it "write converts to the external encoding" do
    result = ze0(<<~'RUBY')
      # A stream that names an external encoding writes in it, as do_writeconv
      # converts: through UTF-8 to one that is not ASCII-compatible, and not at
      # all where the encoding is binary.

      path = "wenc.txt"
      File.open(path, "w", encoding: "UTF-16LE") { |f| f.write "é" }
      p File.binread(path)
      File.open(path, "w:UTF-16LE") { |f| p f.print "é"; f << "a"; p f.write("bc") }
      p File.binread(path)
      File.open(path, "w", external_encoding: "EUC-JP") { |f| f.puts "日本" }
      p File.binread(path)
      File.open(path, "w:UTF-8") { |f| f.write "é".encode("EUC-JP") }
      p File.binread(path)
      begin
        File.open(path, "w:UTF-16LE") { |f| f.write "\xff".b }
      rescue => e
        p e
      end
      File.open(path, "w:UTF-16LE") { |f| f.write "a".b; f.write "\xff" } rescue p $!
      p File.binread(path)
      File.open(path, "wb:UTF-16LE") { |f| f.write "é" }
      p File.binread(path)
      File.open(path, "w:EUC-JP:UTF-8") { |f| f.write "é" }
      p File.binread(path)
      File.open(path, "w:EUC-JP") { |f| f.write "é".encode("UTF-16LE") }
      p File.binread(path)
      File.open(path, "w") { |f| f.set_encoding("UTF-16BE"); f.printf("%s", "a"); f.putc "b" }
      p File.binread(path)
      File.open(path, "wb") { |f| f.write "é".encode("EUC-JP") }
      p File.binread(path)
      File.delete(path)

    RUBY

    _(result).must_answer <<~'OUT'
      "\xE9\x00"
      nil
      4
      "\xE9\x00a\x00b\x00c\x00"
      "\xC6\xFC\xCB\xDC\n"
      "\xC3\xA9"
      #<Encoding::UndefinedConversionError: "\xFF" from ASCII-8BIT to UTF-8>
      #<Encoding::InvalidByteSequenceError: "\xFF" on UTF-8>
      "a\x00"
      "\xE9\x00"
      "\x8F\xAB\xB1"
      "\x8F\xAB\xB1"
      "\x00a\x00b"
      "\x8F\xAB\xB1"
    OUT
  end
end
