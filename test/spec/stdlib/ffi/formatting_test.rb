# frozen_string_literal: true

require "spec_helper"

describe "FFI: formatting and inspection" do
  it "c half converts and refuses as ruby does" do
    result = ze0(<<~'RUBY')
      # The C half of the ffi gem, written in ruby: each number kind a memory
      # op converts takes and refuses what ruby's C conversions take and
      # refuse, in their words, and the classes refuse what ffi_c refuses.
      require "ffi"
      m = FFI::MemoryPointer.new(:int64, 2)
      vals = [nil, "3", :a, true, 3.7, -1, 2**31, -2**31-1, 2**32, 2**63, 2**64, -2**63-1, 1r/2, Object.new, 1e30, Float::NAN]
      def t; yield; rescue Exception => e; puts "#{e.class}: #{e.message.gsub(/0x\h{16}/, "ADDR")}"; else puts "ok"; end
      %w[int8 uint8 int16 uint16 int32 uint32 int64 uint64 long ulong float32 float64 pointer bool].each do |t|
        row = vals.map do |v|
          m.send("put_#{t}", 0, v)
          m.send("get_#{t}", 0).inspect
        rescue => e
          "#{e.class}: #{e.message.sub(/#<Object:0x\h+>/, 'OBJ')}"
        end
        puts "#{t}: #{row.join(' | ')}"
      end
      def show(x) = puts(x.to_s.gsub(/0x\h{16}/, "ADDR"))
      t { FFI::DynamicLibrary.open(nil, nil) }
      t { FFI::StructLayout::Field.new(:a, "1", FFI::Type::INT) }
      t { FFI::StructLayout::Field.new(:a, 2**70, FFI::Type::INT) }
      t { FFI::MemoryPointer.new(:int).put_string(0, 1) }
      t { FFI::MemoryPointer.new(:int).put_array_of_int(0, 1) }
      t { FFI::ArrayType.new(:int, 3) }
      t { FFI::ArrayType.new(nil, 3) }
      t { FFI::Pointer.new(1).dup }
      t { show [FFI::DynamicLibrary.last_error].inspect }
      t { FFI::MemoryPointer.new(:int, -1) }
      t { FFI::Buffer.new(:int, -1) }
      t { show [FFI::Type.new(3).size, FFI::Type.new(FFI::Type::INT).inspect].inspect }
      t { FFI::Type.new("x") }
      t { x = FFI::Pointer.new(0); p x.read_int }
      t { x = FFI::MemoryPointer.new(4); x.freeze; x.put_int(0, 1) }
      t { x = FFI::MemoryPointer.new(4); x.freeze; show x.dup.inspect }
      t { show [FFI::Buffer.new(4).inspect, FFI::Buffer.new(4).total].inspect }
      t { FFI::MemoryPointer.new(4).free; FFI::Pointer.new(8).free }
      t { show [FFI::Function.new(:int, []) { }.inspect].inspect }
      t { show [FFI::Pointer.new(0).order, FFI::Pointer.new(1).order(:big).order].inspect }
      t { show [FFI::MemoryPointer.new(:int, 2)[1]].inspect }
      t { show [FFI::MemoryPointer.from_string("abc").size].inspect }
      t { show [FFI::StructLayout.new([], 0, 1)].inspect }

    RUBY

    _(result).must_answer <<~'OUT', stderr: "stdlib/ffi/formatting_test.rb:35: warning: calling free on non allocated pointer #<FFI::Pointer address=0xADDR> from stdlib/ffi/formatting_test.rb:35:in 'block in <main>'\n"
      int8: TypeError: no implicit conversion from nil to integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | -1 | RangeError: integer 2147483648 too big to convert to 'int' | RangeError: integer -2147483649 too small to convert to 'int' | RangeError: integer 4294967296 too big to convert to 'int' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
      uint8: TypeError: no implicit conversion of nil into Integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | 255 | 0 | RangeError: integer -2147483649 too small to convert to 'unsigned int' | RangeError: integer 4294967296 too big to convert to 'unsigned int' | RangeError: integer 9223372036854775808 too big to convert to 'unsigned int' | RangeError: bignum too big to convert into 'unsigned long' | RangeError: bignum out of range of unsigned long | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
      int16: TypeError: no implicit conversion from nil to integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | -1 | RangeError: integer 2147483648 too big to convert to 'int' | RangeError: integer -2147483649 too small to convert to 'int' | RangeError: integer 4294967296 too big to convert to 'int' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
      uint16: TypeError: no implicit conversion of nil into Integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | 65535 | 0 | RangeError: integer -2147483649 too small to convert to 'unsigned int' | RangeError: integer 4294967296 too big to convert to 'unsigned int' | RangeError: integer 9223372036854775808 too big to convert to 'unsigned int' | RangeError: bignum too big to convert into 'unsigned long' | RangeError: bignum out of range of unsigned long | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
      int32: TypeError: no implicit conversion from nil to integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | -1 | RangeError: integer 2147483648 too big to convert to 'int' | RangeError: integer -2147483649 too small to convert to 'int' | RangeError: integer 4294967296 too big to convert to 'int' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
      uint32: TypeError: no implicit conversion of nil into Integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | 4294967295 | 2147483648 | RangeError: integer -2147483649 too small to convert to 'unsigned int' | RangeError: integer 4294967296 too big to convert to 'unsigned int' | RangeError: integer 9223372036854775808 too big to convert to 'unsigned int' | RangeError: bignum too big to convert into 'unsigned long' | RangeError: bignum out of range of unsigned long | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
      int64: TypeError: no implicit conversion from nil | TypeError: no implicit conversion from string | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion from boolean | 3 | -1 | 2147483648 | -2147483649 | 4294967296 | RangeError: bignum too big to convert into 'long long' | RangeError: bignum too big to convert into 'long long' | RangeError: bignum too big to convert into 'long long' | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of long long | RangeError: float NaN out of range of long long
      uint64: TypeError: no implicit conversion of nil into Integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | 18446744073709551615 | 2147483648 | 18446744071562067967 | 4294967296 | 9223372036854775808 | RangeError: bignum too big to convert into 'unsigned long long' | RangeError: bignum out of range of unsigned long long | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of unsigned long long | RangeError: float NaN out of range of unsigned long long
      long: TypeError: no implicit conversion from nil to integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | -1 | 2147483648 | -2147483649 | 4294967296 | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
      ulong: TypeError: no implicit conversion of nil into Integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | 18446744073709551615 | 2147483648 | 18446744071562067967 | 4294967296 | 9223372036854775808 | RangeError: bignum too big to convert into 'unsigned long' | RangeError: bignum out of range of unsigned long | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
      float32: TypeError: no implicit conversion to float from nil | TypeError: no implicit conversion to float from string | TypeError: can't convert Symbol into Float | TypeError: no implicit conversion to float from true | 3.700000047683716 | -1.0 | 2147483648.0 | -2147483648.0 | 4294967296.0 | 9.223372036854776e+18 | 1.8446744073709552e+19 | -9.223372036854776e+18 | 0.5 | TypeError: can't convert Object into Float | 1.0000000150474662e+30 | NaN
      float64: TypeError: no implicit conversion to float from nil | TypeError: no implicit conversion to float from string | TypeError: can't convert Symbol into Float | TypeError: no implicit conversion to float from true | 3.7 | -1.0 | 2147483648.0 | -2147483649.0 | 4294967296.0 | 9.223372036854776e+18 | 1.8446744073709552e+19 | -9.223372036854776e+18 | 0.5 | TypeError: can't convert Object into Float | 1.0e+30 | NaN
      pointer: #<FFI::Pointer address=0xADDR> | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer | #<FFI::Pointer address=0xADDR> | #<FFI::Pointer address=0xADDR> | #<FFI::Pointer address=0xADDR> | #<FFI::Pointer address=0xADDR> | #<FFI::Pointer address=0xADDR> | RangeError: bignum too big to convert into 'unsigned long long' | RangeError: bignum out of range of unsigned long long | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer
      bool: NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer
      TypeError: wrong argument type nil (expected Integer)
      TypeError: wrong argument type String (expected Integer)
      TypeError: wrong argument type Integer (expected Integer)
      TypeError: wrong argument type Integer (expected String)
      TypeError: wrong argument type Integer (expected Array)
      TypeError: wrong argument type Symbol (expected FFI::Type)
      TypeError: wrong argument type nil (expected FFI::Type)
      RuntimeError: cannot duplicate unbounded memory area
      ["(null)"]
      ok
      ok
      ok
      [1, "#<FFI::Type::ADDR size=4 alignment=4>"]
      ok
      ArgumentError: wrong type
      FFI::NullPointerError: invalid memory read at address=ADDR
      RuntimeError: invalid memory write at address=ADDR
      #<FFI::MemoryPointer address=ADDR size=4>
      ok
      ["#<FFI:Buffer:ADDR address=ADDR size=4>", 4]
      ok
      ok
      ["#<FFI::Function address=ADDR size=48>"]
      ok
      [:little, :big]
      ok
      [#<FFI::Pointer address=ADDR size=4>]
      ok
      [4]
      ok
      RuntimeError: Struct size is zero
    OUT
  end

  it "a ruby array's numeric contents cross the boundary as a contiguous C buffer" do
    result = ze0(<<~'RUBY')
      # Ported from spinel's :float_array/:int_array bulk-transfer specs (#474) to
      # the real ffi gem API: a Ruby array's numeric contents cross the FFI boundary
      # as a contiguous C buffer. write_array_of_* fills an FFI::MemoryPointer,
      # memcpy moves the raw bytes C-side, and read_array_of_* recovers the
      # elements -- the same bulk-transfer contract the original declared.
      require "ffi"

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :memcpy, [:pointer, :pointer, :size_t], :pointer
      end

      src = FFI::MemoryPointer.new(:double, 3)
      src.write_array_of_double([1.5, 2.5, 3.5])
      dst = FFI::MemoryPointer.new(:double, 3)
      LibC.memcpy(dst, src, 24)
      puts dst.read_array_of_double(3).inspect

      isrc = FFI::MemoryPointer.new(:int64, 2)
      isrc.write_array_of_int64([65, 66])
      idst = FFI::MemoryPointer.new(:int64, 2)
      LibC.memcpy(idst, isrc, 16)
      puts idst.read_array_of_int64(2).inspect

      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      [1.5, 2.5, 3.5]
      [65, 66]
      ok
    OUT
  end

  it "read_string(len) keeps the embedded NULs where the strlen form truncates at the first" do
    result = ze0(<<~'RUBY')
      # Ported from spinel's :binstr FFI return mode to the real ffi gem API: a
      # binary payload with embedded NULs survives a byte-count read
      # (read_string(len)), where the C-string read (read_string with no length,
      # strlen-based) truncates at the first NUL -- fatal for binary protocols
      # (WebSocket frames carry 0x00). A plain strlen view reports length 1.
      require "ffi"

      buf = FFI::MemoryPointer.new(16)
      buf.put_bytes(0, "a\0b\0c")
      s = buf.read_string(5)
      puts s.length
      puts s.bytesize
      puts s.bytes.inspect
      # The strlen-truncated view stops at the first embedded NUL.
      puts buf.read_string.length
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      [97, 0, 98, 0, 99]
      1
    OUT
  end

  it "a declaration the compiler could not see attaches over the gem's runtime objects" do
    result = ze0(<<~'RUBY')
      # zeo has two tiers for an `FFI::Library` declaration, and which one runs is
      # decided by whether the COMPILER could see it.
      #
      # A declaration in a file the compiler lowered is consumed there: the whole
      # C signature rides in `.rodata` and the module's `ffi_lib`/`attach_function`
      # rows never run. A declaration the compiler could not see -- one a run-time
      # `eval` compiled -- runs those rows, which attach for real over the gem's
      # own runtime objects (`DynamicLibrary`, `Function`, `VariadicInvoker`).
      #
      # The first section pins the part BOTH tiers share: `extend FFI::Library` is
      # a real `extend`, so the module is one.
      require "ffi"

      module Compiled
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :abs, [:int], :int
      end
      p Compiled.abs(-7)
      p Compiled.is_a?(FFI::Library)
      p Compiled.singleton_class.ancestors.map(&:to_s).include?("FFI::Library")

      def show
        yield
      rescue Exception => e
        puts "#{e.class}: #{e.message.lines.first.to_s.strip[0, 40]}"
      end

      # A whole declaration the compiler never saw, in every argument shape: the
      # 3-argument form, the 4-argument form that renames the C symbol, and a
      # `typedef` the same body declared.
      eval <<~SRC
        module Attached
          extend FFI::Library
          ffi_lib FFI::Library::LIBC
          typedef :int, :my_int
          attach_function :abs, [:my_int], :my_int
          attach_function :my_labs, :labs, [:long], :long
          attach_function :strlen, [:string], :ulong
        end
      SRC
      show { p Attached.abs(-7) }
      show { p Attached.my_labs(-9) }
      show { p Attached.strlen("hello") }
      show { p (Attached.singleton_methods & %i[abs my_labs strlen]).sort }
      show { p Attached.instance_methods(false).sort }

      # A bare library name goes through the gem's own `LibraryPath` mangling.
      show do
        eval <<~SRC
          module Mathy
            extend FFI::Library
            ffi_lib "m"
            attach_function :zeo_cos, :cos, [:double], :double
          end
        SRC
        p Mathy.zeo_cos(0.0)
      end

      # A variadic signature attaches as the gem's `VariadicInvoker`, so the
      # trailing arguments arrive as (type, value) pairs.
      show do
        eval <<~SRC
          module Va
            extend FFI::Library
            ffi_lib FFI::Library::LIBC
            attach_function :snprintf, [:pointer, :ulong, :string, :varargs], :int
          end
        SRC
        buf = FFI::MemoryPointer.new(:char, 32)
        p Va.snprintf(buf, 32, "%d-%s", :int, 42, :string, "hi")
        p buf.read_string
      end

      # `attach_function` answers the callable it installed.
      show do
        m = Module.new
        m.extend FFI::Library
        m.ffi_lib FFI::Library::LIBC
        p m.attach_function(:abs, [:int], :int).class.to_s
      end

      # The three ways a declaration fails, each with the gem's own class.
      show do
        eval <<~SRC
          module Missing
            extend FFI::Library
            ffi_lib FFI::Library::LIBC
            attach_function :zzz_not_a_symbol, [:int], :int
          end
        SRC
      end
      show do
        eval <<~SRC
          module NoSuch
            extend FFI::Library
            ffi_lib "definitely_not_a_library_zzz"
          end
        SRC
      end
      show do
        eval <<~SRC
          module NoLib
            extend FFI::Library
            attach_function :abs, [:int], :int
          end
        SRC
      end
    RUBY

    _(result).must_answer <<~'OUT'
      7
      true
      true
      7
      9
      5
      [:abs, :my_labs, :strlen]
      [:abs, :my_labs, :strlen]
      1.0
      5
      "42-hi"
      "FFI::Function"
      FFI::NotFoundError: Function 'zzz_not_a_symbol' not found in
      LoadError: Could not open library 'definitely_not_a
      LoadError: no library specified
    OUT
  end

  it "an enum marshals a Symbol argument to its int and an int return back to its Symbol" do
    result = ze0(<<~'RUBY')
      # FFI `enum`: a named `enum :tag, [...]` used as an
      # `attach_function` type. A Symbol argument marshals to its int; an int return
      # maps back to its Symbol (an unmapped int stays an Integer). Auto-increment
      # after an explicit value (`:next` = 101). Verified against `ffi 1.17.4` using
      # `labs` as a pass-through: `labs(:hundred)` sends 100, `labs(-100)` returns
      # 100 -> `:hundred`.

      require "ffi"
      module C
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        enum :nums, [:zero, 0, :hundred, 100, :next]
        attach_function :to_num, :labs, [:nums], :long
        attach_function :from_num, :labs, [:long], :nums
      end
      puts C.to_num(:hundred)
      puts C.from_num(-100).inspect
      puts C.from_num(-101).inspect
      puts C.from_num(-5).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      100
      :hundred
      :next
      5
    OUT
  end

  it "an inline array of inline arrays lays out as rows of rows, and the proxy refuses an index" do
    result = ze0(<<~'RUBY')
      # `layout :matrix, [[:XFixed, 3], 3]` -- X11's XTransform, a 3x3 matrix. C
      # lays a 2-D array out as rows of rows, so the field is 9 elements wide and
      # the next field starts after all of it.
      #
      # The gem computes that layout and then REFUSES to read one back: indexing the
      # proxy raises `ArgumentError: get not supported for FFI::ArrayType`, because
      # an array has no scalar accessor to index with. `size` and `to_ptr` still
      # answer, and a whole-field write is the same NotImplementedError any inline
      # array gives.
      require "ffi"

      class Matrix3 < FFI::Struct
        layout :matrix, [[:int32, 3], 3],
               :tail, :int32
      end

      class Deep < FFI::Struct
        layout :cube, [[[:int8, 2], 3], 4],
               :tail, :int32
      end

      def probe(label)
        puts "#{label}: #{yield.inspect}"
      rescue StandardError => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      p [Matrix3.size, Matrix3.alignment, Matrix3.members, Matrix3.offset_of(:tail)]
      p [Deep.size, Deep.alignment, Deep.offset_of(:tail)]

      m = Matrix3.new
      row = m[:matrix]
      p row.class
      probe("size") { row.size }
      probe("get") { row[0] }
      probe("set") { row[0] = 1 }
      probe("to_a") { row.to_a }
      probe("each") { row.each { |x| x } }
      probe("to_ptr offset") { row.to_ptr.address - m.to_ptr.address }

      begin
        m[:matrix] = [1, 2]
      rescue NotImplementedError => e
        puts "whole write: #{e.class}: #{e.message}"
      end

      # A field AFTER the matrix still reads and writes normally -- the point of
      # getting the width right.
      m[:tail] = 42
      p m[:tail]
    RUBY

    _(result).must_answer <<~'OUT'
      [40, 4, [:matrix, :tail], 36]
      [28, 4, 24]
      FFI::Struct::InlineArray
      size: 3
      get: ArgumentError: get not supported for FFI::ArrayType
      set: ArgumentError: set not supported for FFI::ArrayType
      to_a: ArgumentError: get not supported for FFI::ArrayType
      each: ArgumentError: get not supported for FFI::ArrayType
      to_ptr offset: 0
      whole write: NotImplementedError: cannot set array field
      42
    OUT
  end

  it "MemoryPointer owns a heap buffer with typed accessors that C reads and writes" do
    result = ze0(<<~'RUBY')
      # FFI::MemoryPointer / FFI::Pointer and :pointer marshaling (#204 follow-on):
      # an owned heap buffer with typed accessors, passed to and returned from C.
      require "ffi"

      module C
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strcpy, [:pointer, :string], :pointer
        attach_function :strlen, [:pointer], :ulong
      end

      buf = FFI::MemoryPointer.new(:char, 32)
      ret = C.strcpy(buf, "hello, ffi")
      puts buf.read_string
      puts C.strlen(buf)
      puts ret.read_string

      nums = FFI::MemoryPointer.new(:int, 3)
      nums.write_array_of_int([10, 20, 30])
      puts nums.read_array_of_int(3).inspect
      puts (nums + 4).read_int
      puts nums.size
    RUBY

    _(result).must_answer <<~'OUT'
      hello, ffi
      10
      hello, ffi
      [10, 20, 30]
      20
      12
    OUT
  end

  it "a platform typedef is legal in argument and return position, where a struct field fixes a width" do
    result = ze0(<<~'RUBY')
      # A POSIX typedef whose width differs between zeo's targets (mode_t is u16
      # on macOS, u32 on glibc) is legal in argument/return position -- the
      # generated code spells the TARGET's own libc alias, so the C toolchain
      # supplies the real width.
      #
      # A struct FIELD cannot wait that long: its width fixes every following
      # field's offset while the layout lowers. zeo answers from the libc the
      # COMPILER was built against, which is exact for the one target it emits for
      # -- the same assumption the baked RUBY_PLATFORM and RbConfig::CONFIG already
      # make. The struct checks below print only facts that hold on every target,
      # since the widths themselves deliberately do not.
      require "ffi"
      require "tempfile"

      module C
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :chmod, [:string, :mode_t], :int
        attach_function :clock, [], :clock_t
      end

      f = Tempfile.new("zeo-mode")
      puts C.chmod(f.path, 0o644)
      puts format("%o", File.stat(f.path).mode & 0o7777)
      puts C.chmod(f.path, 0o600)
      puts format("%o", File.stat(f.path).mode & 0o7777)
      puts C.clock.is_a?(Integer)
      f.close!

      class Timing < FFI::Struct
        layout :marker, :uint32, :elapsed, :clock_t
      end

      class Marker < FFI::Struct
        layout :marker, :uint32
      end

      t = Timing.new
      t[:marker] = 7
      t[:elapsed] = 123_456
      puts t[:marker]
      puts t[:elapsed]
      puts Timing.offset_of(:marker)
      puts Timing.offset_of(:elapsed) >= 4
      puts Timing.size > Marker.size

      # `sa_family_t` is the narrowest of the family -- one byte on macOS, two on
      # glibc -- so it goes LAST, where its width shifts nothing.
      class Addr < FFI::Struct
        layout :data, [:char, 8], :family, :sa_family_t
      end

      a = Addr.new
      a[:family] = 2
      puts a[:family]
      puts Addr.offset_of(:data)
      puts Addr.offset_of(:family) >= 8
    RUBY

    _(result).must_answer <<~'OUT'
      0
      644
      0
      600
      true
      7
      123456
      0
      true
      true
      2
      0
      true
    OUT
  end

  it "a Struct layout answers size, offset_of and members over an owned MemoryPointer" do
    result = ze0(<<~'RUBY')
      # FFI::Struct + layout (#204 follow-on): C field offsets/alignment, [] / []=,
      # size, offset_of, members -- synthesized over an FFI::MemoryPointer.
      require "ffi"

      class Point < FFI::Struct
        layout :x, :int, :y, :int, :label, :pointer
      end

      puts Point.size
      puts Point.offset_of(:y)
      puts Point.offset_of(:label)
      puts Point.members.inspect

      p = Point.new
      p[:x] = 3
      p[:y] = 7
      puts p[:x]
      puts p[:y]

      class Mixed < FFI::Struct
        layout :flag, :int8, :count, :long, :ratio, :double
      end
      puts Mixed.size
      puts Mixed.offset_of(:count)
      puts Mixed.offset_of(:ratio)
    RUBY

    _(result).must_answer <<~'OUT'
      16
      4
      8
      [:x, :y, :label]
      3
      7
      24
      8
      16
    OUT
  end

  it "a struct class answers offsets and a layout whose fields carry name, offset, size and type" do
    result = ze0(<<~'RUBY')
      # A struct class describes itself: `.offsets`, and a `.layout` reader
      # answering an `FFI::StructLayout` whose fields carry each field's name,
      # offset, size, alignment and TYPE. zeo builds all of it from the layout its
      # compiler already walked, so the descriptors describe exactly the bytes the
      # generated accessors read.
      #
      # One divergence, stated in `ext/ffi/lib/ffi.rb` and not visible here: a
      # `:long` field reports `Type::Builtin::INT64` rather than `LONG`, because
      # the compiler folds the two to one width before a layout is recorded.
      require "ffi"

      class Inner < FFI::Struct
        layout :q, :int
      end

      class Wide < FFI::Struct
        layout :a, :int,
               :b, :pointer,
               :c, [:char, 8],
               :d, :double,
               :e, Inner,
               :f, :string,
               :g, callback([:int], :void),
               :h, :bool
      end

      p Wide.offsets
      p Wide.new.offsets == Wide.offsets

      l = Wide.layout
      p [l.class, l.size, l.alignment, l.members]

      # A layout IS a type, as are the three non-scalar descriptors -- so each
      # carries the builtin type constants. Only `Field` is a plain object.
      p [l.class.ancestors.first(3), l.is_a?(FFI::Type)]
      p [FFI::ArrayType.superclass, FFI::StructByValue.superclass, FFI::FunctionType.superclass]
      p [FFI::StructLayout::Field.superclass, FFI::StructLayout.const_get(:INT32).inspect]
      l.fields.each { |f| p [f.class, f.name, f.offset, f.size, f.alignment, f.type.class] }

      # The reader is memoized, and `to_a` is `fields`.
      p [Wide.layout.equal?(Wide.layout), l.to_a == l.fields]
      p [l.offset_of(:d), l[:e].offset, l.offsets == Wide.offsets]

      # An inline array's type knows its element and its count.
      p [l[:c].type.length, l[:c].type.elem_type.inspect]

      # A field reads and writes through a pointer to the struct's first byte,
      # with every conversion the struct's own `[]` performs.
      s = Wide.new
      s[:a] = 7
      s[:d] = 1.5
      p [l[:a].get(s.pointer), l[:d].get(s.pointer)]
      l[:a].put(s.pointer, 9)
      p s[:a]
      p l[:c].get(s.pointer).class

      # A name this layout has no field for answers nil, not an error.
      p l[:nope]
    RUBY

    _(result).must_answer <<~'OUT'
      [[:a, 0], [:b, 8], [:c, 16], [:d, 24], [:e, 32], [:f, 40], [:g, 48], [:h, 56]]
      true
      [FFI::StructLayout, 64, 8, [:a, :b, :c, :d, :e, :f, :g, :h]]
      [[FFI::StructLayout, FFI::Type, Object], true]
      [FFI::Type, FFI::Type, FFI::Type]
      [Object, "#<FFI::Type::Builtin::INT32 size=4 alignment=4>"]
      [FFI::StructLayout::Number, :a, 0, 4, 4, FFI::Type::Builtin]
      [FFI::StructLayout::Pointer, :b, 8, 8, 8, FFI::Type::Builtin]
      [FFI::StructLayout::Array, :c, 16, 8, 1, FFI::ArrayType]
      [FFI::StructLayout::Number, :d, 24, 8, 8, FFI::Type::Builtin]
      [FFI::StructLayout::InnerStruct, :e, 32, 4, 4, FFI::StructByValue]
      [FFI::StructLayout::String, :f, 40, 8, 8, FFI::Type::Builtin]
      [FFI::StructLayout::Function, :g, 48, 8, 8, FFI::FunctionType]
      [FFI::StructLayout::Number, :h, 56, 1, 1, FFI::Type::Builtin]
      [true, true]
      [24, 32, true]
      [8, "#<FFI::Type::Builtin::INT8 size=1 alignment=1>"]
      [7, 1.5]
      9
      FFI::StructLayout::CharArray
      nil
    OUT
  end

  it "an inline array field stores its elements in place and reads back as a proxy over them" do
    result = ze0(<<~'RUBY')
      # An INLINE array field (`layout :bytes, [:uint8, 4]`) stores its elements in
      # place, so it is the field that decides where every following one starts --
      # and reading it yields ruby's own proxy OVER that memory, not a copy.
      #
      # zeo refused the whole struct: `[:uint8, 4]` is not a symbol, so the layout
      # never parsed. The offsets, the two proxy classes, and which of them answers
      # `to_s` are all observable, so all three are matched here rather than
      # approximated.
      require "ffi"

      class Mixed < FFI::Struct
        layout :a, [:int32, 3], :b, [:char, 4], :c, [:uint8, 2], :d, [:double, 2]
      end

      # C alignment: each array aligns to its ELEMENT, and the struct rounds up to
      # its widest member.
      p Mixed.size
      p [Mixed.offset_of(:a), Mixed.offset_of(:b), Mixed.offset_of(:c), Mixed.offset_of(:d)]
      p Mixed.members

      # `CharArray` for an 8-bit element, `InlineArray` otherwise -- the gem's own
      # split, and the reason only one of them answers `to_s`.
      s = Mixed.new
      p [s[:a].class, s[:b].class, s[:c].class, s[:d].class]
      p [s[:a].size, s[:d].size]
      p s[:b].respond_to?(:to_str)
      p s[:a].respond_to?(:to_str)

      # The proxy writes THROUGH to the struct's memory.
      s[:a][1] = 9
      p s[:a].to_a
      s[:b][0] = 72
      s[:b][1] = 105
      p s[:b].to_s

      # ...and a whole-array assignment is refused, as ruby refuses it.
      begin
        s[:a] = [1, 2, 3]
      rescue NotImplementedError => e
        p e.message
      end

      # An array field does not disturb the ordinary fields around it.
      class Framed < FFI::Struct
        layout :tag, :int32, :bytes, [:uint8, 4], :tail, :int32
      end
      f = Framed.new
      f[:tag] = 7
      f[:tail] = 9
      f[:bytes][3] = 255
      p [f[:tag], f[:tail], f[:bytes].to_a]
      p Framed.size

      # The element count may be a constant this body already set -- C bindings spell
      # array widths that way far more often than as bare numbers (sys-filesystem).
      class Named < FFI::Struct
        NAME_LEN = 8
        layout :name, [:char, NAME_LEN], :id, :int32
      end
      p [Named.size, Named.offset_of(:id), Named.new[:name].size]

      # `each`/`to_a` come from Enumerable over the same proxy.
      n = Named.new
      n[:name][0] = 90
      p n[:name].each_with_index.first(2)
      p n[:name].to_a.length

      # A SECOND struct with an array field reuses the same proxy classes rather than
      # redefining them.
      class Other < FFI::Struct
        layout :v, [:uint8, 2]
      end
      p Other.new[:v].class == Framed.new[:bytes].class
    RUBY

    _(result).must_answer <<~'OUT'
      40
      [0, 12, 16, 24]
      [:a, :b, :c, :d]
      [FFI::Struct::InlineArray, FFI::StructLayout::CharArray, FFI::StructLayout::CharArray, FFI::Struct::InlineArray]
      [3, 2]
      true
      false
      [0, 9, 0]
      "Hi"
      "cannot set array field"
      [7, 9, [0, 0, 0, 255]]
      12
      [12, 8, 8]
      [[90, 0], [0, 1]]
      8
      true
    OUT
  end

  it "a struct auto-converts to its pointer at a C :pointer argument" do
    result = ze0(<<~'RUBY')
      # FFI `FFI::Struct` + `layout`: a `class T < FFI::Struct`
      # with a `layout` gets synthesized `[]`/`[]=`/`size`/`offset_of`/`members`
      # over an owned `FFI::MemoryPointer`, with C field offsets/alignment. The
      # struct is auto-converted to its pointer when passed to a C `:pointer`
      # argument (`gettimeofday` fills `tv_sec`). Byte-identical to `ffi 1.17.4`.

      require "ffi"
      class Timeval < FFI::Struct
        layout :tv_sec, :long, :tv_usec, :int
      end
      puts Timeval.size
      puts Timeval.offset_of(:tv_usec)
      puts Timeval.members.inspect
      t = Timeval.new
      t[:tv_sec] = 123
      t[:tv_usec] = 456
      puts t[:tv_sec]
      puts t[:tv_usec]

      class Mixed < FFI::Struct
        layout :a, :int8, :b, :long, :c, :int
      end
      puts Mixed.size
      puts Mixed.offset_of(:b)
      puts Mixed.offset_of(:c)

      module C
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :gettimeofday, [:pointer, :pointer], :int
      end
      tv = Timeval.new
      C.gettimeofday(tv, nil)
      puts(tv[:tv_sec] > 1_000_000)
    RUBY

    _(result).must_answer <<~'OUT'
      16
      8
      [:tv_sec, :tv_usec]
      123
      456
      24
      8
      16
      true
    OUT
  end

  it "FFI::Type::Builtin holds one object per canonical type, and LONG and INT64 are two" do
    skip "runs only on macos" unless ["macos"].include?(Ze0::Spec.platform)

    result = ze0(<<~'RUBY')

      # `FFI::Type::Builtin` holds one instance per CANONICAL type, and the aliases
      # are extra constants naming the SAME object -- `:char` really is
      # `Type::Builtin::INT8`, which is why `CHAR.inspect` says `INT8`.
      #
      # The canonical set is not the set of distinct C widths. `LONG` and `INT64`
      # are separate objects that compare UNEQUAL although both are eight signed
      # bytes on this target, and so are `ULONG` and `UINT64`. Collapsing them by
      # width made `ffi_args.last == FFI::Type::Builtin::LONG` answer true for an
      # `:int64` argument, where the gem answers false.
      #
      # Only the constants naming a TYPE are listed. `FFI::Type` also carries four
      # naming a CLASS -- `Array`, `Function`, `Struct` and `Mapped`, for the
      # non-scalar type descriptors -- pinned by
      # `tests/ffi_type_descriptor_classes.rb`.
      require "ffi"

      types = FFI::Type::Builtin.constants.sort.select do |name|
        FFI::Type::Builtin.const_get(name).is_a?(FFI::Type)
      end
      p types
      types.each { |name| puts "#{name}\t#{FFI::Type::Builtin.const_get(name).inspect}" }

      # Two names for one type ARE one object; two types of one width are not.
      p [
        FFI::Type::Builtin::CHAR.equal?(FFI::Type::Builtin::INT8),
        FFI::Type::Builtin::DOUBLE.equal?(FFI::Type::Builtin::FLOAT64),
        FFI::Type::Builtin::LONG_LONG.equal?(FFI::Type::Builtin::INT64),
        FFI::Type::Builtin::LONG.equal?(FFI::Type::Builtin::INT64),
        FFI::Type::Builtin::ULONG.equal?(FFI::Type::Builtin::UINT64),
      ]
      p [
        FFI::Type::Builtin::CHAR == FFI::Type::Builtin::INT8,
        FFI::Type::Builtin::LONG == FFI::Type::Builtin::INT64,
        FFI::Type::Builtin::ULONG == FFI::Type::Builtin::UINT64,
        FFI::Type::Builtin::LONG.size == FFI::Type::Builtin::INT64.size,
      ]

      # `FFI::Type` spells the same constants, and `VOID` there is the very object
      # `Builtin::VOID` is.
      p FFI::Type::VOID.equal?(FFI::Type::Builtin::VOID)
      p [FFI::Type.instance_methods(false).sort, FFI::Type::Builtin.instance_methods(false).sort]

      # `NativeType` and the top-level `TYPE_*` constants are a third and fourth
      # name for the canonical set -- only the canonical names, no aliases.
      p FFI::NativeType.constants.sort
      p FFI.constants.grep(/^TYPE_/).sort
      p [
        FFI::TYPE_INT32.equal?(FFI::Type::Builtin::INT32),
        FFI::NativeType::LONG.equal?(FFI::Type::Builtin::LONG),
      ]

      # The keyword each spelling resolves to, and the lookup that reads it.
      p FFI::TypeDefs.keys.first(29)
      p %i[void int uint long ulong long_long float double pointer string buffer_in varargs]
        .map { |k| FFI.find_type(k).inspect }
      p %i[char short int long float double pointer].map { |k| FFI.type_size(k) }
      p FFI.find_type(FFI::Type::Builtin::BOOL).equal?(FFI::Type::Builtin::BOOL)
      p FFI.find_type(:int, { int: FFI::Type::Builtin::INT8 }).inspect

      # A runtime `typedef` is reflection: it answers `find_type` and leaves the
      # published `TypeDefs` table alone, exactly as the gem's C half does.
      FFI.typedef(:uint32, :my_handle_t)
      p [FFI.find_type(:my_handle_t).inspect, FFI::TypeDefs[:my_handle_t]]

      begin
        FFI.find_type(:definitely_not_a_type)
      rescue TypeError => e
        p [e.class, e.message]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:BOOL, :BUFFER_IN, :BUFFER_INOUT, :BUFFER_OUT, :CHAR, :DOUBLE, :FLOAT, :FLOAT32, :FLOAT64, :INT, :INT16, :INT32, :INT64, :INT8, :LONG, :LONGDOUBLE, :LONG_LONG, :POINTER, :SCHAR, :SHORT, :SINT, :SLONG, :SLONG_LONG, :SSHORT, :STRING, :UCHAR, :UINT, :UINT16, :UINT32, :UINT64, :UINT8, :ULONG, :ULONG_LONG, :USHORT, :VARARGS, :VOID]
      BOOL	#<FFI::Type::Builtin::BOOL size=1 alignment=1>
      BUFFER_IN	#<FFI::Type::Builtin::BUFFER_IN size=8 alignment=8>
      BUFFER_INOUT	#<FFI::Type::Builtin::BUFFER_INOUT size=8 alignment=8>
      BUFFER_OUT	#<FFI::Type::Builtin::BUFFER_OUT size=8 alignment=8>
      CHAR	#<FFI::Type::Builtin::INT8 size=1 alignment=1>
      DOUBLE	#<FFI::Type::Builtin::FLOAT64 size=8 alignment=8>
      FLOAT	#<FFI::Type::Builtin::FLOAT32 size=4 alignment=4>
      FLOAT32	#<FFI::Type::Builtin::FLOAT32 size=4 alignment=4>
      FLOAT64	#<FFI::Type::Builtin::FLOAT64 size=8 alignment=8>
      INT	#<FFI::Type::Builtin::INT32 size=4 alignment=4>
      INT16	#<FFI::Type::Builtin::INT16 size=2 alignment=2>
      INT32	#<FFI::Type::Builtin::INT32 size=4 alignment=4>
      INT64	#<FFI::Type::Builtin::INT64 size=8 alignment=8>
      INT8	#<FFI::Type::Builtin::INT8 size=1 alignment=1>
      LONG	#<FFI::Type::Builtin::LONG size=8 alignment=8>
      LONGDOUBLE	#<FFI::Type::Builtin::LONGDOUBLE size=8 alignment=8>
      LONG_LONG	#<FFI::Type::Builtin::INT64 size=8 alignment=8>
      POINTER	#<FFI::Type::Builtin::POINTER size=8 alignment=8>
      SCHAR	#<FFI::Type::Builtin::INT8 size=1 alignment=1>
      SHORT	#<FFI::Type::Builtin::INT16 size=2 alignment=2>
      SINT	#<FFI::Type::Builtin::INT32 size=4 alignment=4>
      SLONG	#<FFI::Type::Builtin::LONG size=8 alignment=8>
      SLONG_LONG	#<FFI::Type::Builtin::INT64 size=8 alignment=8>
      SSHORT	#<FFI::Type::Builtin::INT16 size=2 alignment=2>
      STRING	#<FFI::Type::Builtin::STRING size=8 alignment=8>
      UCHAR	#<FFI::Type::Builtin::UINT8 size=1 alignment=1>
      UINT	#<FFI::Type::Builtin::UINT32 size=4 alignment=4>
      UINT16	#<FFI::Type::Builtin::UINT16 size=2 alignment=2>
      UINT32	#<FFI::Type::Builtin::UINT32 size=4 alignment=4>
      UINT64	#<FFI::Type::Builtin::UINT64 size=8 alignment=8>
      UINT8	#<FFI::Type::Builtin::UINT8 size=1 alignment=1>
      ULONG	#<FFI::Type::Builtin::ULONG size=8 alignment=8>
      ULONG_LONG	#<FFI::Type::Builtin::UINT64 size=8 alignment=8>
      USHORT	#<FFI::Type::Builtin::UINT16 size=2 alignment=2>
      VARARGS	#<FFI::Type::Builtin::VARARGS size=1 alignment=1>
      VOID	#<FFI::Type::Builtin::VOID size=1 alignment=1>
      [true, true, true, false, false]
      [true, false, false, true]
      true
      [[:alignment, :inspect, :size], [:inspect]]
      [:BOOL, :BUFFER_IN, :BUFFER_INOUT, :BUFFER_OUT, :FLOAT32, :FLOAT64, :INT16, :INT32, :INT64, :INT8, :LONG, :LONGDOUBLE, :POINTER, :STRING, :UINT16, :UINT32, :UINT64, :UINT8, :ULONG, :VARARGS, :VOID]
      [:TYPE_BOOL, :TYPE_BUFFER_IN, :TYPE_BUFFER_INOUT, :TYPE_BUFFER_OUT, :TYPE_FLOAT32, :TYPE_FLOAT64, :TYPE_INT16, :TYPE_INT32, :TYPE_INT64, :TYPE_INT8, :TYPE_LONG, :TYPE_LONGDOUBLE, :TYPE_POINTER, :TYPE_STRING, :TYPE_UINT16, :TYPE_UINT32, :TYPE_UINT64, :TYPE_UINT8, :TYPE_ULONG, :TYPE_VARARGS, :TYPE_VOID]
      [true, true]
      [:void, :bool, :string, :char, :uchar, :short, :ushort, :int, :uint, :long, :ulong, :long_long, :ulong_long, :float, :double, :long_double, :pointer, :int8, :uint8, :int16, :uint16, :int32, :uint32, :int64, :uint64, :buffer_in, :buffer_out, :buffer_inout, :varargs]
      ["#<FFI::Type::Builtin::VOID size=1 alignment=1>", "#<FFI::Type::Builtin::INT32 size=4 alignment=4>", "#<FFI::Type::Builtin::UINT32 size=4 alignment=4>", "#<FFI::Type::Builtin::LONG size=8 alignment=8>", "#<FFI::Type::Builtin::ULONG size=8 alignment=8>", "#<FFI::Type::Builtin::INT64 size=8 alignment=8>", "#<FFI::Type::Builtin::FLOAT32 size=4 alignment=4>", "#<FFI::Type::Builtin::FLOAT64 size=8 alignment=8>", "#<FFI::Type::Builtin::POINTER size=8 alignment=8>", "#<FFI::Type::Builtin::STRING size=8 alignment=8>", "#<FFI::Type::Builtin::BUFFER_IN size=8 alignment=8>", "#<FFI::Type::Builtin::VARARGS size=1 alignment=1>"]
      [1, 2, 4, 8, 4, 8, 8]
      true
      "#<FFI::Type::Builtin::INT8 size=1 alignment=1>"
      ["#<FFI::Type::Builtin::UINT32 size=4 alignment=4>", nil]
      [TypeError, "unable to resolve type 'definitely_not_a_type'"]
    OUT
  end

  it "an integer slot range-checks by the converter the gem picks, not by the slot's width" do
    result = ze0(<<~'RUBY')
      # An FFI integer slot converts the way the gem does, and THE SLOT'S WIDTH IS
      # NOT THE RANGE CHECKED: the gem reaches C through NUM2INT/NUM2UINT for a 1-,
      # 2- or 4-byte slot and NUM2LL/NUM2ULL for an 8-byte one. So a 1- or 2-byte
      # slot truncates silently while a 4-byte one refuses past the 32-bit limits,
      # and the four converters each name themselves in their own message.
      #
      # The unsigned converters wrap a negative number, which is why
      # `write_uint64(-1)` reads back as 2**64-1 -- a value no `i64` holds, so the
      # read has to answer a Bignum.

      require "ffi"

      m = FFI::MemoryPointer.new(:uint64, 2)

      def t(label)
        r = begin
          yield.inspect
        rescue Exception => e
          "#{e.class}: #{e.message}"
        end
        puts format("%-18s %s", label, r)
      end

      t("u64 max") { m.write_uint64(0xFFFF_FFFF_FFFF_FFFF); m.read_uint64 }
      t("u64 -1") { m.write_uint64(-1); m.read_uint64 }
      t("u64 2**63") { m.write_uint64(0x8000_0000_0000_0000); m.read_uint64 }
      t("u64 -2**63") { m.write_uint64(-2**63); m.read_uint64 }
      t("u64 2**64") { m.write_uint64(2**64) }
      t("u64 -2**63-1") { m.write_uint64(-2**63 - 1) }
      t("i64 -1") { m.write_int64(-1); m.read_int64 }
      t("i64 min") { m.write_int64(-2**63); m.read_int64 }
      t("i64 2**63") { m.write_int64(2**63) }
      t("i64 min-1") { m.write_int64(-2**63 - 1) }

      t("u32 max") { m.write_uint32(0xFFFF_FFFF); m.read_uint32 }
      t("u32 -1") { m.write_uint32(-1); m.read_uint32 }
      t("u32 -2**31") { m.write_uint32(-2**31); m.read_uint32 }
      t("u32 2**32") { m.write_uint32(2**32) }
      t("u32 -2**31-1") { m.write_uint32(-2**31 - 1) }
      t("i32 2**31") { m.write_int32(2**31) }
      t("i32 -2**31-1") { m.write_int32(-2**31 - 1) }

      # 8- and 16-bit slots truncate rather than refuse, but still go through the
      # 32-bit converter, so they refuse the same values a 32-bit slot does.
      t("u8 255") { m.write_uint8(255); m.read_uint8 }
      t("u8 -1") { m.write_uint8(-1); m.read_uint8 }
      t("u8 256") { m.write_uint8(256); m.read_uint8 }
      t("i8 128") { m.write_int8(128); m.read_int8 }
      t("u16 65536") { m.write_uint16(65536); m.read_uint16 }
      t("u8 2**32") { m.write_uint8(2**32) }
      t("u8 -2**31-1") { m.write_uint8(-2**31 - 1) }

      # A Float truncates toward zero; out of range it names ITSELF, not "bignum".
      t("u64 1.5") { m.write_uint64(1.5); m.read_uint64 }
      t("u64 -1.5") { m.write_uint64(-1.5); m.read_uint64 }
      t("u32 2.9") { m.write_uint32(2.9); m.read_uint32 }
      t("u64 1e30") { m.write_uint64(1e30) }
      t("i64 nan") { m.write_int64(Float::NAN) }

      class Seven
        def to_int = 7
      end
      t("to_int") { m.write_uint64(Seven.new); m.read_uint64 }
      t("string") { m.write_uint64("1") }
      t("nil") { m.write_uint64(nil) }

      t("array u64") { m.write_array_of_uint64([0xFFFF_FFFF_FFFF_FFFF, 1]); m.read_array_of_uint64(2) }
      t("array i64 big") { m.write_array_of_int64([0xFFFF_FFFF_FFFF_FFFF]) }

      t("inspect") { m.inspect }
      t("inspect raw") { FFI::Pointer.new(4096).inspect }
      t("inspect null") { FFI::Pointer::NULL.inspect }
      t("inspect slice") { m.slice(0, 4).inspect }
      t("to_s is inspect") { m.to_s == m.inspect }
    RUBY

    _(result).must_answer <<~'OUT'
      u64 max            18446744073709551615
      u64 -1             18446744073709551615
      u64 2**63          9223372036854775808
      u64 -2**63         9223372036854775808
      u64 2**64          RangeError: bignum too big to convert into 'unsigned long long'
      u64 -2**63-1       RangeError: bignum out of range of unsigned long long
      i64 -1             -1
      i64 min            -9223372036854775808
      i64 2**63          RangeError: bignum too big to convert into 'long long'
      i64 min-1          RangeError: bignum too big to convert into 'long long'
      u32 max            4294967295
      u32 -1             4294967295
      u32 -2**31         2147483648
      u32 2**32          RangeError: integer 4294967296 too big to convert to 'unsigned int'
      u32 -2**31-1       RangeError: integer -2147483649 too small to convert to 'unsigned int'
      i32 2**31          RangeError: integer 2147483648 too big to convert to 'int'
      i32 -2**31-1       RangeError: integer -2147483649 too small to convert to 'int'
      u8 255             255
      u8 -1              255
      u8 256             0
      i8 128             -128
      u16 65536          0
      u8 2**32           RangeError: integer 4294967296 too big to convert to 'unsigned int'
      u8 -2**31-1        RangeError: integer -2147483649 too small to convert to 'unsigned int'
      u64 1.5            1
      u64 -1.5           18446744073709551615
      u32 2.9            2
      u64 1e30           RangeError: float 1e+30 out of range of unsigned long long
      i64 nan            RangeError: float NaN out of range of long long
      to_int             7
      string             TypeError: no implicit conversion of String into Integer
      nil                TypeError: no implicit conversion of nil into Integer
      array u64          [18446744073709551615, 1]
      array i64 big      RangeError: bignum too big to convert into 'long long'
      inspect            "#<FFI::MemoryPointer address=0xADDR size=16>"
      inspect raw        "#<FFI::Pointer address=0xADDR>"
      inspect null       "#<FFI::Pointer address=0xADDR>"
      inspect slice      "#<FFI::Pointer address=0xADDR size=4>"
      to_s is inspect    true
    OUT
  end

  it "a trailing :varargs spec makes the function variadic, taking (type, value) pairs" do
    result = ze0(<<~'RUBY')
      # Variadic FFI through the real ffi gem API: a trailing :varargs spec makes
      # the function variadic, and each call passes (type, value) pairs for the
      # variable part with C default promotions (int->int, float->double,
      # str->const char*). NOTE: printf writes through C stdio, whose buffer
      # flushes after Ruby's own stdout at process exit, so when stdout is a pipe
      # all printf output trails the Ruby-side puts output.
      require "ffi"

      module C
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :printf, [:string, :varargs], :int
      end

      # int + int + str varargs; printf returns the byte count written
      n = C.printf("%d-%d-%s\n", :int, 1, :int, 22, :string, "hi")
      puts n

      # float vararg promotes to double
      C.printf("%.2f\n", :double, 3.5)

      # multiple mixed args
      C.printf("[%s=%d]\n", :string, "k", :int, 7)

      # no extra args (just the fixed format)
      C.printf("plain\n")
    RUBY

    _(result).must_answer <<~'OUT'
      8
      1-22-hi
      3.50
      [k=7]
      plain
    OUT
  end

  it "a variadic call builds its interface at run time, and a callback type takes a ruby Proc" do
    result = ze0(<<~'RUBY')
      # Variadic FFI and Ruby-Proc callbacks, AOT-compiled through libffi: a
      # `[.., :varargs]` function builds its call interface at runtime, and a
      # `callback` type turns a Ruby Proc into a C function pointer.
      require "ffi"

      module C
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
        callback :cmp, [:pointer, :pointer], :int
        attach_function :qsort, [:pointer, :size_t, :size_t, :cmp], :void
      end

      # Variadic: format mixed int/string/double varargs into a buffer.
      buf = FFI::MemoryPointer.new(:char, 64)
      n = C.snprintf(buf, 64, "%d items, %s, %.2f done", :int, 3, :string, "ok", :double, 0.75)
      puts n
      puts buf.read_string

      # Callback: a Ruby Proc sorts a C array in place via qsort.
      arr = FFI::MemoryPointer.new(:int32, 6)
      arr.write_array_of_int32([5, 2, 8, 1, 9, 3])
      C.qsort(arr, 6, 4, proc { |a, b| a.read_int32 <=> b.read_int32 })
      p arr.read_array_of_int32(6)
    RUBY

    _(result).must_answer <<~'OUT'
      22
      3 items, ok, 0.75 done
      [1, 2, 3, 5, 8, 9]
    OUT
  end
end
