# frozen_string_literal: true

require "spec_helper"

describe "FFI: arithmetic" do
  it "bare struct name in a signature is a reference" do
    result = ze0(<<~'RUBY')
      # A bare `FFI::Struct` subclass in an `attach_function` signature is
      # ruby-ffi's StructByReference -- the ABI type is a POINTER (`.by_value` is
      # the by-value spelling). An argument takes a struct instance and passes its
      # backing memory; a return comes back as a plain `FFI::Pointer` (the gem
      # does NOT auto-wrap it). gmtime/timegm round-trip both directions.
      require "ffi"

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        class Tm < FFI::Struct
          layout :tm_sec, :int,
                 :tm_min, :int,
                 :tm_hour, :int,
                 :tm_mday, :int,
                 :tm_mon, :int,
                 :tm_year, :int,
                 :tm_wday, :int,
                 :tm_yday, :int,
                 :tm_isdst, :int,
                 :tm_gmtoff, :long,
                 :tm_zone, :pointer
        end

        attach_function :gmtime, [:pointer], Tm
        attach_function :timegm, [Tm], :long
      end

      t = FFI::MemoryPointer.new(:long)
      t.write_long(86_400 * 365)
      ptr = LibC.gmtime(t)
      p ptr.class
      p ptr.null?
      tm = LibC::Tm.new(ptr)
      p tm[:tm_year] + 1900
      p tm[:tm_mon]
      p tm[:tm_mday]
      p tm[:tm_hour]
      p LibC.timegm(tm)
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      FFI::Pointer
      false
      1971
      0
      1
      0
      31536000
      still running
    OUT
  end

  it "attach_function emits an extern C wrapper, and the scalar marshaling matches CRuby with the gem" do
    result = ze0(<<~'RUBY')
      # The real `ffi` gem API, AOT-compiled: `require "ffi"` is a native
      # no-op, `extend FFI::Library` marks the module, and `attach_function` (plain
      # and the 4-arg rename form) emits a compile-time `extern "C"` + `#[link]` and
      # a wrapper module method. Scalar marshaling (`:int`/`:string`/`:ulong`/
      # `:double`) is byte-identical to CRuby+ffi -- the whole point of the
      # CRuby-faithful surface. libc/libm are always present, so this runs anywhere.

      require "ffi"
      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :abs, [:int], :int
        attach_function :my_strlen, :strlen, [:string], :ulong
      end
      module LibM
        extend FFI::Library
        ffi_lib "m"
        attach_function :pow, [:double, :double], :double
      end
      puts LibC.abs(-7)
      puts LibC.my_strlen("hello world")
      puts LibM.pow(2.0, 10.0)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      11
      1024.0
    OUT
  end

  it "an :int argument computed by repeated multiplication still marshals as a plain C int" do
    result = ze0(<<~'RUBY')
      # An FFI :int argument fed by an integer computed through repeated
      # multiplication (a value a widening analysis could have promoted) still
      # marshals as a plain C int. Ported from spinel's ffi_func to the real ffi
      # gem API.
      require "ffi"

      module M
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :abs, [:int], :int
      end
      class P
        def initialize
          @mult = 2
          @base = 5
        end
        def backoff_for(n)
          d = @base
          i = 0
          while i < n
            d = d * @mult
            i += 1
          end
          d
        end
      end
      p = P.new
      b = p.backoff_for(3)   # 5*2*2*2 = 40
      puts M.abs(b)
    RUBY

    _(result).must_answer "40\n"
  end

  it "a program that attaches libc functions runs the same under CRuby with the gem and under zeo" do
    result = ze0(<<~'RUBY')
      # Real `ffi` gem API, AOT-compiled (#204): `attach_function` emits a
      # compile-time `extern "C"` + `#[link]`; the program runs identically under
      # CRuby+ffi and zeo.
      require "ffi"

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :abs, [:int], :int
        attach_function :my_strlen, :strlen, [:string], :ulong
      end

      module LibM
        extend FFI::Library
        ffi_lib "m"
        attach_function :pow, [:double, :double], :double
      end

      puts LibC.abs(-7)
      puts LibC.my_strlen("hello world")
      puts LibM.pow(2.0, 10.0)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      11
      1024.0
    OUT
  end

  it "MemoryPointer reads, writes, pointer arithmetic, typed arrays, and an out-of-bounds IndexError" do
    result = ze0(<<~'RUBY')
      # FFI `FFI::MemoryPointer`: an owned heap buffer with typed
      # read/write accessors, pointer arithmetic, typed arrays, `from_string`, and
      # an out-of-bounds `IndexError` -- byte-identical to `ffi 1.17.4`.

      require "ffi"
      p = FFI::MemoryPointer.new(:int, 3)
      p.put_int(0, 10); p.put_int(4, 20); p.put_int(8, 30)
      puts p.get_int(0)
      puts p.get_int(4)
      puts (p + 8).read_int
      puts p.size
      p.write_array_of_int([7, 8, 9])
      puts p.read_array_of_int(3).inspect
      sp = FFI::MemoryPointer.from_string("hi there")
      puts sp.read_string
      puts sp.size
      d = FFI::MemoryPointer.new(:double, 1)
      d.write_double(3.5)
      puts d.read_double
      begin
        FFI::MemoryPointer.new(:int, 1).get_int(4)
        puts "no error"
      rescue IndexError
        puts "IndexError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      12
      [7, 8, 9]
      hi there
      9
      3.5
      IndexError
    OUT
  end

  it "a MemoryPointer passes to C as its raw address, and a char * return comes back as an FFI::Pointer" do
    result = ze0(<<~'RUBY')
      # FFI `:pointer` marshaling: a `MemoryPointer` passed to a C
      # function as its raw address, and a C `char *` return wrapped back as an
      # `FFI::Pointer`. `strcpy(buf, "hello")` fills the buffer and returns it;
      # `strlen(buf)` reads it back through the pointer. Matches CRuby+ffi.

      require "ffi"
      module C
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strcpy, [:pointer, :string], :pointer
        attach_function :strlen, [:pointer], :ulong
      end
      buf = FFI::MemoryPointer.new(:char, 32)
      ret = C.strcpy(buf, "hello")
      puts buf.read_string
      puts C.strlen(buf)
      puts ret.read_string
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      5
      hello
    OUT
  end

  it "an array literal of :pointer returns infers as pointers, not as an int array" do
    result = ze0(<<~'RUBY')
      # #492 (ported to the real ffi gem API). An array literal whose elements are
      # FFI :pointer returns (e.g. `[LibC.malloc(...)]`) must infer as an array of
      # pointers, not collapse to an int-array representation -- push sites and
      # element reads round-trip the pointer values intact.
      require "ffi"

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :malloc, [:size_t], :pointer
        attach_function :free,   [:pointer], :void
      end

      class Bag
        attr_accessor :slots
        def initialize
          @slots = [LibC.malloc(8)]
        end
      end

      b = Bag.new
      b.slots.push(LibC.malloc(8))
      puts b.slots.length
      b.slots.each { |p| LibC.free(p) }
    RUBY

    _(result).must_answer "2\n"
  end

  it "layout declares the C fields, [] and []= read and write them, and C fills the struct through its pointer" do
    result = ze0(<<~'RUBY')
      # FFI::Struct through the real ffi gem API (ported from spinel's ffi_struct
      # DSL): `layout` declares the C fields, `[]`/`[]=` read and write them, and a
      # C function can fill a struct through its pointer.
      require "ffi"

      class Point < FFI::Struct
        layout :x, :long, :y, :long
      end
      class Mix < FFI::Struct
        layout :a, :int, :d, :double
      end
      class Node < FFI::Struct
        layout :val, :int, :next, :pointer
      end
      class Timeval < FFI::Struct
        layout :tv_sec, :long, :tv_usec, :long
      end

      module M
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :gettimeofday, [:pointer, :pointer], :int
      end

      # scalar fields round-trip
      pt = Point.new
      pt[:x] = 3
      pt[:y] = 7
      puts pt[:x]
      puts pt[:y]
      puts(pt[:x] + pt[:y])

      # mixed int + double
      m = Mix.new
      m[:a] = 42
      m[:d] = 3.5
      puts m[:a]
      puts m[:d]

      # pointer fields chain, NULL reads back as nil-equal
      a = Node.new
      b = Node.new
      a[:val] = 11
      a[:next] = b.pointer
      puts a[:val]
      puts(a[:next] != nil)
      puts(b[:next] == nil)

      # interop: gettimeofday fills the struct through its pointer
      tv = Timeval.new
      M.gettimeofday(tv.pointer, nil)
      puts(tv[:tv_sec] > 0)

      # a pointer field can carry a C string; read it back through read_string
      label = FFI::MemoryPointer.from_string("hello")
      nm = Node.new
      nm[:next] = label
      nm[:val] = 5
      puts nm[:next].read_string
      puts nm[:val]
    RUBY

    _(result).must_answer <<~'OUT'
      3
      7
      10
      42
      3.5
      11
      true
      true
      true
      hello
      5
    OUT
  end
end
