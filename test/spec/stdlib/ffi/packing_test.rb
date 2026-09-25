# frozen_string_literal: true

require "spec_helper"

describe "FFI: packing and unpacking" do
  it "a binary payload's embedded NUL bytes survive the boundary through a byte-count read" do
    result = zr(<<~'RUBY')
      # Through the real ffi gem API, a binary payload's embedded NUL bytes survive the FFI
      # boundary. The motivating case is a WebSocket frame: an inbound
      # (client->server) frame is masked, and an ActionCable "subscribe" payload is
      # >125 bytes, so the WS extended 2-byte length field is used -- its high byte
      # is 0x00 (lengths 126..255) at frame index 2. A strlen-based read
      # (read_string with no length) truncates there; a byte-count read
      # (read_bytes) preserves every byte, so the payload unmasks exactly.
      require "ffi"

      # Expected unmasked payload (the ActionCable subscribe JSON), as bytes.
      PAYLOAD = [123, 34, 99, 111, 109, 109, 97, 110, 100, 34, 58, 34, 115, 117, 98, 115, 99, 114, 105, 98, 101, 34, 44, 34, 105, 100, 101, 110, 116, 105, 102, 105, 101, 114, 34, 58, 34, 123, 92, 34, 99, 104, 97, 110, 110, 101, 108, 92, 34, 58, 92, 34, 82, 111, 111, 109, 67, 104, 97, 110, 110, 101, 108, 92, 34, 44, 92, 34, 114, 111, 111, 109, 92, 34, 58, 92, 34, 103, 101, 110, 101, 114, 97, 108, 45, 100, 105, 115, 99, 117, 115, 115, 105, 111, 110, 45, 108, 111, 98, 98, 121, 92, 34, 44, 92, 34, 115, 105, 110, 99, 101, 92, 34, 58, 49, 55, 49, 56, 54, 48, 48, 48, 48, 48, 125, 34, 125].pack("C*")

      # The masked WebSocket frame for that payload (raw bytes, octal escapes).
      FRAME = "\201\376\000\177\067\372\041\235\114\330\102\362\132\227\100\363\123\330\033\277\104\217\103\356\124\210\110\377\122\330\015\277\136\236\104\363\103\223\107\364\122\210\003\247\025\201\175\277\124\222\100\363\131\237\115\301\025\300\175\277\145\225\116\360\164\222\100\363\131\237\115\301\025\326\175\277\105\225\116\360\153\330\033\301\025\235\104\363\122\210\100\361\032\236\110\356\124\217\122\356\136\225\117\260\133\225\103\377\116\246\003\261\153\330\122\364\131\231\104\301\025\300\020\252\006\302\027\255\007\312\021\255\112\330\134".b

      buf = FFI::MemoryPointer.new(FRAME.bytesize + 1)
      buf.put_bytes(0, FRAME)
      full  = buf.read_bytes(FRAME.bytesize)
      trunc = buf.read_string
      puts "frame bytes (binstr)  = #{full.bytesize}"
      puts "truncated (str)       = #{trunc.bytesize}"

      # Unmask the full frame: 2-byte extended length at [2..3], 4-byte key at [4..7],
      # masked payload from [8].
      plen = (full.getbyte(2) << 8) | full.getbyte(3)
      kk = [full.getbyte(4), full.getbyte(5), full.getbyte(6), full.getbyte(7)]
      out = []
      i = 0
      while i < plen
        out << (full.getbyte(8 + i) ^ kk[i & 3])
        i += 1
      end
      puts "unmasked length       = #{out.length}"
      puts "unmasked == subscribe = #{out.pack("C*") == PAYLOAD}"
    RUBY

    _(result).must_answer <<~'OUT'
      frame bytes (binstr)  = 135
      truncated (str)       = 2
      unmasked length       = 127
      unmasked == subscribe = true
    OUT
  end

  it "a MemoryPointer comes up zero-filled, and every reader kind lines up at every offset" do
    result = zr(<<~'RUBY')
      # Through the real ffi gem API, an FFI::MemoryPointer allocation is zero-filled,
      # so reading it back through
      # every reader kind at every offset proves the storage + read-pointer
      # arithmetic line up.
      require "ffi"

      buf = FFI::MemoryPointer.new(16)
      puts buf.get_uint32(0)
      puts buf.get_uint32(4)
      puts buf.get_uint32(8)
      puts buf.get_int32(0)

      # A second buffer is a distinct allocation; reading from one doesn't
      # accidentally see the other's bytes.
      other = FFI::MemoryPointer.new(16)
      puts other.get_uint32(0)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      0
      0
      0
    OUT
  end

  it "a layout list put through a splat or a hash lowers to the layout the program computes" do
    result = zr(<<~'RUBY')
      # Three spellings that put the same declaration list through an expression
      # before the directive sees it. All are compile-time values, so all lower to
      # the layout the program computes.
      #
      #   layout(*[ ... ])              the flat pair list, splatted (fzeet,
      #                                 windows_gui and ffi-wingui-core all spell
      #                                 NONCLIENTMETRICS this way)
      #   layout(*{ ... }.to_a.flatten) the documented hash form, flattened into
      #                                 pairs and splatted back apart (voicevox)
      #   [:pointer, name = :string]    an assignment mid-argument-list, whose VALUE
      #                                 is the type -- ffi-tk keeps the local for a
      #                                 later declaration
      require "ffi"

      class Metrics < FFI::Struct
        layout(*[
          :cbSize, :uint,
          :iBorderWidth, :int,
          :iScrollWidth, :int
        ])
      end

      class Options < FFI::Struct
        layout(*{
          mode: :int32,
          threads: :int16,
          load_all: :bool
        }.to_a.flatten)
      end

      module Libc
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :zr_memcpy, :memcpy, [:pointer, :pointer, size = :size_t], :pointer
      end

      p [Metrics.size, Metrics.members, Metrics.offset_of(:iScrollWidth)]
      p [Options.size, Options.members, Options.offset_of(:load_all)]

      m = Metrics.new
      m[:iBorderWidth] = 3
      p m[:iBorderWidth]

      o = Options.new
      o[:load_all] = true
      p [o[:load_all], o[:threads]]

      src = FFI::MemoryPointer.new(4)
      src.put_bytes(0, "abc\0")
      dst = FFI::MemoryPointer.new(4)
      Libc.zr_memcpy(dst, src, 4)
      p dst.read_string

      # The assignment's local belongs to the module body it was written in, so it
      # is not visible out here -- the same NameError ruby raises.
      begin
        p size
      rescue NameError => e
        puts "size: #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [12, [:cbSize, :iBorderWidth, :iScrollWidth], 8]
      [8, [:mode, :threads, :load_all], 6]
      3
      [true, 0]
      "abc"
      size: NameError
    OUT
  end

  it "a field may name its own byte offset, and the number given wins over the alignment" do
    result = zr(<<~'RUBY')
      # ruby-ffi's third element per field: an explicit byte OFFSET. Every Win32
      # header struct in winwindow is written that way, and readline-ffi, PAPI,
      # musicbeeipc, snarl and windows_gui all spell at least one. zr read the
      # argument list as `:name, :type` pairs only, so an odd count was an outright
      # rejection.
      #
      # The number the declaration gives wins, however it sits against the field's
      # own alignment. Size and alignment still come from the fields: this struct is
      # 8 bytes aligned to 4, not 8 aligned to 2 -- oracle-verified, along with
      # `alignment` itself, which the synthesized class did not answer at all.
      require "ffi"

      class Header < FFI::Struct
        layout :kind, :int16, 0,
               :size, :int32, 2,
               :tail, :int16, 6
      end

      p Header.size
      p Header.alignment
      p Header.offset_of(:size)
      p Header.members

      h = Header.new
      h[:kind] = 3
      h[:size] = 70_000
      h[:tail] = -1
      p [h[:kind], h[:size], h[:tail]]

      # A packed layout, with no pinned offsets, still lays out the way it always
      # did: each field rounded up to its own alignment.
      class Packed < FFI::Struct
        layout :a, :int8, :b, :int32, :c, :int8
      end

      p Packed.size
      p Packed.offset_of(:b)
      p Packed.offset_of(:c)

      # Unrelated to offsets, and in the same neighbourhood of "the declaration is
      # not all literal": `**opts` where the class body set `opts = { blocking: true }`
      # above. cztop, mosq, jansson and czmq-ffi-gen each hoist the one option they
      # share into a local and splat it into every declaration.
      module Libc
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        opts = { blocking: true }
        attach_function :labs, [:long], :long, **opts
        attach_function :abs, [:int], :int
      end

      p Libc.labs(-9)
      p Libc.abs(-3)

      # A third literal-strictness shape in the same family: an inline array's
      # element COUNT held in a constant the class body computed. librtmp writes
      # `RTMP_BUFFER_CACHE_SIZE = (16*1024)` four lines above the field it sizes, and
      # the count is what decides where every following field starts -- so it has to
      # fold at LOWERING time. A constant expression counts, not only a bare integer
      # literal.
      module Net
        BUF = (16 * 1024)
        TAG = (1 << 3)

        class SockBuf < FFI::Struct
          layout :sock, :int,
                 :buf, [:char, BUF],
                 :tag, [:uint8, TAG]
        end
      end

      p Net::SockBuf.size
      p Net::SockBuf.offset_of(:tag)

      # And the argument LIST itself, when the gem did not want to spell a prototype
      # twice: `[:pointer] * 13` (rbmetis' METIS bindings, csspool's croco
      # callbacks) and a body-local `%i[...]` (ires).
      module Repeated
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        params = %i[int]
        attach_function :abs, params, :int
        attach_function :labs, [:long] * 1, :long
        callback :pair, [:pointer] * 2, :void
      end

      p Repeated.abs(-4)
      p Repeated.labs(-5)
    RUBY

    _(result).must_answer <<~'OUT'
      8
      4
      2
      [:kind, :size, :tail]
      [3, 70000, -1]
      12
      4
      8
      9
      3
      16396
      16388
      4
      5
    OUT
  end

  it "the typed array accessors answer in all four spellings, at offset zero and beyond" do
    result = zr(<<~'RUBY')
      # `FFI::Pointer`'s typed ARRAY accessors, in all four spellings ruby-ffi has:
      # `read_`/`write_` start at offset 0, `get_`/`put_` take one. zr had six of
      # the ninety-odd, so a gem reading a C array back (`put_array_of_int32`,
      # `get_array_of_pointer`, ...) hit a NoMethodError at run time.
      #
      # Also here: `#clear`, `#type_size`, `#order`, `#read_string_length` and the
      # generic `read_array_of_type`/`write_array_of_type` pair.
      require "ffi"

      ptr = FFI::MemoryPointer.new(:int32, 4)
      ptr.write_array_of_int32([1, 2, 3, 4])
      p ptr.read_array_of_int32(4)
      p ptr.get_array_of_int32(4, 2)
      ptr.put_array_of_int32(8, [30, 40])
      p ptr.read_array_of_int(4)
      p ptr.type_size
      p ptr.size

      # Every width, signed and unsigned, through the offset spellings.
      buf = FFI::MemoryPointer.new(:uint8, 64)
      buf.put_array_of_int8(0, [-1, 2])
      p buf.get_array_of_int8(0, 2)
      p buf.get_array_of_uint8(0, 2)
      buf.put_array_of_int16(8, [-300, 300])
      p buf.get_array_of_int16(8, 2)
      p buf.get_array_of_uint16(8, 2)
      buf.put_array_of_int64(16, [-5, 5])
      p buf.get_array_of_int64(16, 2)
      buf.put_array_of_uint64(16, [7, 8])
      p buf.get_array_of_uint64(16, 2)
      buf.put_array_of_long(32, [11, 12])
      p buf.get_array_of_long(32, 2)
      buf.put_array_of_ushort(48, [65535])
      p buf.get_array_of_ushort(48, 1)

      # Floats, in both widths and both alias spellings.
      f = FFI::MemoryPointer.new(:double, 4)
      f.write_array_of_double([1.5, 2.5])
      p f.read_array_of_double(2)
      f.put_array_of_float64(16, [3.5])
      p f.get_array_of_double(16, 1)
      g = FFI::MemoryPointer.new(:float, 4)
      g.write_array_of_float([0.5, 1.25])
      p g.read_array_of_float(2)
      p g.get_array_of_float32(0, 2)

      # Pointers, by value and back.
      slots = FFI::MemoryPointer.new(:pointer, 2)
      a = FFI::MemoryPointer.new(:int32, 1)
      a.write_int32(42)
      slots.write_array_of_pointer([a, FFI::Pointer.new(0)])
      back = slots.read_array_of_pointer(2)
      p back.length
      p back[0].read_int32
      p back[1].null?
      p slots.get_array_of_pointer(0, 1).first.read_int32

      # The generic pair, over the same accessors. Not symmetric: ruby-ffi's writer
      # is sent `(offset, value)` while its reader walks a stepped pointer, so the
      # writer names a `put_` and the reader a `read_`.
      t = FFI::MemoryPointer.new(:int32, 3)
      t.write_array_of_type(:int32, :put_int32, [7, 8, 9])
      p t.read_array_of_type(:int32, :read_int32, 3)

      # `#clear` zeroes the whole extent.
      t.clear
      p t.read_array_of_int32(3)

      # `#read_string_length` takes the bytes verbatim, NULs and all.
      s = FFI::MemoryPointer.from_string("ab\0cd")
      p s.read_string_length(5)
      p s.read_string

      # Byte order on a little-endian target.
      p ptr.order
      p ptr.order(:little).equal?(ptr)

      # An array of C strings.
      argv = FFI::MemoryPointer.new(:pointer, 2)
      one = FFI::MemoryPointer.from_string("one")
      two = FFI::MemoryPointer.from_string("two")
      argv.write_array_of_pointer([one, two])
      p argv.read_array_of_string(2)
      p argv.get_array_of_string(0, 2)

      # Out of bounds stays the gem's IndexError.
      begin
        ptr.read_array_of_int32(1000)
      rescue IndexError => e
        puts "IndexError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [2, 3]
      [1, 2, 30, 40]
      4
      16
      [-1, 2]
      [255, 2]
      [-300, 300]
      [65236, 300]
      [-5, 5]
      [7, 8]
      [11, 12]
      [65535]
      [1.5, 2.5]
      [3.5]
      [0.5, 1.25]
      [0.5, 1.25]
      2
      42
      true
      42
      [7, 8, 9]
      [0, 0, 0]
      "ab\x00cd"
      "ab"
      :little
      true
      ["one", "two"]
      ["one", "two"]
      IndexError
    OUT
  end

  it "a live malloc result is not nil-equal, where a NULL pointer is" do
    result = zr(<<~'RUBY')
      # Pointer/nil equality through the real ffi gem API: a live malloc result is
      # not nil-equal, and a NULL pointer
      # (read out of a zero-filled MemoryPointer) is.
      require "ffi"

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :malloc, [:size_t], :pointer
        attach_function :free,   [:pointer], :void
      end

      p = LibC.malloc(64)
      if p == nil
        puts "got_nil"
      else
        puts "non_nil"
      end
      LibC.free(p)

      # A MemoryPointer is zero-filled, so reading 8 bytes at offset 0 as a pointer
      # gives a deterministic NULL -- handy for verifying that `ptr == nil`
      # actually compares to NULL.
      zero_ptr = FFI::MemoryPointer.new(16).read_pointer
      if zero_ptr == nil
        puts "zero_is_nil"
      else
        puts "zero_non_nil"
      end
    RUBY

    _(result).must_answer "non_nil\nzero_is_nil\n"
  end

  it "every typed accessor reads exactly its own width, never its neighbour's bytes" do
    result = zr(<<~'RUBY')
      # Every typed accessor names the WIDTH of its access. The bytes below are laid
      # out by a wider write and read back one width at a time, so a reader that
      # loaded the wrong width would fold in its neighbours. Little-endian target
      # (x86_64 / arm64), which is what the FFI layer assumes.
      #
      # The real ffi gem spells these accesses as FFI::MemoryPointer#put_*/#get_* at
      # an offset, which is what this checks.
      require "ffi"

      buf = FFI::MemoryPointer.new(:uint8, 32)

      buf.put_uint32(0, 0x04030201)
      puts buf.get_uint8(0)
      puts buf.get_uint8(1)
      puts buf.get_uint8(2)
      puts buf.get_uint8(3)
      puts buf.get_uint16(0)
      puts buf.get_uint16(2)
      puts buf.get_uint32(0)

      buf.put_int8(8, -5)
      puts buf.get_int8(8)
      puts buf.get_uint8(8)

      buf.put_int16(10, -300)
      puts buf.get_int16(10)
      puts buf.get_uint16(10)

      buf.put_int64(16, -1234567890123)
      puts buf.get_int64(16)

      # a 2-byte store leaves the two bytes above it alone
      buf.put_uint16(24, 0xBEEF)
      puts buf.get_uint32(24)

      # the last byte of the buffer: a wider load here would run off the end
      puts buf.get_uint8(31)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      4
      513
      1027
      67305985
      -5
      251
      -300
      65236
      -1234567890123
      48879
      0
    OUT
  end

  it "a subclass of a struct class is a struct class, but it inherits no layout" do
    result = zr(<<~'RUBY')
      # A gem that wraps `FFI::Struct` once and declares every real struct against
      # the wrapper. gssapi does exactly this -- `GssUMStruct < FFI::Struct` exists
      # only to hide `[]`/`[]=`, and nothing else in the gem names `FFI::Struct`
      # again -- so zr, which recognized only a DIRECT superclass, saw none of them
      # as structs at all and reported the grandchildren as undeclared FFI types.
      #
      # A subclass of a struct class is a struct class. `FFI::ManagedStruct` joins
      # the same set: its auto-release finalizer is a lifetime concern, not an ABI
      # one, so the layout reads identically.
      #
      # What is NOT inherited is the LAYOUT. `class B < A; end` leaves `B.size` at 0
      # in ruby-ffi and `B.new` raises "no Struct layout configured" -- a subclass
      # gets its parent's accessors and none of its fields.
      require "ffi"

      module Lib
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        class Wrapper < FFI::Struct
          def summary = "#{self.class.name} holds #{self.class.size} bytes"
        end

        class Timeval < Wrapper
          layout :tv_sec, :long, :tv_usec, :long
        end

        # Two steps down, with its own layout, and taken by REFERENCE in a
        # signature -- which is what a bare struct class means to ruby-ffi.
        class Stamp < Timeval
          layout :sec, :long, :usec, :long
        end

        attach_function :gettimeofday, [Stamp, :pointer], :int
      end

      s = Lib::Stamp.new
      p Lib.gettimeofday(s, nil)
      p s[:sec] > 0
      p Lib::Stamp.size
      p s.summary
    RUBY

    _(result).must_answer <<~'OUT'
      0
      true
      16
      "Lib::Stamp holds 16 bytes"
    OUT
  end

  it "layout takes one hash, a root-anchored superclass and a count computed from a type's size" do
    result = zr(<<~'RUBY')
      # `layout` written as one hash (the gem's documented alternative), a
      # root-anchored `::FFI::Struct` superclass, and an inline-array count
      # computed from `FFI::Type::X.size` -- three corpus spellings in one layout.
      #
      # 4 + 4 + 2 bytes, rounded up to the 4-byte alignment.

      require "ffi"
      class Pt < ::FFI::Struct
        layout x: :int32, y: :int32, pad: [:uint8, 16 / ::FFI::Type::LONG.size]
      end
      p = Pt.new
      p[:x] = 7
      p[:y] = 35
      puts p[:x] + p[:y]
      puts Pt.size
    RUBY

    _(result).must_answer "42\n12\n"
  end

  it "a nested struct field views the parent's bytes, and a callback field reads back as a Function" do
    result = zr(<<~'RUBY')
      # A layout field can be another struct BY VALUE, or a declared callback.
      # Reading a nested field yields the inner class VIEWING the same bytes (a
      # write through the view mutates the parent); assigning one copies bytes,
      # both oracle-verified against the gem. A callback field reads back as an
      # FFI::Function over the stored code pointer, and accepts a callable on
      # write -- the closure is kept alive by the struct.
      require "ffi"

      class Inner < FFI::Struct
        layout :a, :uint8, :b, :uint32
      end
      class Outer < FFI::Struct
        layout :x, :uint8, :inner, Inner, :y, :uint8
      end

      puts Outer.offset_of(:inner)
      puts Outer.offset_of(:y)
      puts Outer.size
      o = Outer.new
      o[:inner][:b] = 77
      puts o[:inner][:b]
      view = o[:inner]
      view[:a] = 5
      puts o[:inner][:a]
      puts o[:inner].class
      puts o[:inner].to_ptr.address - o.to_ptr.address

      i2 = Inner.new
      i2[:a] = 3
      i2[:b] = 9
      o[:inner] = i2
      puts o[:inner][:b]
      i2[:b] = 1
      puts o[:inner][:b]

      module M
        extend FFI::Library
        callback :adder_t, [:int, :int], :int
        class S < FFI::Struct
          layout :fn, :adder_t, :tail, :uint8
        end
      end

      s = M::S.new
      puts M::S.offset_of(:tail)
      s[:fn] = proc { |x, y| x + y }
      puts s[:fn].class
      puts s[:fn].call(20, 22)
    RUBY

    _(result).must_answer <<~'OUT'
      4
      12
      16
      77
      5
      Inner
      4
      9
      9
      8
      FFI::Function
      42
    OUT
  end

  it "a type position takes Struct.by_ref and an enum named by the constant it is assigned to" do
    result = zr(<<~'RUBY')
      # A type position in an FFI declaration takes more than a literal symbol.
      #
      #  - `Struct.by_ref` is a POINTER to the struct, which is what the C prototype
      #    receives; the layout never enters the call, so nothing about it is needed
      #    to make one. get_process_mem passes its `TaskInfo` that way.
      #  - an anonymous `Tag = enum(...)` is named by the constant it is assigned to,
      #    not by a `:tag` argument, and is then written as that constant wherever a
      #    type goes. sassc and google-protobuf declare every enum this way.
      require "ffi"

      module Libc
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        # Members auto-increment from 0, exactly as the `:tag` form's do.
        Whence = enum(:set, :cur, :end)

        # ... and an explicit value still restarts the run.
        Signal = enum(:hup, 1, :int, 2, :quit)

        typedef Whence, :whence_t

        attach_function :abs, [:int], :int
        # The same C `abs`, declared to take the enum. An enum IS an `int` at the
        # ABI -- that is the whole point of one: the names are ruby-side, the call
        # passes the number.
        attach_function :whence_abs, :abs, [:whence_t], :int
        attach_function :signal_abs, :abs, [Signal], :int
      end

      p Libc.abs(-7)
      p Libc.whence_abs(-3)
      p Libc.whence_abs(:end)
      p Libc.signal_abs(:quit)

      module Timing
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        class TimeVal < FFI::Struct
          layout :tv_sec, :int64,
                 :tv_usec, :int64
        end

        attach_function :gettimeofday, [TimeVal.by_ref, :pointer], :int
      end

      tv = Timing::TimeVal.new
      p Timing.gettimeofday(tv, nil)
      p tv[:tv_sec] > 1_700_000_000
      p Timing::TimeVal.members

      # A struct field may be an enum too. In memory it is an `int`; what comes back
      # out of it is the member's SYMBOL, and either spelling goes in.
      module Shapes
        extend FFI::Library

        Kind = enum(:round, :square, :odd)

        class Tagged < FFI::Struct
          layout :kind, Kind,
                 :n, :int32
        end

        # `FFI::Union` is the same declaration with every member at offset 0, and is
        # as wide as its widest member. A type declared in the library module reaches
        # the struct classes nested inside it.
        class Either < FFI::Union
          layout :as_int, :int32,
                 :as_double, :double
        end
      end

      t = Shapes::Tagged.new
      t[:kind] = 2
      p t[:kind]
      t[:kind] = :square
      p t[:kind]
      t[:n] = 9
      p t[:n]
      p Shapes::Tagged.size
      p Shapes::Tagged.offset_of(:n)

      e = Shapes::Either.new
      e[:as_double] = 1.5
      p e[:as_double]
      p Shapes::Either.size
      p Shapes::Either.offset_of(:as_double)

      # A `:bool` field is one byte and reads back as true/false; a `:string` field
      # is a `char *`, read through the pointer and NOT writable -- there would be
      # nowhere to keep the bytes alive, so ruby refuses.
      class Row < FFI::Struct
        layout :t, :int32,
               :flag, :bool,
               :name, :string,
               :n, :int32
      end

      p Row.size
      p [Row.offset_of(:flag), Row.offset_of(:name), Row.offset_of(:n)]

      r = Row.new
      p r[:flag]
      r[:flag] = true
      p r[:flag]
      r[:flag] = false
      p r[:flag]
      p r[:name]

      begin
        r[:name] = "hi"
      rescue ArgumentError => err
        p err.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      7
      3
      2
      3
      0
      true
      [:tv_sec, :tv_usec]
      :odd
      :square
      9
      8
      4
      1.5
      8
      0
      24
      [4, 8, 16]
      false
      true
      false
      nil
      "Cannot set :string fields"
    OUT
  end
end
