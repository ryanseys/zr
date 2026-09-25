# frozen_string_literal: true

require "spec_helper"

describe "FFI: inheritance and ancestors" do
  it "an integer argument given a String raises TypeError rather than coerce" do
    result = zr(<<~'RUBY')
      # An FFI integer argument given a non-Integer is a `TypeError`, exactly as the
      # gem raises -- the marshaling is faithful, not a silent coercion.

      require "ffi"
      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :abs, [:int], :int
      end
      begin
        L.abs("not an int")
        puts "no error"
      rescue TypeError
        puts "TypeError"
      end
    RUBY

    _(result).must_answer "TypeError\n"
  end

  it "an inline array field takes its count from an earlier struct's size or alignment" do
    result = zr(<<~'RUBY')
      # An inline array field whose element COUNT is `OtherStruct.size * N`.
      #
      # zr laid `OtherStruct` out itself, so its extent is as much a compile-time
      # constant as the literal the gem could have written -- j-law-ruby sizes every
      # one of its inline storage arrays this way, and zr refused the whole file
      # because the count "must be an integer literal".
      require "ffi"

      module Lib
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        MAX_TIERS = 3

        class Step < FFI::Struct
          layout :label, [:char, 8],
                 :amount, :uint64
        end

        class Fee < FFI::Struct
          layout :total, :uint64,
                 :storage, [:char, Step.size * MAX_TIERS],
                 :len, :int
        end

        # `.alignment` folds for the same reason.
        class Padded < FFI::Struct
          layout :head, :uint8,
                 :pad, [:char, Step.alignment],
                 :tail, :uint64
        end
      end

      p Lib::Step.size
      p Lib::Step.alignment
      p Lib::Fee.size
      p Lib::Fee.offset_of(:storage)
      p Lib::Fee.offset_of(:len)
      p Lib::Padded.offset_of(:tail)

      f = Lib::Fee.new
      f[:total] = 7
      f[:len] = 2
      p f[:total]
      p f[:len]
    RUBY

    _(result).must_answer <<~'OUT'
      16
      8
      64
      8
      56
      16
      7
      2
    OUT
  end

  it "two library modules each bind their own functions out of one shared library" do
    result = zr(<<~'RUBY')
      # Two library modules each bind their own functions out of libm.
      require "ffi"

      module MathA
        extend FFI::Library
        ffi_lib "m"
        attach_function :fabs, [:double], :double
      end

      module MathB
        extend FFI::Library
        ffi_lib "m"
        attach_function :cos, [:double], :double
      end

      puts MathA.fabs(-1.5)
      puts MathB.cos(0.0)
    RUBY

    _(result).must_answer "1.5\n1.0\n"
  end

  it "a C flag value is a plain Ruby constant on the library module, combinable with the bit ops" do
    result = zr(<<~'RUBY')
      # C-side flag values are plain Ruby constants on the library module,
      # combinable with the usual Integer bit ops.
      require "ffi"

      module Flags
        extend FFI::Library
        READ  = 1
        WRITE = 2
        EXEC  = 4
        MASK  = 0xff
      end

      puts Flags::READ
      puts Flags::WRITE
      puts Flags::EXEC
      puts Flags::MASK
      puts(Flags::READ | Flags::WRITE | Flags::EXEC)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      4
      255
      7
    OUT
  end

  it "a constant in a library module resolves parent-qualified, so a leaf name may collide" do
    result = zr(<<~'RUBY')
      # A constant in an FFI-library module whose leaf name collides with a plain
      # constant in another module must resolve parent-qualified (a leaf-keyed
      # constant table would silently rebind the reference and its type). The
      # constant is a plain Ruby constant on the FFI::Library module.
      require "ffi"

      module Verbs
        TEXT = "download-text"
      end

      module CMath
        extend FFI::Library
        ffi_lib "m"
        TEXT = 3
        attach_function :fabs, [:double], :double
      end

      t = 3
      puts(t == CMath::TEXT ? "int" : "collision")
      puts Verbs::TEXT
      puts CMath::TEXT + 1
      puts CMath.fabs(-2.5)
    RUBY

    _(result).must_answer <<~'OUT'
      int
      download-text
      4
      2.5
    OUT
  end

  it "the direct tier marshals every C scalar kind in and out" do
    result = zr(<<~'RUBY')
      # The direct tier: every C scalar kind in and out, through the emitted
      # `call_indirect` rather than the libffi engine. Widths and signedness
      # are what the test is about -- a `long` past 32 bits, an `unsigned long`
      # past `i64::MAX` (a Bignum), a `float` demoted and promoted, a `:bool`
      # read from an `int` result's low byte (`access` answers 0 or -1, so both
      # libcs agree; glibc's `isalpha` answers 1024, whose low byte is 0),
      # a NULL `:string` result (`nil`), a `:pointer` result read back.

      require "ffi"
      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :abs, [:int], :int
        attach_function :labs, [:long], :long
        attach_function :my_strlen, :strlen, [:string], :ulong
        attach_function :getenv, [:string], :string
        attach_function :strdup, [:string], :pointer
        attach_function :free, [:pointer], :void
        attach_function :strtoul, [:string, :pointer, :int], :ulong
        attach_function :access, [:string, :int], :bool
        attach_function :toupper, [:int], :int
      end
      module LibM
        extend FFI::Library
        ffi_lib "m"
        attach_function :fabs, [:double], :double
        attach_function :fabsf, [:float], :float
      end
      p LibC.abs(-7), LibC.labs(-(2**40)), LibC.my_strlen("hello")
      p LibC.getenv("ZR_TEST_NO_SUCH_VARIABLE")
      d = LibC.strdup("copied")
      p d.read_string
      p LibC.free(d)
      p LibC.strtoul("18446744073709551615", nil, 10)
      p LibC.access("/no/such/path", 0), LibC.access("/", 0), LibC.toupper("a".ord).chr
      p LibM.fabs(-2.5), LibM.fabsf(-1.5)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      1099511627776
      5
      nil
      "copied"
      nil
      18446744073709551615
      true
      false
      "A"
      2.5
      1.5
    OUT
  end

  it "a string argument's copy is released when a later argument's coercion raises" do
    result = zr(<<~'RUBY', env: {"ZR_TEST_RT_LEAKCHECK" => "1"})
      # A `:string` argument's NUL-terminated copy is owned by a pooled temp.
      # When a LATER argument's coercion raises, the copy is released on the
      # raise edge like any other temp -- the leak checker is what proves it,
      # and the gem's own error texts are what the rescue prints.


      require "ffi"
      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strtol, [:string, :pointer, :int], :long
        attach_function :my_strlen, :strlen, [:string], :ulong
      end
      3.times do
        begin
          LibC.strtol("42", nil, "ten")
        rescue TypeError => e
          puts e.message
        end
      end
      begin
        LibC.my_strlen("a\0b")
      rescue ArgumentError => e
        puts e.message
      end
      puts LibC.strtol("42", nil, 10)
    RUBY

    _(result).must_answer <<~'OUT'
      no implicit conversion of String into Integer
      no implicit conversion of String into Integer
      no implicit conversion of String into Integer
      string contains null byte
      42
    OUT
  end

  it "enum takes a member list the program builds, and the named form needs an Array" do
    result = zr(<<~'RUBY')
      # An `enum` whose MEMBER LIST is not a literal. ethon writes
      # `EasyCode = enum(:easy_code, easy_codes)`, where `easy_codes` is a method on
      # a module it `extend`ed and returns eighty-odd symbols; gir_ffi reads its flag
      # sets out of a shared library at load time. Both forms must work.
      #
      # The ABI never depended on the members: an enum is a C `int` either way, so
      # the extern signature is settled at compile time and only the symbol<->integer
      # marshaling has to wait. It waits in a slot -- the class body fills it when it
      # executes, exactly like a deferred `ffi_lib` -- and every signature lowered
      # under the declaration reads it back.
      #
      # The gem decides the named-vs-anonymous shape by RUNTIME CLASS: `Library#enum`
      # reads `:tag, [members]` when the second argument is an Array, and treats
      # every argument as a member otherwise. `enum(:status, status_codes)` is
      # therefore NAMED, while `enum(:level, *levels)` is not -- the splat puts
      # members, not an Array, in `args[1]`.
      require "ffi"

      module Codes
        # An explicit Integer sets that member's value AND the counter, so `:weird`
        # is 18. Same rule as the literal tier, applied to values only the running
        # program has.
        def status_codes = [:ok, :partial, :failed, 17, :weird]
      end

      module Lib
        extend FFI::Library
        extend Codes
        # A candidate list forces the dlopen tier too, so both marshaling paths --
        # the compile-time extern and the libffi one -- run against the same slot.
        ffi_lib ["/no/such/dir/libnothing.so", FFI::Library::LIBC]

        Status = enum(:status, status_codes)

        class Record < FFI::Struct
          layout :code, :status, :n, :int
        end

        attach_function :pick, :abs, [:status], :status
      end

      p Lib.pick(:failed)
      p Lib.pick(:weird)
      p Lib.pick(:ok)
      # An unnamed value passes through as an Integer, both ways.
      p Lib.pick(99)

      # A struct field of that enum reads and writes through the same slot.
      r = Lib::Record.new
      r[:code] = :failed
      p r[:code]
      r[:code] = :ok
      p r[:code]
      p Lib::Record.size
    RUBY

    _(result).must_answer <<~'OUT'
      :failed
      :weird
      :ok
      99
      :failed
      :ok
      8
    OUT
  end

  it "a self.extended hook can make every module that extends it an FFI library" do
    result = zr(<<~'RUBY')
      # A module whose `def self.extended(host)` hook runs `host.extend
      # FFI::Library` makes every module that extends IT an FFI library one step
      # removed -- chef's Win32 API modules share one FFI setup this way. The
      # hook's `host.typedef` stream replays into the host before its own
      # directives lower, and the `extend` itself still happens (the host keeps
      # the extender's ordinary methods).
      require "ffi"

      module Api
        def self.extended(host)
          host.extend FFI::Library
          host.typedef :uint32, :dword
          host.typedef :uint64, :qword
        end

        def helper_marker
          :helped
        end
      end

      module Win
        extend Api
        ffi_lib "m"
        enum :status, [:ok, 1, :bad]
        typedef :dword, :dword_alias
        attach_function :my_ceil, :ceil, [:double], :double

        class Box < FFI::Struct
          layout :d, :dword_alias, :q, :qword, :s, :status
        end
      end

      puts Win.my_ceil(1.25)
      puts Win::Box.offset_of(:q)
      puts Win::Box.size
      puts Win.respond_to?(:helper_marker)
      puts Win.helper_marker
    RUBY

    _(result).must_answer <<~'OUT'
      2.0
      8
      24
      true
      helped
    OUT
  end

  it "ffi_lib takes candidates only the running process can name, resolving at class-body time", only: "macos" do
    result = zr(<<~'RUBY')

      # An `ffi_lib` whose candidates zr cannot fold (an ENV read, a local, a
      # splat) is not a rejection: the expressions evaluate when the class body
      # executes, with the gem's exact shape -- every top-level argument is its
      # own required library, an Array argument lists alternatives for one, and a
      # library that can't open is CRuby's require-time LoadError at that very
      # statement. Every attach_function under it resolves through the handles.
      require "ffi"

      module RtMath
        extend FFI::Library
        lib = ENV["ZR_TEST_TEST_NO_SUCH_ENV"] || "m"
        ffi_lib lib
        attach_function :fabs, [:double], :double
      end
      puts RtMath.fabs(-3.5)

      module Alternatives
        extend FFI::Library
        candidates = ["zr-definitely-absent", "m"]
        ffi_lib candidates
        attach_function :my_floor, :floor, [:double], :double
      end
      puts Alternatives.my_floor(2.75)

      module Splatted
        extend FFI::Library
        libs = ["m", "c"]
        ffi_lib(*libs)
        attach_function :my_ceil, :ceil, [:double], :double
      end
      puts Splatted.my_ceil(2.25)

      begin
        module Nope
          extend FFI::Library
          ffi_lib "zr-definitely-absent-#{Process.pid}"
        end
      rescue LoadError => e
        puts "raised #{e.class} at ffi_lib"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3.5
      2.0
      3.0
      raised LoadError at ffi_lib
    OUT
  end

  it "a nameless enum registers no type name, and a DataConverter stands for its native type" do
    result = zr(<<~'RUBY')
      # A NAMELESS `enum [...]` registers no type name and is consumed; a class
      # that `extend FFI::DataConverter` with a `native_type` stands for that
      # native type in later declarations (google-protobuf's Internal::Arena).

      require "ffi"
      module Internal
        class Arena
          extend ::FFI::DataConverter
          native_type ::FFI::Type::POINTER
        end
      end
      module L
        extend FFI::Library
        ffi_lib FFI::CURRENT_PROCESS
        enum [:small, :medium, :large]
        attach_function :my_memchr, :memchr, [Internal::Arena, :int, :size_t], :pointer
      end
      puts "compiled"
    RUBY

    _(result).must_answer "compiled\n"
  end

  it "FFI::AutoPointer can be subclassed and inherits the whole pointer read and write surface" do
    result = zr(<<~'RUBY')
      # `class Handle < FFI::AutoPointer` with a `self.release` is the ffi gem's
      # own idiom for a C handle -- the single biggest subclassing ask in the
      # gem-probe ledger. Both pointer classes are payload roots now, so the
      # subclass is a `ValueSubclass` around a pointer payload and inherits the
      # whole `FFI::Pointer` read/write surface through the ancestry.
      #
      # What zr does NOT do is run `self.release`: there is no finalizer, so a
      # handle that closes an OS resource stays open until the process exits.
      # Nothing LEAKS that the runtime would not also free: an owned buffer is
      # reference counted.
      require "ffi"

      class Handle < FFI::AutoPointer
        def self.release(ptr)
          $released = ptr.address
        end

        def tag = :handle
      end

      h = Handle.new(FFI::Pointer.new(0x1234))
      p h.class
      p Handle.ancestors.take(4)
      p h.address
      p h.tag
      p h.is_a?(FFI::Pointer)
      p h.null?
      # `#autorelease?` is the gem's default for this class -- true here, and
      # false for a raw pointer, which owns nothing.
      p h.autorelease?
      h.autorelease = false
      p h.autorelease?
      p FFI::Pointer.new(4).autorelease?
      p FFI::MemoryPointer.new(:int, 2).autorelease?

      # A plain `FFI::Pointer` subclass, with ivars and an `initialize` that
      # seats the real payload through `super`.
      class Slot < FFI::Pointer
        def initialize(address, label)
          super(address)
          @label = label
        end

        attr_reader :label
      end

      s = Slot.new(0x40, "meta")
      p s.class
      p s.address
      p s.label
      p s.null?
      p Slot.new(0, "zero").null?

      # A `MemoryPointer` subclass allocates through ITS constructor, not the
      # plain pointer one -- `Buf.new(:int, 2)` is 8 owned bytes, not address 2.
      class Buf < FFI::MemoryPointer
        def label = :buf
      end

      b = Buf.new(:int, 2)
      p b.class
      p b.label
      p b.size
      p b.autorelease?

      # The inherited read/write surface works on the subclass instance.
      buf = FFI::MemoryPointer.new(:int, 1)
      buf.write_int(4242)
      view = Slot.new(buf.address, "view")
      p view.read_int
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      Handle
      [Handle, FFI::AutoPointer, FFI::Pointer, FFI::AbstractMemory]
      4660
      :handle
      true
      false
      true
      false
      false
      true
      Slot
      64
      "meta"
      false
      true
      Buf
      :buf
      8
      true
      4242
      still running
    OUT
  end

  it "FFI::Pointer.new(n) makes an integer-valued pointer a :pointer argument takes" do
    result = zr(<<~'RUBY')
      # Sentinel integer-valued pointers, ported to the real ffi gem API. The gem
      # spells an integer-valued pointer as FFI::Pointer.new(n) -- e.g. -1 for
      # sqlite3_bind_text's SQLITE_TRANSIENT destructor sentinel. free(NULL) is a
      # well-defined POSIX no-op, so a NULL-valued sentinel (and nil, the gem's
      # other NULL spelling) is the safe observation point.
      require "ffi"

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :free, [:pointer], :void
      end

      # Integer-valued NULL pointer as a :pointer arg.
      LibC.free(FFI::Pointer.new(0))

      # nil is the gem's NULL for a :pointer arg.
      LibC.free(nil)

      # A non-NULL sentinel constructs (not passed to free -- it isn't a real
      # allocation); its bit pattern is preserved.
      sentinel = FFI::Pointer.new(-1)
      puts(sentinel.null? ? "sentinel_null" : "sentinel_non_null")

      puts "ok"
    RUBY

    _(result).must_answer "sentinel_non_null\nok\n"
  end

  it "the runtime library tier passes a struct by value with the declaration's real field types" do
    result = zr(<<~'RUBY')
      # A struct passed BY VALUE through the RUNTIME library tier (an ffi_lib only
      # the running process can name): libffi builds the aggregate descriptor from
      # the declaration's real field types, so the classification matches the
      # extern tier's repr(C) mirror. libc's inet_ntoa takes struct in_addr by
      # value; 0x0100007F little-endian is network-order 127.0.0.1.
      require "ffi"

      module Net
        extend FFI::Library
        lib = ENV["ZR_TEST_TEST_NO_SUCH_ENV"] || "c"
        ffi_lib lib

        class InAddr < FFI::Struct
          layout :s_addr, :uint32
        end

        attach_function :inet_ntoa, [InAddr.by_value], :string
      end

      a = Net::InAddr.new
      a[:s_addr] = 0x0100007F
      puts Net.inet_ntoa(a)
      a[:s_addr] = 0xFFFFFFFF
      puts Net.inet_ntoa(a)
    RUBY

    _(result).must_answer "127.0.0.1\n255.255.255.255\n"
  end

  it "a :strptr return answers the decoded String and the raw Pointer together" do
    result = zr(<<~'RUBY')
      # `:strptr` is the gem's two-for-one return: the char* decoded as a String
      # AND the raw Pointer beside it, so the caller can still free the buffer.
      # strerror's ENOENT message spells the same on macOS and glibc.
      require "ffi"

      module C
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strerror, [:int], :strptr
      end

      s, p = C.strerror(2)
      puts s
      puts s.class
      puts p.class
      puts p.null?
    RUBY

    _(result).must_answer <<~'OUT'
      No such file or directory
      String
      FFI::Pointer
      false
    OUT
  end

  it "by_value passes the struct itself, where a bare Struct subclass passes its address" do
    result = zr(<<~'RUBY')
      # `.by_value` is the gem's BY-VALUE spelling: `inet_ntoa` takes `struct
      # in_addr` by value on every libc, and the mirror declaration carries the
      # real field types so the C ABI owns the layout.
      #
      # A BARE `FFI::Struct` subclass in the same position is the gem's
      # `StructByReference` -- it passes a POINTER (oracle-checked: ruby-ffi hands
      # `inet_ntoa` the struct's address and gets an address-shaped dotted quad
      # back). `gettimeofday` is the honest way to show it, since a C function that
      # really wants the pointer then works.

      require "ffi"
      class InAddr < FFI::Struct
        layout s_addr: :uint32
      end
      class Timeval < FFI::Struct
        layout :tv_sec, :long, :tv_usec, :long
      end
      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :inet_ntoa, [InAddr.by_value], :string
        attach_function :gettimeofday, [Timeval, :pointer], :int
      end
      a = InAddr.new
      a[:s_addr] = 16777343
      puts L.inet_ntoa(a)
      tv = Timeval.new
      puts L.gettimeofday(tv, nil)
      puts tv[:tv_sec] > 1_600_000_000
    RUBY

    _(result).must_answer <<~'OUT'
      127.0.0.1
      0
      true
    OUT
  end

  it "an attach_function returning Struct.by_value copies the result into a fresh struct" do
    result = zr(<<~'RUBY')
      # An attach_function whose return type is `Struct.by_value`: the C function
      # hands the struct back in registers/stack per the ABI, and the wrapper
      # copies it into a fresh ruby-owned MemoryPointer viewed through the struct's
      # own class. libc's div() is the canonical case, oracle-verified.
      require "ffi"

      module M
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        class DivT < FFI::Struct
          layout :quot, :int, :rem, :int
        end

        attach_function :div, [:int, :int], DivT.by_value
      end

      r = M.div(7, 3)
      puts r.class
      puts r[:quot]
      puts r[:rem]
      r2 = M.div(-9, 4)
      puts r2[:quot]
      puts r2[:rem]
      puts r.is_a?(FFI::Struct)
    RUBY

    _(result).must_answer <<~'OUT'
      M::DivT
      2
      1
      -2
      -1
      true
    OUT
  end

  it "an attached strlen answers the length of the string it is handed" do
    result = zr(<<~'RUBY')
      # An attached strlen binding returns the length of its argument.
      require "ffi"

      module Pathy
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strlen, [:string], :size_t
      end

      puts Pathy.strlen("hello")
      puts Pathy.strlen("")
    RUBY

    _(result).must_answer "5\n0\n"
  end

  it "layoutless struct name still types a signature" do
    result = zr(<<~'RUBY')
      # A `class X < FFI::Struct` whose layout the compiler never saw (ffi_dry's
      # `dsl_layout` builds one at runtime) still NAMES a struct: a signature
      # position only needs the by-reference fact, so `attach_function` typing
      # works -- the return is the plain `FFI::Pointer` StructByReference always
      # produces, and a layout-carrying class can view it.
      require "ffi"

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        class OpaqueTm < FFI::Struct
        end

        class Tm < FFI::Struct
          layout :tm_sec, :int,
                 :tm_min, :int,
                 :tm_hour, :int,
                 :tm_mday, :int,
                 :tm_mon, :int,
                 :tm_year, :int
        end

        attach_function :gmtime, [:pointer], OpaqueTm
      end

      t = FFI::MemoryPointer.new(:long)
      t.write_long(86_400 * 365)
      ptr = LibC.gmtime(t)
      p ptr.class
      p ptr.null?
      tm = LibC::Tm.new(ptr)
      p tm[:tm_year] + 1900
      p tm[:tm_mday]
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      FFI::Pointer
      false
      1971
      1
      still running
    OUT
  end

  it "reopened ffi module declares global typedefs" do
    result = zr(<<~'RUBY')
      # `module ::FFI; typedef :ulong, :XID; end` -- self IS the FFI module inside
      # that body, so a bare `typedef` there is the same GLOBAL declaration
      # `FFI.typedef` makes, visible to every library and struct that lowers after
      # it. The x11 family fills the whole X vocabulary this way in one file and
      # spends it across every other one.
      require "ffi"

      module ::FFI
        typedef :ulong, :XID
        # A typedef whose SOURCE is another global typedef resolves through it.
        typedef :XID, :Font
        typedef :int, :Bool
      end

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strlen, [:string], :XID
        attach_function :abs, [:Bool], :Bool
      end

      p L.strlen("hello")
      p L.abs(-7)

      class Glyph < FFI::Struct
        layout :id, :Font, :ok, :Bool
      end

      g = Glyph.new
      g[:id] = 4_294_967_296
      g[:ok] = 1
      p Glyph.size
      p g[:id]
      p g[:ok]
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      5
      7
      16
      4294967296
      1
      still running
    OUT
  end

  it "variadic attach function matches the oracle" do
    result = zr(<<~'RUBY')
      require "ffi"
      module C
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
      end
      buf = FFI::MemoryPointer.new(:char, 64)
      n = C.snprintf(buf, 64, "%d/%s/%.1f", :int, 42, :string, "hi", :double, 2.5)
      puts n
      puts buf.read_string
      buf2 = FFI::MemoryPointer.new(:char, 16)
      C.snprintf(buf2, 16, "plain")
      puts buf2.read_string
    RUBY

    _(result).must_answer <<~'OUT'
      9
      42/hi/2.5
      plain
    OUT
  end
end
