# frozen_string_literal: true

require "spec_helper"

describe "FFI programs" do
  it "by value struct return through the runtime tier" do
    result = zr(<<~'RUBY')
      # A library named by a CANDIDATE LIST is resolved with dlopen at the first
      # call, so its functions go through libffi rather than a compile-time
      # `extern`. A struct returned BY VALUE used to be refused on that tier: the
      # extern tier lets the C ABI classify the aggregate through a mirror
      # declaration, and libffi needs the same classification built by hand.
      #
      # It gets it from the very field descriptor the by-value ARGUMENT direction
      # already builds, so both directions now agree on every tier. `div` and
      # `ldiv` return their quotient/remainder pair by value on every libc.
      require "ffi"

      class Div < FFI::Struct
        layout :quot, :int, :rem, :int
      end

      class LDiv < FFI::Struct
        layout :quot, :long, :rem, :long
      end

      module L
        extend FFI::Library
        # The absent first candidate is what forces the runtime tier: the library
        # is only decidable once something tries to open it.
        ffi_lib ["/no/such/dir/libnothing.so", FFI::Library::LIBC]

        attach_function :div, [:int, :int], Div.by_value
        attach_function :ldiv, [:long, :long], LDiv.by_value
        attach_function :labs, [:long], :long
      end

      d = L.div(17, 5)
      p d.class
      p d[:quot]
      p d[:rem]

      l = L.ldiv(-17, 5)
      p l[:quot]
      p l[:rem]

      # A scalar return on the same tier is unchanged.
      p L.labs(-3)
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      Div
      3
      2
      -3
      -2
      3
      still running
    OUT
  end

  it "callback exception surfaces from the c call" do
    skip "runs only on macos" unless ["macos"].include?(Zr::Spec.platform)

    result = zr(<<~'RUBY')

      # An IMP written in Ruby and installed with `class_addMethod`: Objective-C
      # reaches it through `objc_msgSend`, an attached function that takes no
      # callback argument of its own. The gem still raises the exception the IMP
      # raised from that call -- so every forward call asks for a stashed callback
      # error on return, not only one that passed a callback. A `:void` IMP is the
      # ordinary shape of a notification handler, and builds.

      require "ffi"
      module OC
        extend FFI::Library
        ffi_lib "objc"
        ffi_lib "/System/Library/Frameworks/Foundation.framework/Foundation"
        attach_function :objc_getClass, [:string], :pointer
        attach_function :sel_registerName, [:string], :pointer
        attach_function :objc_allocateClassPair, [:pointer, :string, :size_t], :pointer
        attach_function :objc_registerClassPair, [:pointer], :void
        attach_function :class_addMethod, [:pointer, :pointer, :pointer, :string], :bool
        attach_function :send_id, :objc_msgSend, [:pointer, :pointer], :pointer
        attach_function :send_long_ret, :objc_msgSend, [:pointer, :pointer], :long
        attach_function :send_void_obj, :objc_msgSend, [:pointer, :pointer, :pointer], :void
      end
      def sel(s) = OC.sel_registerName(s)
      calls = []
      klass = OC.objc_allocateClassPair(OC.objc_getClass("NSObject"), "ZeoProbe", 0)
      imps = []
      imps << (f = FFI::Function.new(:void, [:pointer, :pointer, :pointer], proc { |_s, _c, _a| calls << :void; nil }))
      OC.class_addMethod(klass, sel("note:"), f, "v@:@")
      imps << (f = FFI::Function.new(:long, [:pointer, :pointer], proc { |_s, _c| raise "boom inside imp" }))
      OC.class_addMethod(klass, sel("explode"), f, "q@:")
      imps << (f = FFI::Function.new(:void, [:pointer, :pointer, :pointer]) { |_s, _c, _a| calls << :block })
      OC.class_addMethod(klass, sel("noteBlock:"), f, "v@:@")
      OC.objc_registerClassPair(klass)
      obj = OC.send_id(OC.send_id(klass, sel("alloc")), sel("init"))
      OC.send_void_obj(obj, sel("note:"), obj)
      OC.send_void_obj(obj, sel("noteBlock:"), obj)
      p calls
      begin
        OC.send_long_ret(obj, sel("explode"))
      rescue => e
        p [:rescued, e.class, e.message]
      end
      p OC.send_long_ret(obj, sel("hash")).class
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      [:void, :block]
      [:rescued, RuntimeError, "boom inside imp"]
      Integer
      done
    OUT
  end

  it "callback parameter naming a struct class" do
    result = zr(<<~'RUBY')
      # A `callback` whose parameter names an `FFI::Struct` subclass. zeo refused
      # these outright, on the belief that ruby-ffi hands the Proc a Struct instance
      # there and a raw pointer would be silently different behaviour.
      #
      # It hands a pointer. `StructByReference#from_native` would build a Struct, but
      # the callback path never routes an argument through the Ruby data converter --
      # the block below receives an `FFI::Pointer`, in ruby as in zeo. The old
      # rejection even told the author to "take :pointer and wrap it yourself", which
      # is exactly what the gem does for them.
      #
      # A callback RETURNING a struct class is still refused: nothing measured it,
      # and a silently wrong conversion is worse than a refusal.
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        class Pair < FFI::Struct
          layout :a, :int, :b, :int
        end

        callback :cmp, [Pair, Pair], :int
        attach_function :qsort, [:pointer, :size_t, :size_t, :cmp], :void
      end

      seen = nil
      compare = proc do |x, y|
        seen ||= x.class
        x.get_int32(0) <=> y.get_int32(0)
      end

      buf = FFI::MemoryPointer.new(:int, 4)
      [30, 1, 20, 2].each_with_index { |v, i| buf.put_int32(i * 4, v) }
      L.qsort(buf, 2, 8, compare)

      p seen
      p((0...4).map { |i| buf.get_int32(i * 4) })
    RUBY

    _(result).must_answer "FFI::Pointer\n[20, 2, 30, 1]\n"
  end

  it "callback proc drives qsort and bsearch" do
    result = zr(<<~'RUBY')
      require "ffi"
      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        callback :cmp, [:pointer, :pointer], :int
        attach_function :qsort,   [:pointer, :size_t, :size_t, :cmp], :void
        attach_function :bsearch, [:pointer, :pointer, :size_t, :size_t, :cmp], :pointer
      end
      cmp = proc { |a, b| a.read_int64 <=> b.read_int64 }
      arr = FFI::MemoryPointer.new(:int64, 5)
      arr.write_array_of_int64([9, 3, 7, 1, 5])
      L.qsort(arr, 5, 8, cmp)
      p arr.read_array_of_int64(5)
      arr2 = FFI::MemoryPointer.new(:int64, 4)
      arr2.write_array_of_int64([10, 20, 30, 40])
      L.qsort(arr2, 4, 8, proc { |a, b| b.read_int64 <=> a.read_int64 })
      p arr2.read_array_of_int64(4)
      key = FFI::MemoryPointer.new(:int64, 1)
      key.write_int64(7)
      hit = L.bsearch(key, arr, 5, 8, cmp)
      puts(hit == nil ? "miss" : hit.read_int64)
      key.write_int64(4)
      puts(L.bsearch(key, arr, 5, 8, cmp) == nil ? "miss" : "hit")
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3, 5, 7, 9]
      [40, 30, 20, 10]
      7
      miss
    OUT
  end

  it "computed c symbol name folds" do
    result = zr(<<~'RUBY')
      # A library whose windows entry points carry a suffix writes the suffix once
      # at the top of the module and builds every C symbol out of it --
      # `attach_function :list_readers, 'SCardListReaders' + str_suffix, ...`, which
      # smartcard does nine times. The suffix is the same compile-time platform
      # question the guards fold, so the symbol name is a compile-time fact too.
      #
      # A plain READ of the local is not what stops the fold: nine declarations
      # share one suffix, and each of those reads is still the value the assignment
      # gave it. Only a rebind or an in-place mutation makes the value unreadable.
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        suffix = FFI::Platform.windows? ? "_s" : ""
        prefix = "str"

        attach_function :length, prefix + "len" + suffix, [:string], :size_t
        attach_function :compare, prefix + "cmp" + suffix, [:string, :string], :int
        # The 3-argument form computes the ruby name from the same string.
        attach_function "strlen", [:string], :size_t
      end

      p L.length("hello")
      p L.compare("a", "a")
      p L.compare("a", "b") < 0
      p L.strlen("worlds")

      # A local the body REBINDS between declarations reads as whatever the
      # preceding assignment left, exactly like ruby.
      module M
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        which = "len"
        attach_function :first, "str" + which, [:string], :size_t
        which = "cmp"
        attach_function :second, "str" + which, [:string, :string], :int
      end

      p M.first("four")
      p M.second("z", "z")
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      5
      0
      true
      6
      4
      0
      still running
    OUT
  end

  it "constant spells an ffi type" do
    result = zr(<<~'RUBY')
      # A constant holding a type symbol (`Word = :uint32`, smartcard) or an
      # `FFI::Type::X` object (`CFIndex = FFI::Type::LONG_LONG`, audio) is FFI
      # vocabulary: signatures and layouts naming the constant resolve through
      # its value, exactly as ruby-ffi's find_type does. The platform-guarded
      # spelling folds the same way at both stages.
      require "ffi"

      module Lib
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        if FFI::Platform.mac?
          Word = :uint32
        else
          Word = :uint32
        end
        # audio's spelling: the width picked by an ARCH string compare. Both
        # branches agree here so the golden holds on every host; the FOLD is
        # exercised either way (an unfolded guard poisons the constant).
        if FFI::Platform::ARCH == 'x86_64'
          CFIndex = FFI::Type::LONG_LONG
        else
          CFIndex = FFI::Type::LONG_LONG
        end

        attach_function :labs_w, :labs, [CFIndex], CFIndex

        class Holder < FFI::Struct
          layout :tag, Word,
                 :count, CFIndex
        end
      end

      p Lib.labs_w(-42)
      h = Lib::Holder.new
      h[:tag] = 7
      h[:count] = -3_000_000_000
      p h[:tag]
      p h[:count]
      p Lib::Holder.size
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      7
      -3000000000
      16
      still running
    OUT
  end

  it "empty array push ptr" do
    result = zr(<<~'RUBY')
      # #688 (ported to the real ffi gem API): empty `[]` followed by pushes of
      # FFI :pointer values must behave as an array of pointers, not silently
      # collapse to an int-array representation that would round-trip the pointer
      # through an integer.
      require "ffi"

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :malloc, [:size_t], :pointer
        attach_function :free,   [:pointer], :void
      end

      p1 = LibC.malloc(64)
      p2 = LibC.malloc(64)

      arr = []
      arr.push(p1)
      arr.push(p2)

      puts arr.length

      # Read back the pointers and confirm they're identical to what we pushed.
      got1 = arr[0]
      got2 = arr[1]
      puts (got1 == p1) ? "p1=match" : "p1=MISMATCH"
      puts (got2 == p2) ? "p2=match" : "p2=MISMATCH"

      LibC.free(p1)
      LibC.free(p2)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      p1=match
      p2=match
    OUT
  end

  it "enum member list the class body built" do
    result = zr(<<~'RUBY')
      # An `enum` member list is written three ways that are all compile-time
      # values: a word array mapped to symbols (`%w(...).map(&:to_sym)`, which is
      # what spotify does four times), a body-local array the class body built up
      # under guards, and that same array splatted in. All three name the members
      # the C header names, so all three lower to the same conversion table.
      #
      # The members are observable through a function typed with the enum: ffi
      # converts the symbol to its integer on the way in.
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        # `String#to_sym` is what the gem does to a string member anyway.
        enum :rate, %w(k160 k320 k96).map(&:to_sym)

        colours = [:red, :green]
        colours.push(:blue) if RUBY_PLATFORM =~ /darwin|linux|bsd/
        colours.push(:infra) if RUBY_PLATFORM =~ /mswin/
        enum :colour, colours

        attach_function :rate_code, :abs, [:rate], :int
        attach_function :colour_code, :abs, [:colour], :int
      end

      p L.rate_code(:k160)
      p L.rate_code(:k320)
      p L.rate_code(:k96)
      p L.colour_code(:red)
      p L.colour_code(:blue)
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
      0
      2
      still running
    OUT
  end

  it "every shape an eval once declined now compiles" do
    result = zr(<<~'RUBY', ruby: ["-W:no-experimental"])
      # There is no second evaluator to hand a declined shape to, so a shape
      # the compiler cannot lower raises `NotImplementedError` naming itself.
      # This test used to pin one such message -- and it had to be re-pointed
      # every time a shape closed, which is a test that rots into a lie. It
      # pins the CLOSURES instead: every shape a snippet once declined, each
      # answering what ruby answers.


      require "ffi"
      # an `FFI::Library` declaration: the directives stay ordinary calls
      # in a snippet, and the module's own rows attach at run time.
      eval <<~SRC
        module EvalLib
          extend FFI::Library
          ffi_lib FFI::Library::LIBC
          attach_function :abs, [:int], :int
        end
      SRC
      p EvalLib.abs(-3)
      # a `class < FFI::Struct`: its `layout` is replaced in place by
      # synthesized accessors, whose own source is the body text that runs.
      eval "class EvalStruct < FFI::Struct; layout :a, :int, :b, :int; end"
      p EvalStruct.size
      # `refine`/`using` at run time. (A `Ruby::Box` closed with them and
      # is pinned by `tests/a_snippet_mints_no_compile_time_box.rb`,
      # which the golden harness runs with `RUBY_BOX=1`.)
      eval "module EvalRef; refine(String) { def shout = upcase + '!' }; end"
      p eval("using EvalRef; 'hi'.shout")
    RUBY

    _(result).must_answer <<~'OUT'
      3
      8
      "HI!"
    OUT
  end

  it "exception in callback is reraised after the c call" do
    result = zr(<<~'RUBY')
      require "ffi"
      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        callback :cmp, [:pointer, :pointer], :int
        attach_function :qsort, [:pointer, :size_t, :size_t, :cmp], :void
      end
      arr = FFI::MemoryPointer.new(:int32, 3)
      arr.write_array_of_int32([3, 1, 2])
      begin
        L.qsort(arr, 3, 4, proc { |a, b| raise "boom from callback" })
      rescue => e
        puts "rescued: #{e.message}"
      end
    RUBY

    _(result).must_answer "rescued: boom from callback\n"
  end

  it "a blocking call with a callback" do
    result = zr(<<~'RUBY')
      # `blocking: true` beside a callback argument is legal: the gem releases the
      # GVL around the C body and the callback trampoline re-acquires before
      # re-entering ruby (rdkafka's poll loop is the shape). qsort sorting through
      # a ruby comparator, oracle-verified.
      require "ffi"

      module Q
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        callback :cmp_t, [:pointer, :pointer], :int
        attach_function :qsort, [:pointer, :size_t, :size_t, :cmp_t], :void, blocking: true
      end

      buf = FFI::MemoryPointer.new(:int32, 5)
      buf.write_array_of_int32([31, 4, 15, 9, 2])
      Q.qsort(buf, 5, 4, proc { |a, b| a.read_int32 <=> b.read_int32 })
      p buf.read_array_of_int32(5)
    RUBY

    _(result).must_answer "[2, 4, 9, 15, 31]\n"
  end

  it "a callback type declares a C function pointer, and a proc becomes one" do
    result = zr(<<~'RUBY')
      # Ported from spinel's ffi_callback trampoline to the real ffi gem API: a
      # `callback` type declares a C function-pointer type, and a Ruby proc passed
      # to an argument of that type becomes a C-callable trampoline -- so Ruby code
      # can be handed to qsort's comparator and bsearch's. Exercising both qsort
      # (`void *base`) and bsearch (`const void *base`) keeps the original's
      # coverage of both const-qualifications. (The original also registered an
      # atexit callback; ruby-ffi cannot run a Ruby callback during process exit,
      # so that leg is dropped in the port.)
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        callback :cmp, [:pointer, :pointer], :int
        attach_function :qsort,   [:pointer, :size_t, :size_t, :cmp], :void
        attach_function :bsearch, [:pointer, :pointer, :size_t, :size_t, :cmp], :pointer
      end

      CMP  = proc { |a, b| a.read_int64 <=> b.read_int64 }
      RCMP = proc { |a, b| b.read_int64 <=> a.read_int64 }

      arr = FFI::MemoryPointer.new(:int64, 8)
      arr.write_array_of_int64([3, 1, 4, 1, 5, 9, 2, 6])
      L.qsort(arr, 8, 8, CMP)
      p arr.read_array_of_int64(8)                 # ascending

      arr2 = FFI::MemoryPointer.new(:int64, 4)
      arr2.write_array_of_int64([10, 20, 30, 40])
      L.qsort(arr2, 4, 8, RCMP)
      p arr2.read_array_of_int64(4)                # descending

      # bsearch over the ascending array. The key is a one-element buffer holding
      # the value to find.
      key = FFI::MemoryPointer.new(:int64, 1)
      key.write_int64(5)
      hit = L.bsearch(key, arr, 8, 8, CMP)
      puts hit == nil ? "miss" : hit.read_int64    # 5

      key.write_int64(7)
      miss = L.bsearch(key, arr, 8, 8, CMP)
      puts miss == nil ? "miss" : miss.read_int64  # miss

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1, 2, 3, 4, 5, 6, 9]
      [40, 30, 20, 10]
      5
      miss
      done
    OUT
  end

  it "a callback declares a function pointer type" do
    result = zr(<<~'RUBY')
      # FFI `callback :tag, [args], ret` declares a callback TYPE. A C callback is a
      # function pointer, so the tag resolves to `:pointer` and is usable anywhere a
      # pointer is -- here, a NULL passed straight back through. Passing a Ruby Proc
      # as a callback argument needs a runtime C-call builder and is still a gap.

      require "ffi"
      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        callback :cmp, [:pointer, :pointer], :int
        attach_function :abs, [:int], :int
        attach_function :my_len, :strlen, [:string], :ulong
      end
      p L.abs(-5)
      p L.my_len("hello")
    RUBY

    _(result).must_answer "5\n5\n"
  end

  it "a constant in a library module resolves through a nested constant path" do
    result = zr(<<~'RUBY')
      # A constant in an FFI-library module referenced through a NESTED constant
      # path (Outer::CMath::MODE) must still resolve parent-qualified by the
      # module's leaf name -- a leaf-keyed plain-constant table would otherwise
      # claim the reference for a same-leaf constant in another module. Ported from
      # spinel's ffi_const to the real ffi gem API: the constant is a plain Ruby
      # constant on the FFI::Library module.
      require "ffi"

      module Verbs
        MODE = "verbose"
      end

      module Outer
        module CMath
          extend FFI::Library
          ffi_lib "m"
          MODE = 7
          attach_function :fabs, [:double], :double
        end
      end

      m = 7
      puts(m == Outer::CMath::MODE ? "int" : "collision")
      puts Verbs::MODE
      puts Outer::CMath::MODE + 1
      puts Outer::CMath.fabs(-1.5)
    RUBY

    _(result).must_answer <<~'OUT'
      int
      verbose
      8
      1.5
    OUT
  end

  it "a declaration inside an eval reaches the library" do
    result = zr(<<~'RUBY')
      # An `FFI::Library` declaration written inside a run-time `eval` attaches
      # for real.
      #
      # zeo resolves the whole FFI surface at compile time -- `extend
      # FFI::Library`, `ffi_lib`, `attach_function` and a `class < FFI::Struct`'s
      # `layout` are directives the whole-program walk consumes into one
      # `FfiCall` tree in `.rodata` -- and a SNIPPET has no such walk. So a
      # snippet's directives stay ordinary calls, and `FFI::Library`'s rows carry
      # the run-time tier: `DynamicLibrary` opens the library, `dlsym` resolves
      # the symbol, and `FFI::Function` (or `VariadicInvoker`) is the callable
      # `attach_function` installs. The engine is the same libffi both tiers end
      # at -- what the run time adds is a DECLARATION built from values rather
      # than baked into `.rodata`.
      #
      # What it used to do instead is why this is written down: the directives
      # were consumed by the snippet's own lowering, attached nothing, and then
      # the `attach_function` call reached a module that had never been
      # extended -- a `NoMethodError` reading as though the name were
      # misspelled. See `an_ffi_declaration_attaches_at_run_time.rb` for the
      # whole surface.

      require "ffi"

      module EvalAttached
      end

      SRC = [
        "module EvalAttached",
        "  extend FFI::Library",
        "  ffi_lib FFI::Library::LIBC",
        "  attach_function :abs, [:int], :int",
        "end",
      ].join("\n")

      begin
        eval(SRC)
        p EvalAttached.abs(-7)
      rescue Exception => e
        puts "#{e.class}: #{e.message.lines.first.strip}"
      end
    RUBY

    _(result).must_answer "7\n"
  end

  it "the declaration spellings a real adapter writes" do
    result = zr(<<~'RUBY')
      # FFI declaration spellings the lowering used to reject as "literal symbol/
      # string required", together in one program:
      #
      #  - an INLINE `callback([...], ret)` in a type position -- the anonymous twin
      #    of the named `callback :tag` declaration;
      #  - the gem's DIRECTION annotations (`Struct.in`/`.out`, `Struct.ptr(:in)`) --
      #    every one a plain pointer on the ABI, the direction only tunes the gem's
      #    own marshaling copies;
      #  - enum member values and inline-array counts read from QUALIFIED constants
      #    (`Limits::FLAG_B`), not just body-local bare names;
      #  - an inline array OF STRUCTS, each element a view over its slot in place.
      require "ffi"

      module Limits
        FLAG_B = 8
        PAIRS = 3
      end

      module C
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :qsort,
                        [:pointer, :size_t, :size_t, callback([:pointer, :pointer], :int)],
                        :void
      end

      arr = FFI::MemoryPointer.new(:int32, 4)
      arr.write_array_of_int32([40, 10, 30, 20])
      C.qsort(arr, 4, 4, proc { |a, b| a.read_int32 <=> b.read_int32 })
      p arr.read_array_of_int32(4)

      # Direction annotations resolve to the same pointer type `.by_ref` does.
      module Timing
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        class TimeVal < FFI::Struct
          layout :tv_sec, :int64,
                 :tv_usec, :int64
        end

        attach_function :gettimeofday, [TimeVal.out, :pointer], :int
        attach_function :memcmp, [TimeVal.in, TimeVal.ptr(:in), :size_t], :int
      end

      tv = Timing::TimeVal.new
      p Timing.gettimeofday(tv, nil)
      p tv[:tv_sec] > 1_700_000_000
      p Timing.memcmp(tv, tv, 16)

      # An enum member's explicit value may be a QUALIFIED constant; the members
      # after it keep auto-incrementing from it.
      module E
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        enum :flags, [:a, 1, :b, Limits::FLAG_B, :c]
        attach_function :flag_abs, :abs, [:flags], :int
      end
      p E.flag_abs(:b)
      p E.flag_abs(:c)

      # An inline array of STRUCTS: elements sit in place, and reading one yields
      # the struct class viewing its slot -- a write through the view writes the
      # parent's memory.
      class Pair < FFI::Struct
        layout :x, :int32, :y, :int32
      end

      class Board < FFI::Struct
        layout :count, :int32,
               :pairs, [Pair, Limits::PAIRS],
               :tail, :int8
      end

      b = Board.new
      p Board.size
      p [Board.offset_of(:pairs), Board.offset_of(:tail)]
      b[:count] = 2
      row = b[:pairs][1]
      row[:x] = 7
      row[:y] = 9
      p [b[:pairs][1][:x], b[:pairs][1][:y]]
      p [b[:pairs][0][:x], b[:pairs][2][:y]]
      p b[:pairs].size
      p b[:pairs].to_a.map { |pr| pr.class }
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 20, 30, 40]
      0
      true
      0
      8
      9
      32
      [4, 28]
      [7, 9]
      [0, 0]
      3
      [Pair, Pair, Pair]
    OUT
  end

  it "declarations reach wider than the scalar keywords" do
    result = zr(<<~'RUBY')
      # Three declaration forms the real `ffi` gem takes and zeo refused.
      require "ffi"

      # 1. C typedefs. The gem resolves ~200 of them from the headers of the machine
      #    it runs on; zeo takes only the ones whose width and signedness are the
      #    same on every target it builds for -- the C99 exact-width names, the
      #    pointer-width names, and the POSIX types that agree. `mode_t`, `dev_t`,
      #    `nlink_t`, `sa_family_t` and friends genuinely differ between macOS and
      #    glibc, and stay a clean rejection instead of a silently wrong layout.
      module Typed
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :abs, [:int32_t], :int32_t
        attach_function :my_strlen, :strlen, [:string], :size_t
        attach_function :getpid, [], :pid_t
        attach_function :getuid, [], :uid_t
      end
      p Typed.abs(-5)
      p Typed.my_strlen("hello")
      p Typed.getpid == Process.pid
      p Typed.getuid == Process.uid

      # The same names work as struct fields, where the width also fixes the offsets.
      class Sized < FFI::Struct
        layout :a, :uint8_t, :b, :int32_t, :c, :uintptr_t
      end
      p [Sized.size, Sized.offset_of(:b), Sized.offset_of(:c)]

      # 2. `attach_function`'s options hash. `blocking: true` releases the GVL for
      #    the call, which is a no-op under zeo's default parallel threads and the
      #    real handoff under ZEO_GVL=1.
      module Blocking
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :labs, [:int64_t], :int64_t, blocking: true
      end
      p Blocking.labs(-9)

      # 3. An enum member's value written as the expression it is. Flag enums are
      #    spelled as shifts and ors far more often than as the numbers they come to.
      #    The folded values are what the marshaling tables are built from, so they
      #    are checked where they are observable: a member symbol passed in as the
      #    enum type, and the same number read back out.
      module Flags
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        enum :mode, [:none, 0, :lazy, (1 << 0), :eager, (1 << 1), :both, (1 << 0) | (1 << 1)]
        attach_function :as_int, :abs, [:mode], :int
        attach_function :as_mode, :abs, [:int], :mode
      end
      p [Flags.as_int(:none), Flags.as_int(:lazy), Flags.as_int(:eager), Flags.as_int(:both)]
      p [Flags.as_mode(0), Flags.as_mode(1), Flags.as_mode(2), Flags.as_mode(3)]

      # An enum-typed field in a struct declared by the SAME library carries the
      # folded values into the layout too.
      module Flags
        class Holder < FFI::Struct
          layout :m, :mode, :n, :int32
        end
      end
      h = Flags::Holder.new
      h[:m] = :eager
      p [h[:m], Flags::Holder.size, Flags::Holder.offset_of(:n)]
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      true
      true
      [16, 4, 8]
      9
      [0, 1, 2, 3]
      [:none, :lazy, :eager, :both]
      [:eager, 8, 4]
    OUT
  end

  it "a directive under a platform guard runs only on that platform" do
    result = zr(<<~'RUBY')
      # An FFI directive under a class-body `if`/`unless` whose predicate is fixed
      # for the build target (`FFI::Platform::ADDRESS_SIZE`, a `RUBY_PLATFORM`
      # regexp, `Gem.win_platform?`) folds at definition time and still reaches the
      # FFI dispatch -- vips declares its `:gtype` typedef exactly this way. The
      # windows-only branches must DROP: their declarations never register, and
      # the module answers `respond_to?` accordingly, both oracle-verified.
      require "ffi"

      module M
        extend FFI::Library
        ffi_lib "m"
        if FFI::Platform::ADDRESS_SIZE == 64
          typedef :uint64, :gtype
        else
          typedef :uint32, :gtype
        end
        unless RUBY_PLATFORM =~ /mswin|mingw|windows/
          attach_function :my_fabs, :fabs, [:double], :double
        end
        if RUBY_PLATFORM =~ /mswin|mingw/
          attach_function :nope, :DoesNotExistAnywhere, [], :void
        end
        if Gem.win_platform?
          attach_function :also_nope, :AlsoAbsent, [], :void
        end
        if RUBY_PLATFORM.include?("darwin") || RUBY_PLATFORM.include?("linux")
          attach_function :my_floor, :floor, [:double], :double
        end

        # The gem scopes a library's `typedef` to that library: a struct must nest
        # INSIDE the module to name `:gtype` (a top-level one raises TypeError).
        class S < FFI::Struct
          layout :g, :gtype
        end
      end

      puts M::S.size
      puts M.my_fabs(-2.5)
      puts M.my_floor(3.75)
      puts M.respond_to?(:nope)
      puts M.respond_to?(:also_nope)
    RUBY

    _(result).must_answer <<~'OUT'
      8
      2.5
      3.0
      false
      false
    OUT
  end

  it "enum members fold the constants of the body they sit in" do
    result = zr(<<~'RUBY')
      # An enum member's VALUE and an inline array's COUNT are compile-time
      # integers to zeo -- they decide marshaling tables and field offsets. Both
      # now fold through one folder that also reads constants the class body
      # already set (`BASE`, `WIDTH * 2`). `FLAGS = enum :flags, [...]` is the
      # gem's NAMED form spelled as an assignment: registered under the tag AND
      # the constant, so both spellings work in later type positions.
      require "ffi"

      module Native
        extend FFI::Library
        BASE = 4
        FLAGS = enum :flags, [:read, (1 << 0), :write, BASE, :append]
        Mode = enum :ro, :rw, :extra

        class Rec < FFI::Struct
          WIDTH = 8
          layout :tag, FLAGS,
                 :mode, Mode,
                 :flg2, :flags,
                 :name, [:uint8, WIDTH * 2]
        end
      end

      r = Native::Rec.new
      r[:tag] = :write
      r[:mode] = 2
      r[:flg2] = :append
      puts Native::Rec.offset_of(:mode)
      puts Native::Rec.offset_of(:name)
      puts Native::Rec.size
      p r[:tag]
      p r[:mode]
      p r[:flg2]
    RUBY

    _(result).must_answer <<~'OUT'
      4
      12
      28
      :write
      :extra
      :append
    OUT
  end

  it "a foreign pointer held in an ivar is not traced as a heap object" do
    result = zr(<<~'RUBY')
      # A foreign pointer (malloc'd C memory) kept alive in an ivar must not be
      # traced by the GC as a heap object. Heavy allocation churns GC cycles that
      # scan the holder; a collector that followed the foreign pointer would crash.
      # Ported from spinel's ffi_buffer to the real ffi gem API: the foreign
      # address comes from libc malloc through attach_function.
      require "ffi"

      module F
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :malloc, [:size_t], :pointer
        attach_function :free,   [:pointer], :void
      end

      class Holder
        def initialize(p)
          @p = p
        end
        def p; @p; end
      end

      holders = []
      n = 0
      while n < 200
        holders.push(Holder.new(F.malloc(64)))
        n += 1
      end

      i = 0
      while i < 200000
        s = "row-" + i.to_s
        i += 1
      end
      puts "ok #{holders.length}"

      holders.each { |h| F.free(h.p) }
    RUBY

    _(result).must_answer "ok 200\n"
  end

  it "a function takes its body as a block" do
    result = zr(<<~'RUBY')
      # The ffi gem takes an `FFI::Function`'s body as a BLOCK as readily as a Proc
      # in the third position -- the two spellings build the same closure. zeo's
      # constructor counted the block as a missing argument.

      require "ffi"
      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        callback :cmp, [:pointer, :pointer], :int
        attach_function :qsort, [:pointer, :size_t, :size_t, :cmp], :void
      end
      fn = FFI::Function.new(:int, [:pointer, :pointer]) { |a, b| a.read_int <=> b.read_int }
      buf = FFI::MemoryPointer.new(:int, 4)
      buf.write_array_of_int([3, 1, 2, 0])
      L.qsort(buf, 4, 4, fn)
      p buf.read_array_of_int(4)

      desc = FFI::Function.new(:int, [:pointer, :pointer], proc { |a, b| b.read_int <=> a.read_int })
      L.qsort(buf, 4, 4, desc)
      p buf.read_array_of_int(4)

      # A callback may answer nothing, and say so.
      sink = FFI::Function.new(:void, [:pointer, :pointer]) { |_a, _b| nil }
      p sink.class
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 2, 3]
      [3, 2, 1, 0]
      FFI::Function
    OUT
  end

  it "require, extend and attach_function are the gem's own spellings" do
    result = zr(<<~'RUBY')
      # The ffi-gem (CRuby `ffi`) compat frontend: require "ffi" is a native
      # no-op, `extend FFI::Library` is declarative, attach_function (plain and
      # the 4-arg rename form) lowers onto ffi_func, and the gem's type
      # spellings (:string, :pointer, :uint, ...) alias the builtin specs.
      require "ffi"

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :abs, [:int], :int
        attach_function :my_len, :strlen, [:string], :ulong
        attach_function :floor, [:double], :double
        callback :cmp, [:pointer, :pointer], :int
      end

      p LibC.abs(-5)
      p LibC.my_len("hello")
      p LibC.floor(3.7)
      p LibC.abs(42)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      3.0
      42
    OUT
  end

  it "a global typedef registers for every library" do
    result = zr(<<~'RUBY')
      # `FFI.typedef :existing, :alias` writes the gem's GLOBAL type registry --
      # visible to every library module and struct layout that runs after it, from
      # whatever plain namespace it was written in (puppet declares the whole Win32
      # vocabulary this way in one file and spends it across the rest).
      require "ffi"

      module Vocabulary
        FFI.typedef :uint16, :word
        FFI.typedef :uintptr_t, :handle
      end

      class S < FFI::Struct
        layout :w, :word, :h, :handle
      end

      module Lib
        extend FFI::Library
        ffi_lib "m"
        attach_function :my_labs, :labs, [:handle], :handle
        attach_function :my_fabs, :fabs, [:double], :double
      end

      puts S.offset_of(:h)
      puts S.size
      puts Lib.my_labs(7)
      puts Lib.my_fabs(-1.5)
    RUBY

    _(result).must_answer <<~'OUT'
      8
      16
      7
      1.5
    OUT
  end

  it "an :int argument coerces a boxed integer rather than passing the box" do
    result = zr(<<~'RUBY')
      # An FFI numeric arg (:int) call site receiving a poly-typed value (an ivar
      # widened by a mixed-type initializer) must coerce the boxed integer rather
      # than passing the box itself. Ported from spinel's ffi_func (#626) to the
      # real ffi gem API; the symptom shape -- a within-class poly slot created by
      # a mixed-type initializer -- is preserved.
      require "ffi"

      class Sink
        attr_accessor :n
        def initialize(flag)
          @n = flag ? 42 : "fallback"
        end
      end

      module Lib
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :abs, [:int], :int
      end

      s = Sink.new(true)
      puts Lib.abs(s.n)
    RUBY

    _(result).must_answer "42\n"
  end

  it "a return at either end of every integer type comes back whole" do
    result = zr(<<~'RUBY')
      # Every FFI integer type accepts its whole C range in both directions: a
      # :ulong/:uint64/:size_t argument or return reaches 2**64-1 (a Bignum), a
      # :long/:int64 reaches -2**63, and a value outside the C type raises the
      # gem's own RangeError -- which names the converter (:long is not :int64).
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strtoull, [:string, :pointer, :int], :ulong
        attach_function :strtoll, [:string, :pointer, :int], :long
        attach_function :strnlen_ulong, :strnlen, [:string, :ulong], :ulong
        attach_function :strnlen_u64, :strnlen, [:string, :uint64], :uint64
        attach_function :strnlen_size_t, :strnlen, [:string, :size_t], :size_t
        attach_function :strnlen_long, :strnlen, [:string, :long], :long
        attach_function :strnlen_i64, :strnlen, [:string, :int64], :int64
        attach_function :strnlen_u32, :strnlen, [:string, :uint32], :uint32
        attach_function :strnlen_i8, :strnlen, [:string, :int8], :int8
        attach_function :llabs, [:long_long], :long_long
        attach_function :labs, [:long], :long
        attach_function :abs, [:int], :int
        attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
      end

      # Every FFI integer type accepts its whole C range in both directions: a
      # :ulong/:uint64/:size_t argument or return reaches 2**64-1 (a Bignum), a
      # :long/:int64 reaches -2**63, and a value outside the C type raises the
      # gem's own RangeError -- which names the converter (:long is not :int64).
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strtoull, [:string, :pointer, :int], :ulong
        attach_function :strtoll, [:string, :pointer, :int], :long
        attach_function :strnlen_ulong, :strnlen, [:string, :ulong], :ulong
        attach_function :strnlen_u64, :strnlen, [:string, :uint64], :uint64
        attach_function :strnlen_size_t, :strnlen, [:string, :size_t], :size_t
        attach_function :strnlen_long, :strnlen, [:string, :long], :long
        attach_function :strnlen_i64, :strnlen, [:string, :int64], :int64
        attach_function :strnlen_u32, :strnlen, [:string, :uint32], :uint32
        attach_function :strnlen_i8, :strnlen, [:string, :int8], :int8
        attach_function :llabs, [:long_long], :long_long
        attach_function :labs, [:long], :long
        attach_function :abs, [:int], :int
        attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
      end

      # Returns above i64::MAX and at i64::MIN.
      p L.strtoull("18446744073709551615", nil, 10)
      p L.strtoll("-9223372036854775808", nil, 10)

    RUBY

    _(result).must_answer <<~'OUT'
      18446744073709551615
      -9223372036854775808
    OUT
  end

  it "an argument at either end of every 64-bit spelling passes whole" do
    result = zr(<<~'RUBY')
      # Every FFI integer type accepts its whole C range in both directions: a
      # :ulong/:uint64/:size_t argument or return reaches 2**64-1 (a Bignum), a
      # :long/:int64 reaches -2**63, and a value outside the C type raises the
      # gem's own RangeError -- which names the converter (:long is not :int64).
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strtoull, [:string, :pointer, :int], :ulong
        attach_function :strtoll, [:string, :pointer, :int], :long
        attach_function :strnlen_ulong, :strnlen, [:string, :ulong], :ulong
        attach_function :strnlen_u64, :strnlen, [:string, :uint64], :uint64
        attach_function :strnlen_size_t, :strnlen, [:string, :size_t], :size_t
        attach_function :strnlen_long, :strnlen, [:string, :long], :long
        attach_function :strnlen_i64, :strnlen, [:string, :int64], :int64
        attach_function :strnlen_u32, :strnlen, [:string, :uint32], :uint32
        attach_function :strnlen_i8, :strnlen, [:string, :int8], :int8
        attach_function :llabs, [:long_long], :long_long
        attach_function :labs, [:long], :long
        attach_function :abs, [:int], :int
        attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
      end

      # Returns above i64::MAX and at i64::MIN.

      # Arguments at both ends of every 64-bit spelling; a negative wraps for an
      # unsigned type, exactly as NUM2ULONG does.
      p L.strnlen_ulong("abc", 2**64 - 1)
      p L.strnlen_u64("abc", 2**64 - 1)
      p L.strnlen_size_t("abc", 2**64 - 1)
      p L.strnlen_ulong("abc", -1)
      p L.strnlen_long("abc", 2**63 - 1)
      p L.strnlen_i64("abc", 2**63 - 1)
      p L.llabs(-2**63 + 1)
      p L.labs(-2**63 + 1)
      p L.strnlen_u32("abc", 2**32 - 1)
      p L.strnlen_u32("abc", -1)
      p L.strnlen_i8("abc", 2.9)

    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      3
      3
      3
      3
      9223372036854775807
      9223372036854775807
      3
      3
      2
    OUT
  end

  it "a variadic argument promotes and keeps its own converter" do
    result = zr(<<~'RUBY')
      # Every FFI integer type accepts its whole C range in both directions: a
      # :ulong/:uint64/:size_t argument or return reaches 2**64-1 (a Bignum), a
      # :long/:int64 reaches -2**63, and a value outside the C type raises the
      # gem's own RangeError -- which names the converter (:long is not :int64).
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strtoull, [:string, :pointer, :int], :ulong
        attach_function :strtoll, [:string, :pointer, :int], :long
        attach_function :strnlen_ulong, :strnlen, [:string, :ulong], :ulong
        attach_function :strnlen_u64, :strnlen, [:string, :uint64], :uint64
        attach_function :strnlen_size_t, :strnlen, [:string, :size_t], :size_t
        attach_function :strnlen_long, :strnlen, [:string, :long], :long
        attach_function :strnlen_i64, :strnlen, [:string, :int64], :int64
        attach_function :strnlen_u32, :strnlen, [:string, :uint32], :uint32
        attach_function :strnlen_i8, :strnlen, [:string, :int8], :int8
        attach_function :llabs, [:long_long], :long_long
        attach_function :labs, [:long], :long
        attach_function :abs, [:int], :int
        attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
      end

      # Returns above i64::MAX and at i64::MIN.

      # Arguments at both ends of every 64-bit spelling; a negative wraps for an
      # unsigned type, exactly as NUM2ULONG does.

      # Variadic arguments promote but keep their own converter.
      buf = FFI::MemoryPointer.new(:char, 128)
      L.snprintf(buf, 128, "%llu %lld %u %d", :ulong, 2**64 - 1, :long, -2**63, :uint32, 2**32 - 1, :int32, -2**31)
      puts buf.read_string
      L.snprintf(buf, 128, "%llu %u %d", :uint64, 2**64 - 1, :uint8, -1, :int8, 200)
      puts buf.read_string

    RUBY

    _(result).must_answer <<~'OUT'
      18446744073709551615 -9223372036854775808 4294967295 -2147483648
      18446744073709551615 4294967295 200
    OUT
  end

  it "a pointer round-trips the full unsigned range" do
    result = zr(<<~'RUBY')
      # Every FFI integer type accepts its whole C range in both directions: a
      # :ulong/:uint64/:size_t argument or return reaches 2**64-1 (a Bignum), a
      # :long/:int64 reaches -2**63, and a value outside the C type raises the
      # gem's own RangeError -- which names the converter (:long is not :int64).
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strtoull, [:string, :pointer, :int], :ulong
        attach_function :strtoll, [:string, :pointer, :int], :long
        attach_function :strnlen_ulong, :strnlen, [:string, :ulong], :ulong
        attach_function :strnlen_u64, :strnlen, [:string, :uint64], :uint64
        attach_function :strnlen_size_t, :strnlen, [:string, :size_t], :size_t
        attach_function :strnlen_long, :strnlen, [:string, :long], :long
        attach_function :strnlen_i64, :strnlen, [:string, :int64], :int64
        attach_function :strnlen_u32, :strnlen, [:string, :uint32], :uint32
        attach_function :strnlen_i8, :strnlen, [:string, :int8], :int8
        attach_function :llabs, [:long_long], :long_long
        attach_function :labs, [:long], :long
        attach_function :abs, [:int], :int
        attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
      end

      # Returns above i64::MAX and at i64::MIN.

      # Arguments at both ends of every 64-bit spelling; a negative wraps for an
      # unsigned type, exactly as NUM2ULONG does.

      # Variadic arguments promote but keep their own converter.
      buf = FFI::MemoryPointer.new(:char, 128)
      L.snprintf(buf, 128, "%llu %lld %u %d", :ulong, 2**64 - 1, :long, -2**63, :uint32, 2**32 - 1, :int32, -2**31)
      L.snprintf(buf, 128, "%llu %u %d", :uint64, 2**64 - 1, :uint8, -1, :int8, 200)

      # A pointer round-trips the full unsigned range.
      mp = FFI::MemoryPointer.new(:uint64, 3)
      mp.put_uint64(0, 2**64 - 1)
      p mp.read_uint64
      mp.write_ulong(2**64 - 1)
      p mp.read_ulong
      mp.put_array_of_uint64(0, [2**64 - 1, 1, 2**63])
      p mp.read_array_of_ulong(3)

    RUBY

    _(result).must_answer <<~'OUT'
      18446744073709551615
      18446744073709551615
      [18446744073709551615, 1, 9223372036854775808]
    OUT
  end

  it "a callback takes and answers the full range" do
    result = zr(<<~'RUBY')
      # Every FFI integer type accepts its whole C range in both directions: a
      # :ulong/:uint64/:size_t argument or return reaches 2**64-1 (a Bignum), a
      # :long/:int64 reaches -2**63, and a value outside the C type raises the
      # gem's own RangeError -- which names the converter (:long is not :int64).
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strtoull, [:string, :pointer, :int], :ulong
        attach_function :strtoll, [:string, :pointer, :int], :long
        attach_function :strnlen_ulong, :strnlen, [:string, :ulong], :ulong
        attach_function :strnlen_u64, :strnlen, [:string, :uint64], :uint64
        attach_function :strnlen_size_t, :strnlen, [:string, :size_t], :size_t
        attach_function :strnlen_long, :strnlen, [:string, :long], :long
        attach_function :strnlen_i64, :strnlen, [:string, :int64], :int64
        attach_function :strnlen_u32, :strnlen, [:string, :uint32], :uint32
        attach_function :strnlen_i8, :strnlen, [:string, :int8], :int8
        attach_function :llabs, [:long_long], :long_long
        attach_function :labs, [:long], :long
        attach_function :abs, [:int], :int
        attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
      end

      # Returns above i64::MAX and at i64::MIN.

      # Arguments at both ends of every 64-bit spelling; a negative wraps for an
      # unsigned type, exactly as NUM2ULONG does.

      # Variadic arguments promote but keep their own converter.
      buf = FFI::MemoryPointer.new(:char, 128)
      L.snprintf(buf, 128, "%llu %lld %u %d", :ulong, 2**64 - 1, :long, -2**63, :uint32, 2**32 - 1, :int32, -2**31)
      L.snprintf(buf, 128, "%llu %u %d", :uint64, 2**64 - 1, :uint8, -1, :int8, 200)

      # A pointer round-trips the full unsigned range.
      mp = FFI::MemoryPointer.new(:uint64, 3)
      mp.put_uint64(0, 2**64 - 1)
      mp.write_ulong(2**64 - 1)
      mp.put_array_of_uint64(0, [2**64 - 1, 1, 2**63])

      # A callback receives and returns the full range.
      f = FFI::Function.new(:ulong, [:ulong]) { |x| p [:cb, x]; x }
      p f.call(2**64 - 1)
      g = FFI::Function.new(:long, [:long]) { |x| x }
      p g.call(-2**63)
      h = FFI::Function.new(:int, [:int8]) { |x| x }
      p h.call(300)
      p FFI::Function.new(:int, [:int]) { nil }.call(1)

    RUBY

    _(result).must_answer <<~'OUT'
      [:cb, 18446744073709551615]
      18446744073709551615
      -9223372036854775808
      44
      0
    OUT
  end

  it "a struct field goes through the same converters" do
    result = zr(<<~'RUBY')
      # Every FFI integer type accepts its whole C range in both directions: a
      # :ulong/:uint64/:size_t argument or return reaches 2**64-1 (a Bignum), a
      # :long/:int64 reaches -2**63, and a value outside the C type raises the
      # gem's own RangeError -- which names the converter (:long is not :int64).
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strtoull, [:string, :pointer, :int], :ulong
        attach_function :strtoll, [:string, :pointer, :int], :long
        attach_function :strnlen_ulong, :strnlen, [:string, :ulong], :ulong
        attach_function :strnlen_u64, :strnlen, [:string, :uint64], :uint64
        attach_function :strnlen_size_t, :strnlen, [:string, :size_t], :size_t
        attach_function :strnlen_long, :strnlen, [:string, :long], :long
        attach_function :strnlen_i64, :strnlen, [:string, :int64], :int64
        attach_function :strnlen_u32, :strnlen, [:string, :uint32], :uint32
        attach_function :strnlen_i8, :strnlen, [:string, :int8], :int8
        attach_function :llabs, [:long_long], :long_long
        attach_function :labs, [:long], :long
        attach_function :abs, [:int], :int
        attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
      end

      # Returns above i64::MAX and at i64::MIN.

      # Arguments at both ends of every 64-bit spelling; a negative wraps for an
      # unsigned type, exactly as NUM2ULONG does.

      # Variadic arguments promote but keep their own converter.
      buf = FFI::MemoryPointer.new(:char, 128)
      L.snprintf(buf, 128, "%llu %lld %u %d", :ulong, 2**64 - 1, :long, -2**63, :uint32, 2**32 - 1, :int32, -2**31)
      L.snprintf(buf, 128, "%llu %u %d", :uint64, 2**64 - 1, :uint8, -1, :int8, 200)

      # A pointer round-trips the full unsigned range.
      mp = FFI::MemoryPointer.new(:uint64, 3)
      mp.put_uint64(0, 2**64 - 1)
      mp.write_ulong(2**64 - 1)
      mp.put_array_of_uint64(0, [2**64 - 1, 1, 2**63])

      # A callback receives and returns the full range.
      f = FFI::Function.new(:ulong, [:ulong]) { |x| p [:cb, x]; x }
      g = FFI::Function.new(:long, [:long]) { |x| x }
      h = FFI::Function.new(:int, [:int8]) { |x| x }

      # A struct field goes through the same converters.
      class S < FFI::Struct
        layout :a, :ulong, :b, :long, :c, :uint64
      end
      s = S.new
      s[:a] = 2**64 - 1
      s[:b] = -2**63
      s[:c] = 2**64 - 1
      p [s[:a], s[:b], s[:c]]
      p S.layout.fields.map { |fld| fld.type }

    RUBY

    _(result).must_answer <<~'OUT'
      [18446744073709551615, -9223372036854775808, 18446744073709551615]
      [#<FFI::Type::Builtin::ULONG size=8 alignment=8>, #<FFI::Type::Builtin::LONG size=8 alignment=8>, #<FFI::Type::Builtin::UINT64 size=8 alignment=8>]
    OUT
  end

  it "a value out of range raises RangeError in the gem's own wording" do
    result = zr(<<~'RUBY')
      # Every FFI integer type accepts its whole C range in both directions: a
      # :ulong/:uint64/:size_t argument or return reaches 2**64-1 (a Bignum), a
      # :long/:int64 reaches -2**63, and a value outside the C type raises the
      # gem's own RangeError -- which names the converter (:long is not :int64).
      require "ffi"

      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strtoull, [:string, :pointer, :int], :ulong
        attach_function :strtoll, [:string, :pointer, :int], :long
        attach_function :strnlen_ulong, :strnlen, [:string, :ulong], :ulong
        attach_function :strnlen_u64, :strnlen, [:string, :uint64], :uint64
        attach_function :strnlen_size_t, :strnlen, [:string, :size_t], :size_t
        attach_function :strnlen_long, :strnlen, [:string, :long], :long
        attach_function :strnlen_i64, :strnlen, [:string, :int64], :int64
        attach_function :strnlen_u32, :strnlen, [:string, :uint32], :uint32
        attach_function :strnlen_i8, :strnlen, [:string, :int8], :int8
        attach_function :llabs, [:long_long], :long_long
        attach_function :labs, [:long], :long
        attach_function :abs, [:int], :int
        attach_function :snprintf, [:pointer, :size_t, :string, :varargs], :int
      end

      # Returns above i64::MAX and at i64::MIN.

      # Arguments at both ends of every 64-bit spelling; a negative wraps for an
      # unsigned type, exactly as NUM2ULONG does.

      # Variadic arguments promote but keep their own converter.
      buf = FFI::MemoryPointer.new(:char, 128)
      L.snprintf(buf, 128, "%llu %lld %u %d", :ulong, 2**64 - 1, :long, -2**63, :uint32, 2**32 - 1, :int32, -2**31)
      L.snprintf(buf, 128, "%llu %u %d", :uint64, 2**64 - 1, :uint8, -1, :int8, 200)

      # A pointer round-trips the full unsigned range.
      mp = FFI::MemoryPointer.new(:uint64, 3)
      mp.put_uint64(0, 2**64 - 1)
      mp.write_ulong(2**64 - 1)
      mp.put_array_of_uint64(0, [2**64 - 1, 1, 2**63])

      # A callback receives and returns the full range.
      f = FFI::Function.new(:ulong, [:ulong]) { |x| p [:cb, x]; x }
      g = FFI::Function.new(:long, [:long]) { |x| x }
      h = FFI::Function.new(:int, [:int8]) { |x| x }

      # A struct field goes through the same converters.
      class S < FFI::Struct
        layout :a, :ulong, :b, :long, :c, :uint64
      end
      s = S.new
      s[:a] = 2**64 - 1
      s[:b] = -2**63
      s[:c] = 2**64 - 1

      def attempt
        yield
        puts "no error"
      rescue RangeError, TypeError => e
        puts "#{e.class}: #{e.message}"
      end

      def attempt
        yield
        puts "no error"
      rescue RangeError, TypeError => e
        puts "#{e.class}: #{e.message}"
      end

      # Out of range, and the wrong kind of value: the gem's exact wording.
      attempt { L.strnlen_ulong("abc", 2**64) }
      attempt { L.strnlen_ulong("abc", -2**63 - 1) }
      attempt { L.strnlen_ulong("abc", -2**64) }
      attempt { L.strnlen_size_t("abc", 2**64) }
      attempt { L.strnlen_u64("abc", 2**64) }
      attempt { L.strnlen_u64("abc", -2**63 - 1) }
      attempt { L.strnlen_long("abc", 2**63) }
      attempt { L.strnlen_long("abc", -2**63 - 1) }
      attempt { L.strnlen_i64("abc", 2**63) }
      attempt { L.abs(2**31) }
      attempt { L.abs(-2**31 - 1) }
      attempt { L.abs(2**64) }
      attempt { L.strnlen_u32("abc", 2**32) }
      attempt { L.strnlen_u32("abc", -2**31 - 1) }
      attempt { L.strnlen_u32("abc", 2**63) }
      attempt { L.strnlen_i8("abc", 2**31) }
      attempt { L.strnlen_ulong("abc", 2.0**64) }
      attempt { L.strnlen_u64("abc", 2.0**64) }
      attempt { L.strnlen_long("abc", 2.0**63) }
      attempt { L.strnlen_i64("abc", Float::NAN) }
      attempt { L.strnlen_ulong("abc", nil) }
      attempt { L.strnlen_long("abc", nil) }
      attempt { L.strnlen_i64("abc", nil) }
      attempt { L.strnlen_i64("abc", true) }
      attempt { L.strnlen_i64("abc", "1") }
      attempt { L.abs("1") }
      attempt { L.snprintf(buf, 128, "%llu", :ulong, 2**64) }
      attempt { L.snprintf(buf, 128, "%u", :uint8, 2**32) }
      attempt { mp.put_ulong(0, 2**64) }
      attempt { mp.put_uint64(0, 2**64) }
      attempt { mp.write_long(2**63) }
      attempt { mp.write_int64(2**63) }
      attempt { mp.write_array_of_ulong([2**64]) }
      attempt { mp.write_uint(2**32) }
      attempt { s[:a] = 2**64 }
      attempt { s[:b] = 2**63 }
      attempt { s[:c] = -2**63 - 1 }
      attempt { f.call(2**64) }
      attempt { FFI::Function.new(:ulong, [:ulong]) { 2**64 }.call(1) }
      attempt { FFI::Function.new(:uint8, [:int]) { 2**32 }.call(1) }
    RUBY

    _(result).must_answer <<~'OUT'
      RangeError: bignum too big to convert into 'unsigned long'
      RangeError: bignum out of range of unsigned long
      RangeError: bignum too big to convert into 'unsigned long'
      RangeError: bignum too big to convert into 'unsigned long'
      RangeError: bignum too big to convert into 'unsigned long long'
      RangeError: bignum out of range of unsigned long long
      RangeError: bignum too big to convert into 'long'
      RangeError: bignum too big to convert into 'long'
      RangeError: bignum too big to convert into 'long long'
      RangeError: integer 2147483648 too big to convert to 'int'
      RangeError: integer -2147483649 too small to convert to 'int'
      RangeError: bignum too big to convert into 'long'
      RangeError: integer 4294967296 too big to convert to 'unsigned int'
      RangeError: integer -2147483649 too small to convert to 'unsigned int'
      RangeError: integer 9223372036854775808 too big to convert to 'unsigned int'
      RangeError: integer 2147483648 too big to convert to 'int'
      RangeError: float 1.844674407e+19 out of range of integer
      RangeError: float 1.844674407e+19 out of range of unsigned long long
      RangeError: float 9.223372037e+18 out of range of integer
      RangeError: float NaN out of range of long long
      TypeError: no implicit conversion of nil into Integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil
      TypeError: no implicit conversion from boolean
      TypeError: no implicit conversion from string
      TypeError: no implicit conversion of String into Integer
      RangeError: bignum too big to convert into 'unsigned long'
      RangeError: integer 4294967296 too big to convert to 'unsigned int'
      RangeError: bignum too big to convert into 'unsigned long'
      RangeError: bignum too big to convert into 'unsigned long long'
      RangeError: bignum too big to convert into 'long'
      RangeError: bignum too big to convert into 'long long'
      RangeError: bignum too big to convert into 'unsigned long'
      RangeError: integer 4294967296 too big to convert to 'unsigned int'
      RangeError: bignum too big to convert into 'unsigned long'
      RangeError: bignum too big to convert into 'long'
      RangeError: bignum out of range of unsigned long long
      RangeError: bignum too big to convert into 'unsigned long'
      RangeError: bignum too big to convert into 'unsigned long'
      RangeError: integer 4294967296 too big to convert to 'unsigned int'
    OUT
  end

  it "a layout installed by an included module" do
    result = zr(<<~'RUBY')
      # A module whose `self.included(base)` hook `class_eval`s a `layout` into
      # whoever includes it. gssapi writes every one of its buffer structs this way:
      # `GssBufferDescLayout` carries the two fields AND the two readers, and the
      # structs themselves have empty bodies apart from the `include`.
      #
      # zeo saw a struct class with no layout, so embedding one inline in another
      # struct reported "its `layout` directive never lowered".
      #
      # The hook's block SOURCE is recorded when the module lowers (a prism node is
      # neither `Clone` nor storable past its parse) and re-parsed at the include
      # site, where its statements take the ordinary struct-body path -- so the
      # layout synthesizes accessors and records offsets exactly as a written one
      # does, and the `def`s beside it come along.
      require "ffi"

      module GSSAPI
        module LibGSSAPI
          extend FFI::Library
          ffi_lib FFI::Library::LIBC

          module BufferLayout
            def self.included(base)
              base.class_eval do
                layout :length, :uint32, :value, :pointer

                def len2 = self[:length] * 2
              end
            end
          end

          # The wrapper the real structs descend from -- the shape that made
          # `UnManagedGssBufferDesc` invisible as a struct in the first place.
          class GssUMStruct < FFI::Struct
            def tag = "um"
          end

          class UnManagedGssBufferDesc < GssUMStruct
            include BufferLayout
          end

          # Embedded BY VALUE, which is what needs the layout rather than just the
          # name.
          class GssIOVBufferDesc < FFI::Struct
            layout :type, :uint32, :buffer, UnManagedGssBufferDesc
          end
        end
      end

      b = GSSAPI::LibGSSAPI::UnManagedGssBufferDesc.new
      b[:length] = 5
      p b.len2
      p b.tag
      p GSSAPI::LibGSSAPI::UnManagedGssBufferDesc.size
      p GSSAPI::LibGSSAPI::GssIOVBufferDesc.size
      p GSSAPI::LibGSSAPI::GssIOVBufferDesc.offset_of(:buffer)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      "um"
      16
      24
      8
    OUT
  end

  it "a layout reads the constants of the body it sits in" do
    result = zr(<<~'RUBY')
      # A layout can spell its types and counts as CONSTANTS of the ENCLOSING
      # module -- ffi-ncurses declares its whole vocabulary that way above the
      # structs that use it. Both halves of an inline array fold too.
      require "ffi"

      module WinStruct
        NCURSES_ATTR_T = :int
        WCHAR_T        = :ushort
        CCHARW_MAX     = 5

        class CCharT < FFI::Struct
          layout :attr, NCURSES_ATTR_T,
                 :chars, [WCHAR_T, CCHARW_MAX]
        end
      end

      puts WinStruct::CCharT.offset_of(:chars)
      puts WinStruct::CCharT.size
      c = WinStruct::CCharT.new
      c[:attr] = 7
      c[:chars][0] = 65
      c[:chars][4] = 90
      puts c[:attr]
      puts c[:chars][0]
      puts c[:chars][4]
    RUBY

    _(result).must_answer <<~'OUT'
      4
      16
      7
      65
      90
    OUT
  end

  it "ffi_lib names a candidate it can decide" do
    result = zr(<<~'RUBY')
      # An ARRAY argument to `ffi_lib` is a list of ALTERNATIVE spellings of ONE
      # library, and ruby loads the first that dlopens. (Separate arguments are
      # separate libraries, all required -- a different thing.) zeo has to name one
      # library at compile time, so it takes the first alternative it can DECIDE.
      #
      # It used to accept only a bare string or `FFI::Library::LIBC`, which refused
      # every gem that writes an alternatives list, a symbol, or the `ffi` gem's own
      # `FFI.library_name` helper -- 317 corpus rows, the largest single lowering
      # diagnostic left after the singleton clusters.
      require "ffi"

      # A candidate LIST. The bare name comes first and the versioned sonames after
      # it, which is why first-decidable is the right pick: rbnacl writes
      # `["sodium", "libsodium.so.18", "libsodium.so.23", "libsodium.so.26"]`.
      module ListForm
        extend FFI::Library
        ffi_lib ["m", "libm.so.6"]
        attach_function :pow, [:double, :double], :double
      end
      puts ListForm.pow(2.0, 10.0)

      # A candidate zeo cannot decide is SKIPPED, not refused -- libusb leads with two
      # locals holding bundled paths and only then names the system library.
      module SkipsTheUndecidable
        extend FFI::Library
        bundled = "/nonexistent/libm.dylib"
        ffi_lib [bundled, "m"]
        attach_function :ceil, [:double], :double
      end
      puts SkipsTheUndecidable.ceil(1.2)

      # A symbol names a library too -- windows gems write `ffi_lib :kernel32`.
      module SymbolForm
        extend FFI::Library
        ffi_lib :m
        attach_function :sqrt, [:double], :double
      end
      puts SymbolForm.sqrt(144.0)

      # `FFI::Platform::LIBC` is `FFI::Library::LIBC` by its other path, and either
      # may be written `::`-anchored.
      module LibcOtherPath
        extend FFI::Library
        ffi_lib ::FFI::Platform::LIBC
        attach_function :abs, [:int], :int
      end
      puts LibcOtherPath.abs(-11)
    RUBY

    _(result).must_answer <<~'OUT'
      1024.0
      2.0
      12.0
      11
    OUT
  end

  it "scalar doubles, a string measured by strlen, and a no-argument int return" do
    result = zr(<<~'RUBY')
      # Basic libc + libm bindings through the real ffi gem API (ported from
      # spinel's ffi_func): scalar doubles in/out, a string argument measured by
      # strlen, and a no-arg int return.
      require "ffi"

      module LibM
        extend FFI::Library
        ffi_lib "m"
        attach_function :cos,  [:double], :double
        attach_function :sqrt, [:double], :double
        attach_function :pow,  [:double, :double], :double
      end

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :strlen, [:string], :size_t
        attach_function :getpid, [],        :int
      end

      puts LibM.cos(0.0).to_i
      puts LibM.sqrt(16.0).to_i
      puts LibM.pow(2.0, 10.0).to_i
      puts LibC.strlen("hello, world")
      puts(LibC.getpid > 0 ? "pid_ok" : "pid_bad")
    RUBY

    _(result).must_answer <<~'OUT'
      1
      4
      1024
      12
      pid_ok
    OUT
  end

  it "a library is marked before the module is reopened" do
    result = zr(<<~'RUBY', files: beside("ffi_library/curl.rb", "ffi_library/vocabulary.rb"))
      # A class-body `require` pre-LOWERS ahead of the requiring file's own
      # statements, so a required file's declarations exist before the statements
      # below the require -- libuv's `require 'libuv/ext/types'`, three lines above
      # the `attach_function`s that spend its enums.
      #
      # The dependency runs both ways. ethon writes `extend ::FFI::Library` in
      # `curl.rb` and then requires `curls/constants.rb`, which REOPENS that module
      # thirteen lines lower to declare its enums. Lowering the required file first
      # left the reopen looking like a plain namespace, so no directive in it was
      # recognized at all and every signature naming one was an unsupported type.
      #
      # What each body IS -- an FFI library, a struct class -- is now read off the
      # requiring file's own syntax before anything it requires lowers. Only the
      # marks: what a body DECLARES needs the alias tables that real lowering has.
      require_relative "ffi_library/curl"

      p Curl.pick(:failed)
      p Curl.pick(:ok)
      p Curl.widen(-7)

      # The requiring file's OWN declarations reach the file it requires, which is
      # the direction fast_excel needs: it declares `enum :error` at binding.rb:318
      # and `class RepeatRows < FFI::Struct` at 1217, both above the requires at
      # 714 and 1461, and every sub-file passes them by value.
      s = Curl::Stamp.new
      s[:sec] = -12
      p Curl.measure(s)
      p Curl::Frame.size
    RUBY

    _(result).must_answer <<~'OUT'
      :failed
      :ok
      7
      12
      16
    OUT
  end

  it "FFI::Platform reports the host's C ABI" do
    skip "runs only on macos" unless ["macos"].include?(Zr::Spec.platform)

    result = zr(<<~'RUBY')

      # `FFI::Platform` answers the host's platform and C-ABI facts as CONSTANTS,
      # not only as the four predicates zeo used to carry. A gem reads them
      # directly -- crabstone picks `:size_t`'s width with
      # `FFI::Platform::ADDRESS_SIZE == 32`, and smartcard its entry-point suffix
      # from `FFI::Platform.windows?` -- so an absent constant is a NameError at
      # the gem's first line.
      #
      # The values a compile-time guard folds and the values the program prints
      # have to be the same numbers, which is the last group here.
      #
      # OSVERSION and CONF_DIR are deliberately absent: both carry the version of
      # the OS the interpreter was BUILT on, so they differ between any two hosts.
      require "ffi"

      p FFI::VERSION

      p FFI::Platform.constants.sort

      sizes = %i[
        ADDRESS_SIZE ADDRESS_ALIGN LONG_SIZE LONG_ALIGN
        INT8_SIZE INT8_ALIGN INT16_SIZE INT16_ALIGN
        INT32_SIZE INT32_ALIGN INT64_SIZE INT64_ALIGN
        FLOAT_SIZE FLOAT_ALIGN DOUBLE_SIZE DOUBLE_ALIGN
        LITTLE_ENDIAN BIG_ENDIAN BYTE_ORDER
      ]
      p sizes.map { |c| FFI::Platform.const_get(c) }

      p [FFI::Platform::OS, FFI::Platform::ARCH, FFI::Platform::NAME]
      p [FFI::Platform::LIBPREFIX, FFI::Platform::LIBSUFFIX, FFI::Platform::LIBC]
      p FFI::Library::LIBC == FFI::Platform::LIBC

      # One IS_ flag per OS, and the predicate that reads it. macOS counts as a
      # BSD, so `bsd?` and `mac?` are true together.
      p FFI::Platform.constants.grep(/^IS_/).sort.map { |c| [c, FFI::Platform.const_get(c)] }
      p [
        FFI::Platform.mac? == FFI::Platform::IS_MAC,
        FFI::Platform.windows? == FFI::Platform::IS_WINDOWS,
        FFI::Platform.solaris? == FFI::Platform::IS_SOLARIS,
        FFI::Platform.bsd? == FFI::Platform::IS_BSD,
        FFI::Platform.unix? == !FFI::Platform::IS_WINDOWS,
      ]
      p FFI::Platform.is_os(FFI::Platform::OS)

      # The exception hierarchy is load-bearing: `rescue LoadError` around a
      # `require` is what catches a missing library or a missing symbol.
      p [
        FFI::NullPointerError.superclass,
        FFI::NotFoundError.superclass,
        FFI::PlatformError.superclass,
      ]
      p defined?(FFI::Error)

      # Library name mapping. A bare name gains the platform's prefix and suffix,
      # a name that already carries one keeps it, a path passes straight through,
      # and `c` is the standard C library rather than a file called `libc`.
      p %w[jpeg z libz.dylib /usr/lib/libz.dylib c].map { |n| FFI.map_library_name(n) }
      p FFI::LibraryPath.new("vips", abi_number: 42).to_s
      p FFI::LibraryPath.new("vips", root: "/opt/lib").to_s
      begin
        FFI.map_library_name(:crypto)
      rescue TypeError => e
        p [e.class, e.message]
      end

      p [FFI.type_size(:int), FFI.type_size(:pointer), FFI.type_size(:double)]
      p FFI.find_type(:ulong).equal?(FFI::Type::Builtin::ULONG)
      begin
        FFI.find_type(:nope)
      rescue TypeError => e
        p [e.class, e.message]
      end

      p FFI::CURRENT_PROCESS.equal?(FFI::USE_THIS_PROCESS_AS_LIBRARY)
      p FFI.make_shareable([1, 2]).frozen?

      # A guard the compiler folds and the constant the program reads answer the
      # same question -- so a `typedef` chosen at compile time cannot contradict
      # what the running program says the width is.
      size_t = FFI::Platform::ADDRESS_SIZE == 32 ? :ulong : :ulong_long
      p [size_t, FFI::Platform::ADDRESS_SIZE == 64, FFI::Platform::ARCH == "aarch64"]
    RUBY

    _(result).must_answer <<~'OUT'
      "1.17.4"
      [:ADDRESS_ALIGN, :ADDRESS_SIZE, :ARCH, :BIG_ENDIAN, :BYTE_ORDER, :CONF_DIR, :CPU, :DOUBLE_ALIGN, :DOUBLE_SIZE, :FLOAT_ALIGN, :FLOAT_SIZE, :INT16_ALIGN, :INT16_SIZE, :INT32_ALIGN, :INT32_SIZE, :INT64_ALIGN, :INT64_SIZE, :INT8_ALIGN, :INT8_SIZE, :IS_BSD, :IS_DRAGONFLYBSD, :IS_FREEBSD, :IS_GNU, :IS_LINUX, :IS_MAC, :IS_NETBSD, :IS_OPENBSD, :IS_SOLARIS, :IS_WINDOWS, :LIBC, :LIBPREFIX, :LIBSUFFIX, :LITTLE_ENDIAN, :LONG_ALIGN, :LONG_DOUBLE_ALIGN, :LONG_DOUBLE_SIZE, :LONG_SIZE, :NAME, :OS, :OSVERSION]
      [64, 64, 64, 64, 8, 8, 16, 16, 32, 32, 64, 64, 32, 32, 64, 64, 1234, 4321, 1234]
      ["darwin", "aarch64", "aarch64-darwin"]
      ["lib", "dylib", "libc.dylib"]
      true
      [[:IS_BSD, true], [:IS_DRAGONFLYBSD, false], [:IS_FREEBSD, false], [:IS_GNU, nil], [:IS_LINUX, false], [:IS_MAC, true], [:IS_NETBSD, false], [:IS_OPENBSD, false], [:IS_SOLARIS, false], [:IS_WINDOWS, false]]
      [true, true, true, true, true]
      true
      [RuntimeError, LoadError, LoadError]
      nil
      ["libjpeg.dylib", "libz.dylib", "libz.dylib", "/usr/lib/libz.dylib", "libc.dylib"]
      "libvips.42.dylib"
      "/opt/lib/libvips.dylib"
      [TypeError, "no implicit conversion of Symbol into String"]
      [4, 8, 8]
      true
      [TypeError, "unable to resolve type 'nope'"]
      true
      true
      [:ulong_long, true, true]
    OUT
  end

  it "an int array whose type collapsed still marshals its elements" do
    result = zr(<<~'RUBY')
      # An int array whose static type poly-collapsed (a param union widened it)
      # must still marshal its element data at an FFI array boundary, and a poly
      # value holding a non-array must raise instead of marshalling NULL. Ported
      # from spinel's :int_array spec to the real ffi gem API: the array's elements
      # land in an FFI::MemoryPointer via write_array_of_int64, and the observer is
      # read_string over the marshalled bytes -- int64 65 is "A\0..." little-endian,
      # so a correct marshal reads back "A".
      require "ffi"

      def widen(a)
        a
      end

      widen(["x", "y"])              # the trigger: widen's param/return go poly

      buf = FFI::MemoryPointer.new(:int64, 2)
      buf.write_array_of_int64(widen([65, 66]))
      p buf.read_string

      # a poly value holding a non-array raises loudly instead of marshalling NULL
      begin
        buf.write_array_of_int64(widen("not an array"))
        puts "no raise"
      rescue TypeError => e
        puts e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "A"
      TypeError
    OUT
  end

  it "a runtime dlopen resolves a list of path candidates" do
    result = zr(<<~'RUBY')
      # An `ffi_lib` whose name only a RUNNING process can resolve -- a path built
      # by interpolation -- takes the dlopen/dlsym tier: the first candidate that
      # opens wins, exactly as the gem tries its alternatives. The list spans both
      # platforms' libm spellings; the leading candidate never exists.

      require "ffi"
      module M
        extend FFI::Library
        ffi_lib ["#{'/no'}/such/dir/libnothing.so", "/usr/lib/libm.dylib", "libm.so.6"]
        attach_function :pow, [:double, :double], :double
      end
      puts M.pow(2.0, 8.0)
    RUBY

    _(result).must_answer "256.0\n"
  end

  it "a :string argument coerces a boxed string rather than passing the box" do
    result = zr(<<~'RUBY')
      # An FFI :string arg call site receiving a poly-typed value (an ivar widened
      # by a mixed-type initializer) must coerce the boxed string rather than
      # passing the box itself. Ported from spinel's ffi_func (#502) to the real
      # ffi gem API; libc's atoi(const char *) exercises the :string coercion
      # through a real, always-available external function.
      require "ffi"

      class Sink
        attr_accessor :body
        def initialize(flag)
          @body = flag ? "42" : 7
        end
      end

      module Lib
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :atoi, [:string], :int
      end

      s = Sink.new(true)
      puts Lib.atoi(s.body)
    RUBY

    _(result).must_answer "42\n"
  end

  it "a function name may be a String, and the library may be the current process" do
    result = zr(<<~'RUBY')
      # The declaration spellings the corpus writes that the strict forms missed:
      # a String function name (the gem calls `.to_sym` on it), and
      # `ffi_lib FFI::CURRENT_PROCESS` (symbols from the already-linked image --
      # what a `lib` of `None` emits).

      require "ffi"
      module L
        extend FFI::Library
        ffi_lib FFI::CURRENT_PROCESS
        attach_function "abs", [:int], :int
      end
      puts L.abs(-9)
    RUBY

    _(result).must_answer "9\n"
  end

  it "a struct declared inside an eval" do
    result = zr(<<~'RUBY')
      # A `class < FFI::Struct` written inside a run-time `eval` declares its
      # layout for real.
      #
      # A struct's `layout` is a compile-time directive: `lower::ffi` computes
      # every field offset from the declared C types and REPLACES the directive,
      # in place, with the accessors `synthesize_ffi_struct` writes. That is what
      # a class body inside a snippet has to survive -- such a body runs as one
      # more `class_eval` of its own SOURCE TEXT, recovered from the statements'
      # spans, and a synthesized statement's span points into a source of
      # analyze's own making. Registering that synthesized text as a file of its
      # own is what makes it recoverable.
      #
      # The limit this cannot reach is the last section: the FFI type vocabulary
      # is per-COMPILE, so a struct declared in one snippet cannot be NAMED as a
      # field type by the next. See
      # `tests/gaps/an_ffi_type_declared_in_one_snippet.rb`.
      require "ffi"

      def show
        yield
      rescue Exception => e
        puts "#{e.class}: #{e.message.lines.first.to_s.strip[0, 60]}"
      end

      eval <<~SRC
        class Pt < FFI::Struct
          layout :x, :int, :y, :int

          def to_a = [self[:x], self[:y]]
        end
      SRC
      show do
        s = Pt.new
        s[:x] = 3
        s[:y] = 4
        p [Pt.size, Pt.offset_of(:y), s.to_a, Pt.members]
      end

      # Every storage shape a field can take, so the offsets are the C ones.
      eval <<~SRC
        class Mixed < FFI::Struct
          layout :flag, :bool,
                 :name, :string,
                 :buf,  [:char, 8],
                 :ptr,  :pointer
        end
      SRC
      show do
        m = Mixed.new
        m[:flag] = true
        p [Mixed.size, Mixed.offset_of(:ptr), m[:flag], m[:ptr].null?]
      end

      # A union is the same synthesis with every field at offset 0.
      eval <<~SRC
        class U < FFI::Union
          layout :i, :int, :f, :double
        end
      SRC
      show { p [U.size, U.offset_of(:f)] }

      # A struct named as another struct's field type, both in ONE snippet.
      show do
        eval <<~SRC
          class P2 < FFI::Struct
            layout :x, :int, :y, :int
          end
          class O2 < FFI::Struct
            layout :head, :int, :pt, P2
          end
        SRC
        o = O2.new
        o[:pt][:x] = 11
        p [O2.size, o[:pt][:x]]
      end

      # A struct and a library declared together.
      show do
        eval <<~SRC
          class Rec < FFI::Struct
            layout :sec, :long, :usec, :int
          end
          module TimeLib
            extend FFI::Library
            ffi_lib FFI::Library::LIBC
            attach_function :abs3, :abs, [:int], :int
          end
        SRC
        p [Rec.size, TimeLib.abs3(-5)]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [8, 4, [3, 4], [:x, :y]]
      [32, 24, true, true]
      [8, 0]
      [12, 11]
      [16, 5]
    OUT
  end

  it "a struct layout built by the class body lowers" do
    result = zr(<<~'RUBY')
      # A C struct whose shape depends on the platform is written as a list the
      # class body builds up and then splats into one `layout` -- sys-uname's
      # `utsname` is the canonical case, and the same idiom decides the field list
      # of a good part of the FFI corpus.
      #
      # Every step of the build is a compile-time fact: the array literal, the
      # guarded `push`es, the `<<`/`concat` appends, and the `case` that sizes the
      # char arrays. zeo folds the guards and replays the array, so the struct
      # lowers to the same fixed layout the C header describes. A build step zeo
      # could NOT follow stays a rejection -- a short struct would be a wrong one.
      require "ffi"

      class Utsname < FFI::Struct
        # The buffer width is spelled as a `case` on the older platform question.
        # Both live branches answer 16 here so the program's output does not depend
        # on which one this build picks.
        case RbConfig::CONFIG["host_os"]
        when /darwin/i
          BUFSIZE = 16
        when /linux/i
          BUFSIZE = 16
        else
          BUFSIZE = 8
        end

        members = [
          :sysname,  [:char, BUFSIZE],
          :nodename, [:char, BUFSIZE]
        ]

        members.push(:release, [:char, BUFSIZE]) if RbConfig::CONFIG["host_os"] =~ /darwin|linux/i
        members.push(:__id_number, [:char, BUFSIZE]) if RbConfig::CONFIG["host_os"] =~ /hpux/i
        members << :flags
        members << :int
        members.concat([:count, :uint32])

        layout(*members)
      end

      p Utsname::BUFSIZE
      p Utsname.size
      p Utsname.offset_of(:sysname)
      p Utsname.offset_of(:release)
      p Utsname.offset_of(:flags)
      p Utsname.offset_of(:count)
      p Utsname.members

      s = Utsname.new
      s[:flags] = 7
      s[:count] = 9
      p s[:flags]
      p s[:count]
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      16
      56
      0
      32
      48
      52
      [:sysname, :nodename, :release, :flags, :count]
      7
      9
      still running
    OUT
  end

  it "a type constant needs no library" do
    result = zr(<<~'RUBY')
      # `FFI::Type::X` is an OBJECT, and ruby-ffi's `find_type` reads whatever
      # value the constant holds. So the vocabulary a struct spends may sit in a
      # plain namespace, and a layout may name the type object outright -- neither
      # needs a module that `extend FFI::Library`.
      require "ffi"

      module Vocab
        WIDE = FFI::Type::UINT16
        TALL = FFI::Type::UINT32

        class Cell < FFI::Struct
          layout :wide, WIDE,
                 :tall, TALL,
                 :deep, FFI::Type::UINT64
        end
      end

      p Vocab::Cell.size
      p [Vocab::Cell.offset_of(:wide), Vocab::Cell.offset_of(:tall), Vocab::Cell.offset_of(:deep)]

      cell = Vocab::Cell.new
      cell[:wide] = 65_535
      cell[:tall] = 4_294_967_295
      cell[:deep] = 42
      p [cell[:wide], cell[:tall], cell[:deep]]
    RUBY

    _(result).must_answer <<~'OUT'
      16
      [0, 4, 8]
      [65535, 4294967295, 42]
    OUT
  end

  it "a type crosses between snippets" do
    result = zr(<<~'RUBY')
      # An FFI type declared in one compile can be NAMED by the next.
      #
      # A field type has to resolve to a byte width and an OFFSET at lowering time,
      # and the tables that resolve it (`Hir::ffi_types`,
      # `Hir::ffi_struct_layouts`) belong to ONE compile. A snippet is its own
      # compile, so it had never heard of a `Pt` an earlier snippet -- or the
      # program itself -- declared, even though the CLASS is right there at run
      # time and `Pt.size` answers.
      #
      # `ffi_vocab` is the process-wide vocabulary every compile publishes into and
      # a SNIPPET's compile seeds from. Sound because it is pure compile-time
      # DESCRIPTION -- names to widths, offsets and field lists -- with no reference
      # to any one arena. A whole-program compile deliberately does not seed: a
      # program is compiled once, before anything has run, and letting one
      # program's declarations reach another's would make a compile depend on what
      # else the process had done.

      require "ffi"

      # A snippet's struct, named by the NEXT snippet.
      eval <<~SRC
        class Pt < FFI::Struct
          layout :x, :int, :y, :int
        end
      SRC
      eval <<~SRC
        class Outer < FFI::Struct
          layout :head, :int, :pt, Pt
        end
      SRC
      o = Outer.new
      o[:pt][:x] = 11
      p [Outer.size, o[:pt][:x]]

      # The PROGRAM's struct, named by a snippet -- the same limit the other way.
      class Direct < FFI::Struct
        layout :a, :int, :b, :int
      end
      eval <<~SRC
        class Wrap < FFI::Struct
          layout :head, :int, :d, Direct
        end
      SRC
      w = Wrap.new
      w[:d][:b] = 7
      p [Wrap.size, w[:d][:b], Direct.size]

      # Two levels of snippet-declared struct.
      eval "class Two < FFI::Struct; layout :a, :int, :b, :int; end"
      eval "class Three < FFI::Struct; layout :t, Two, :n, :int; end"
      t = Three.new
      t[:t][:a] = 3
      p [Three.size, t[:t][:a]]

      # A `.size` on an earlier snippet's struct is a compile-time constant there
      # too.
      eval "class Sized < FFI::Struct; layout :pad, [:char, Pt.size]; end"
      p Sized.size
    RUBY

    _(result).must_answer <<~'OUT'
      [12, 11]
      [12, 7, 8]
      [12, 3]
      8
    OUT
  end

  it "the four FFI::Type class constants name the non-scalar descriptors" do
    result = zr(<<~'RUBY')
      # `FFI::Type`'s four CLASS constants -- the non-scalar type descriptors.
      # `Array`/`Function`/`Struct` alias the canonical `FFI::ArrayType`/
      # `FFI::FunctionType`/`FFI::StructByValue`; `Mapped` is named under `Type`
      # and subclasses it; `CallbackInfo` is the third name for `FunctionType`.
      require "ffi"

      p [
        FFI::Type::Array == FFI::ArrayType,
        FFI::Type::Function == FFI::FunctionType,
        FFI::Type::Struct == FFI::StructByValue,
        FFI::CallbackInfo == FFI::FunctionType,
      ]
      p [FFI::Type::Array.name, FFI::Type::Function.name, FFI::Type::Struct.name, FFI::Type::Mapped.name]
      p FFI::Type::Array.superclass == FFI::Type
      p FFI::Type::Mapped.ancestors[0, 3]
    RUBY

    _(result).must_answer <<~'OUT'
      [true, true, true, true]
      ["FFI::ArrayType", "FFI::FunctionType", "FFI::StructByValue", "FFI::Type::Mapped"]
      true
      [FFI::Type::Mapped, FFI::Type, Object]
    OUT
  end

  it "a type list may be a constant, a repeated array or a word list" do
    result = zr(<<~'RUBY')
      # Imported from the spinel corpus at c55d9bdb.
      # An ffi type list may be written the way a real adapter writes a long one:
      # a constant, a repeated array, a word list, any of them frozen or
      # parenthesised. Every form names the same function as the plain literal.
      #
      # Ported from spinel's ffi_type_list_forms, whose `ffi_func` class macro is
      # compile-time spinel DSL with no CRuby analog. The real ffi gem spells it
      # `attach_function`, which takes the same argument-type array.
      require "ffi"

      module Demo
        module Ext
          extend FFI::Library
          ffi_lib "m"

          TYPES = [:float].freeze
          PAIR = [:float, :float]
          NESTED = ([:float] * 2).freeze
          WORDS = %i[float float]
          ALIAS = TYPES

          attach_function :fabsf, TYPES, :float
          attach_function :truncf, [:float].freeze, :float
          attach_function :ceilf, ALIAS, :float
          attach_function :fmaxf, [:float] * 2, :float
          attach_function :fminf, [:float, :float], :float
          attach_function :hypotf, PAIR, :float
          attach_function :powf, NESTED, :float
          attach_function :fdimf, WORDS, :float
          attach_function :copysignf, [:float].freeze * 2, :float
        end
      end

      e = Demo::Ext
      p [e.fabsf(-2.5), e.truncf(2.9), e.ceilf(2.1)]
      p [e.fmaxf(1.5, 2.5), e.fminf(1.5, 2.5), e.hypotf(3.0, 4.0)]
      p [e.powf(2.0, 3.0), e.fdimf(5.0, 2.0), e.copysignf(3.0, -1.0)]

      # A list the class body REBINDS between declarations is not one value, so the
      # read is refused rather than answered with a stale one.
      module Demo
        module Late
          extend FFI::Library
          ffi_lib "m"
          LATER = [:double]
          attach_function :fabs, LATER, :double
        end
      end
      p Demo::Late.fabs(-3.25)
    RUBY

    _(result).must_answer <<~'OUT'
      [2.5, 2.0, 3.0]
      [2.5, 1.5, 5.0]
      [8.0, 3.0, -3.0]
      3.25
    OUT
  end

  it "a typedef aliases a scalar type" do
    result = zr(<<~'RUBY')
      # FFI `typedef :existing, :alias`: a library-local type alias,
      # declared before use as the gem requires, resolves in a later
      # `attach_function`'s type list. Behaves identically to naming the underlying
      # type -- a pure compile-time aliasing, matching the gem.

      require "ffi"
      module L
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        typedef :int, :myint
        typedef :myint, :myint2
        attach_function :abs, [:myint2], :myint
      end
      puts L.abs(-5)
    RUBY

    _(result).must_answer "5\n"
  end

  it "typedefs and guarded directives together" do
    result = zr(<<~'RUBY')
      # The FFI type registry is whole-program: `FFI.typedef` writes it from
      # whatever namespace it stands in, and every `layout` after it reads it. The
      # C99 and POSIX names whose width is the same on every target zeo emits for
      # resolve without a typedef at all.
      require "ffi"

      module Vocabulary
        FFI.typedef :uint16, :word
        FFI.typedef :uintptr_t, :handle
      end

      class Row < FFI::Struct
        layout :w, :word, :h, :handle
      end
      p [Row.size, Row.offset_of(:h)]

      class Fixed < FFI::Struct
        layout :a, :uint8_t, :b, :int32_t, :c, :uintptr_t
      end
      p [Fixed.size, Fixed.offset_of(:b), Fixed.offset_of(:c)]

      # A layout may spell a type or an inline array's count with a CONSTANT of
      # the enclosing body -- ffi-ncurses declares its whole vocabulary that way
      # above the structs that spend it.
      module Vocab
        ATTR_T = :int
        WCHAR  = :ushort
        MAX    = 5

        class Cell < FFI::Struct
          layout :attr, ATTR_T, :chars, [WCHAR, MAX]
        end
      end
      p [Vocab::Cell.size, Vocab::Cell.offset_of(:chars)]

      # A `private_constant` in a branch this compile cannot decide runs where it
      # stands, because the branch may never run at all.
      module Sealed
        if RUBY_PLATFORM.empty?
          OPEN = :never
        else
          HIDDEN = :secret
          private_constant :HIDDEN
          def self.peek = HIDDEN
        end
      end

      p Sealed.peek
      begin
        Sealed::HIDDEN
      rescue NameError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [16, 8]
      [16, 4, 8]
      [16, 4]
      :secret
      private constant Sealed::HIDDEN referenced
    OUT
  end

  it "a void-returning function works in any expression position" do
    result = zr(<<~'RUBY')
      # Void-returning FFI functions through the real ffi gem API (ported from
      # spinel's ffi_func).
      require "ffi"

      module LibC
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :malloc, [:size_t], :pointer
        attach_function :free,   [:pointer], :void
      end

      # void-returning functions can be used in any expression position;
      # the call evaluates and the value is dropped.
      p = LibC.malloc(8)
      LibC.free(p)
      puts "freed"

      # As an expression: the sequence evaluates to its last value.
      x = (LibC.free(LibC.malloc(8)); 42)
      puts x
    RUBY

    _(result).must_answer "freed\n42\n"
  end

  it "every put_ writer round-trips through the matching get_ reader" do
    result = zr(<<~'RUBY')
      # put_*/get_* round-trips through the real ffi gem API (ported from spinel's
      # ffi_write_*/ffi_read_* DSL): each writer stores a value at a byte offset
      # into a buffer and the matching reader recovers it, including a pointer slot
      # whose NULL reads back nil-equal.
      require "ffi"

      buf = FFI::MemoryPointer.new(32)

      buf.put_int32(0, -12345)
      puts buf.get_int32(0)

      buf.put_uint32(4, 4_000_000_000)
      puts buf.get_uint32(4)

      # a second write through the same slot overwrites the first
      buf.put_int32(0, 77)
      puts buf.get_int32(0)

      # ptr writer: store a pointer and read it back; an untouched (zeroed) slot
      # reads back as NULL.
      buf.put_pointer(8, buf)           # store the buffer's own address
      puts(buf.get_pointer(8) != nil)
      puts(buf.get_pointer(16) == nil)
    RUBY

    _(result).must_answer <<~'OUT'
      -12345
      4000000000
      77
      true
      true
    OUT
  end

  it "a block whose tail is an FFI pointer hands the pointer back intact" do
    result = zr(<<~'RUBY')
      # Issue #1017, ported to the real ffi gem API: a block whose tail expression
      # is an FFI pointer value must flow that pointer out of the block intact
      # (the original guarded a codegen cast when the tail crossed the proc-return
      # ABI). The yielded pointer here is NULL -- the first word of a zero-filled
      # MemoryPointer -- so the pool's free list ends up holding a nil-equal
      # pointer.
      require "ffi"

      scratch = FFI::MemoryPointer.new(16)

      class Pool
        def initialize(n)
          @free = []
          i = 0
          while i < n
            @free.push(yield)
            i += 1
          end
        end
        def first
          @free[0]
        end
      end

      pool = Pool.new(1) { scratch.read_pointer }
      if pool.first == nil
        puts "ok"
      else
        puts "not_ok"
      end
    RUBY

    _(result).must_answer "ok\n"
  end

  it "implicit self new in a concealed class" do
    result = zr(<<~'RUBY')
      # A class method calling bare `new` inside a class whose constant is
      # CONCEALED -- `FFI.constants` is a namespace observer, so every member of it
      # becomes a runtime question and `.new` reads the constant through the
      # concealment check. That route answers a plain value, and the implicit-self
      # call site has to agree with it: boxing what it already boxed is an invalid
      # program, not a wrong answer, so this test is a compile check as much as a
      # value one.
      require "ffi"

      p FFI.constants.grep(/^TYPE_/).sort.first(3)
      p FFI::LibraryPath.wrap("m").class
      p FFI::LibraryPath.wrap("m").name
      p FFI::LibraryPath.wrap("/usr/lib/libm.dylib")
      p FFI::LibraryPath.wrap(FFI::LibraryPath.new("z")).name
    RUBY

    _(result).must_answer <<~'OUT'
      [:TYPE_BOOL, :TYPE_BUFFER_IN, :TYPE_BUFFER_INOUT]
      FFI::LibraryPath
      "m"
      "/usr/lib/libm.dylib"
      "z"
    OUT
  end

  it "module body require declares before the next statement" do
    result = zr(<<~'RUBY', files: beside("module_body_require/uv_types.rb"))
      # A require written in a `class`/`module` BODY runs mid-body in CRuby, so
      # the target's declarations exist before the statements below it -- libuv
      # requires its `ext/types` (every typedef and enum) three lines above the
      # `attach_function`s that spend them. The vocabulary must lower first, which
      # is what the pre-lower here pins; the required file's STATEMENTS run at the
      # require's own position, which
      # `a_class_body_require_runs_in_place` pins.
      require "ffi"

      module Loop
        extend FFI::Library
        ffi_lib FFI::Library::LIBC

        require_relative "module_body_require/uv_types"

        attach_function :big_abs, :labs, [:uv_ret], :uv_ret
        # The enum declared by the sibling is vocabulary here too.
        attach_function :kind_abs, :abs, [:uv_kind], :int
      end

      p Loop.big_abs(-3_000_000_000)
      p Loop.kind_abs(:udp)
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      3000000000
      7
      still running
    OUT
  end

  it "sp net basic" do
    result = zr(<<~'RUBY')
      # Ported from spinel's bundled sp_net.c FFI surface. sp_net_shell_capture is
      # spinel-private (Kernel backticks are the Ruby spelling of the same thing);
      # getpid stays a real FFI binding through the ffi gem.
      #
      # Cross-platform-deterministic smoke: shell capture + getpid produce the
      # same output on every POSIX target, so the .expected holds for Linux +
      # macOS CI.
      require "ffi"

      module Net
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :getpid, [], :int
      end

      # Shell capture: stdout of `printf hello` is exactly "hello".
      puts `printf hello`

      # getpid is always a positive pid (print a stable token, not the pid).
      puts(Net.getpid > 0 ? "pid-ok" : "pid-bad")
    RUBY

    _(result).must_answer "hello\npid-ok\n"
  end

  it "toplevel runs on the process main thread" do
    skip "runs only on macos" unless ["macos"].include?(Zr::Spec.platform)

    result = zr(<<~'RUBY')


      # The top level runs on the PROCESS main thread (`pthread_main_np` == 1),
      # the thread Apple's frameworks insist on: AppKit raises
      # `NSInternalInconsistencyException: NSWindow should only be instantiated on
      # the main thread!` from any other, WebKit, Metal and the Cocoa run loop share
      # the rule, and no dispatch trick satisfies the check. zeo once ran the top
      # level on a spawned 64 MiB thread; the darwin link line now sizes the main
      # thread's stack instead (`-stack_size`, see `link_binary`). The portable
      # half -- `Thread.current` at the top level is `Thread.main` -- is
      # tests/the_toplevel_thread_is_the_main_thread.rb.

      require "ffi"
      module AK
        extend FFI::Library
        ffi_lib "objc"
        ffi_lib "/System/Library/Frameworks/AppKit.framework/AppKit"
        class CGPoint < FFI::Struct
          layout :x, :double, :y, :double
        end
        class CGSize < FFI::Struct
          layout :width, :double, :height, :double
        end
        class NSRect < FFI::Struct
          layout :origin, CGPoint, :size, CGSize
        end
        attach_function :objc_getClass, [:string], :pointer
        attach_function :sel_registerName, [:string], :pointer
        attach_function :send_id, :objc_msgSend, [:pointer, :pointer], :pointer
        attach_function :send_init_rect, :objc_msgSend, [:pointer, :pointer, NSRect.by_value, :ulong, :ulong, :bool], :pointer
        attach_function :pthread_main_np, [], :int
      end
      def sel(s) = AK.sel_registerName(s)
      puts "main thread: #{AK.pthread_main_np}"
      puts "Thread.main: #{Thread.current.equal?(Thread.main)}"
      r = AK::NSRect.new
      r[:origin][:x] = 100
      r[:origin][:y] = 200
      r[:size][:width] = 640
      r[:size][:height] = 480
      win = AK.send_init_rect(AK.send_id(AK.objc_getClass("NSWindow"), sel("alloc")), sel("initWithContentRect:styleMask:backing:defer:"), r, 15, 2, false)
      puts "window: #{win.null? ? "NULL" : "ok"}"
    RUBY

    _(result).must_answer <<~'OUT'
      main thread: 1
      Thread.main: true
      window: ok
    OUT
  end

  it "a Thread runs off the process main thread" do
    skip "a Thread is a green one and shares the main OS thread, so pthread_main_np answers 1 inside it"
    skip "runs only on macos" unless ["macos"].include?(Zr::Spec.platform)

    result = zr(<<~'RUBY')
      require "ffi"
      module PT
        extend FFI::Library
        ffi_lib FFI::Library::LIBC
        attach_function :pthread_main_np, [], :int
      end
      puts "worker: #{Thread.new { PT.pthread_main_np }.value}"
    RUBY

    _(result).must_answer "worker: 0\n"
  end
end
