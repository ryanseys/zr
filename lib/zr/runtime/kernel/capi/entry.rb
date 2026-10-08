module Zr::Kern
  # CRuby's C API, for C extensions: each `rb_*` def here is the function
  # of that name, which an extension's machine code calls. zr's objects
  # have CRuby 4.0's layout (value.rb, string.rb), so an extension reads
  # them inline as it reads ruby's, and calls these functions for the
  # rest.
  #
  # A def that C calls starts with `Machine.gates_enter`, then
  # zr_c_entered: the first loads the gate word and saves all of C's
  # callee-saved registers in its frame; the second tells the collector
  # where C's frames end (c_frame.rb). A C caller never sees undef: when
  # zr code that a def calls raises, the def gives the result to
  # zr_c_result, which unwinds out of C, as rb_raise longjmps.

  # Marks the low end of the C frames of the innermost C call: a slot of
  # this frame, which is below the frame of the def that C called.
  #: () -> void
  def zr_c_entered
    zr_c_frames_end(Machine.slot(8))
  end

  # The result of zr code that a C-API def called: `v`, or no return at
  # all when `v` is undef, because zr_c_unwind leaves the C frames.
  #: (value) -> value
  def zr_c_result(v)
    if v == QUNDEF
      zr_c_unwind()
    end
    v
  end

  # Raises `klass` with the message `bytes` from a C-API def: it does not
  # return.
  #: (value, ptr, word) -> void
  def zr_c_raise(klass, bytes, len)
    zr_c_result(zr_raise_msg(klass, bytes, len))
  end

  # Runs a C extension's Init function (`Init_hello`) where ruby's require
  # of its bundle runs it: the toplevel of the extension's unit
  # (`Hir::ExtInit`) calls this. Returns undef when Init raised.
  #: (ptr) -> value
  def zr_ext_init(init)
    zr_capi_init()
    argv = Machine.slot(64)
    if zr_call_c(init, argv, 0) == QUNDEF
      return Machine.value(QUNDEF)
    end
    Machine.value(QTRUE)
  end

  # Runs a C extension that the binary loads with dlopen: the bundle at
  # `path`, and its Init function `init`. The binary exports the C API,
  # which the bundle's imports bind to. Raises LoadError with dlopen's
  # reason when the bundle does not load. Returns undef when Init raised.
  #: (value, value) -> value
  def zr_ext_load(path, init)
    handle = Libc.dlopen(RString[path].ptr, Machine.i32(RTLD_LAZY))
    if handle == 0
      why = Libc.dlerror()
      return zr_raise_msg(zr_core_class(Machine.id(:LoadError)), why, zr_cstr_len(why))
    end
    fn = Libc.dlsym(handle, RString[init].ptr)
    if fn == 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("no "), 3)
      zr_buf_str(b, init)
      zr_buf_push(b, Machine.bytes(" in "), 4)
      zr_buf_str(b, path)
      return zr_raise_buf(zr_core_class(Machine.id(:LoadError)), b)
    end
    zr_ext_init(fn)
  end

  # Sets the words that an extension reads as `rb_cObject` and the like,
  # once, before the first Init runs. They hold core classes, which their
  # constants keep alive.
  #: () -> void
  def zr_capi_init
    done = Machine.static(:capi_ready, 8)
    if Machine.load64(done, 0) != 0
      return
    end
    Machine.store64(done, 0, 1)
    zr_capi_set(Machine.global(:rb_cBasicObject), zr_global(G_BASIC_OBJECT))
    zr_capi_set(Machine.global(:rb_cObject), zr_global(G_OBJECT))
    zr_capi_set(Machine.global(:rb_cModule), zr_global(G_MODULE))
    zr_capi_set(Machine.global(:rb_cClass), zr_global(G_CLASS))
    zr_capi_set(Machine.global(:rb_mKernel), zr_global(G_KERNEL))
    zr_capi_set(Machine.global(:rb_cInteger), zr_global(G_INTEGER))
    zr_capi_set(Machine.global(:rb_cString), zr_global(G_STRING))
    zr_capi_set(Machine.global(:rb_cSymbol), zr_global(G_SYMBOL))
    zr_capi_set(Machine.global(:rb_cNilClass), zr_global(G_NIL))
    zr_capi_set(Machine.global(:rb_cTrueClass), zr_global(G_TRUE))
    zr_capi_set(Machine.global(:rb_cFalseClass), zr_global(G_FALSE))
    zr_capi_set(Machine.global(:rb_cRange), zr_global(G_RANGE))
    zr_capi_set(Machine.global(:rb_cNumeric), zr_global(G_NUMERIC))
    zr_capi_set(Machine.global(:rb_cArray), zr_global(G_ARRAY))
    zr_capi_set(Machine.global(:rb_cHash), zr_global(G_HASH))
    zr_capi_set(Machine.global(:rb_cProc), zr_global(G_PROC))
    zr_capi_set(Machine.global(:rb_cFloat), zr_global(G_FLOAT))
    zr_capi_set(Machine.global(:rb_cRegexp), zr_global(G_REGEXP))
    zr_capi_set(Machine.global(:rb_eException), zr_global(G_EXCEPTION))
    zr_capi_set(Machine.global(:rb_eStandardError), zr_global(G_STANDARD_ERROR))
    zr_capi_set(Machine.global(:rb_eArgError), zr_global(G_ARGUMENT_ERROR))
    zr_capi_set(Machine.global(:rb_eNameError), zr_global(G_NAME_ERROR))
    zr_capi_set(Machine.global(:rb_eNoMethodError), zr_global(G_NO_METHOD_ERROR))
    zr_capi_set(Machine.global(:rb_eTypeError), zr_global(G_TYPE_ERROR))
    zr_capi_set(Machine.global(:rb_eZeroDivError), zr_global(G_ZERO_DIVISION_ERROR))
    zr_capi_set(Machine.global(:rb_eRuntimeError), zr_global(G_RUNTIME_ERROR))
    zr_capi_set(Machine.global(:rb_eIndexError), zr_global(G_INDEX_ERROR))
    zr_capi_set(Machine.global(:rb_eFrozenError), zr_global(G_FROZEN_ERROR))
    zr_capi_set(Machine.global(:rb_eKeyError), zr_global(G_KEY_ERROR))
    zr_capi_set(Machine.global(:rb_eFatal), zr_global(G_FATAL))
    zr_capi_set(Machine.global(:rb_mComparable), zr_core_class(Machine.id(:Comparable)))
    zr_capi_set(Machine.global(:rb_mEnumerable), zr_core_class(Machine.id(:Enumerable)))
    zr_capi_set(Machine.global(:rb_cEncoding), zr_core_class(Machine.id(:Encoding)))
    zr_capi_set(Machine.global(:rb_cIO), zr_core_class(Machine.id(:IO)))
    zr_capi_set(Machine.global(:rb_cFile), zr_core_class(Machine.id(:File)))
    zr_capi_set(Machine.global(:rb_cTime), zr_core_class(Machine.id(:Time)))
    zr_capi_set(Machine.global(:rb_cRandom), zr_core_class(Machine.id(:Random)))
    zr_capi_set(Machine.global(:rb_cRational), zr_core_class(Machine.id(:Rational)))
    zr_capi_set(Machine.global(:rb_cComplex), zr_core_class(Machine.id(:Complex)))
    zr_capi_set(Machine.global(:rb_cStruct), zr_core_class(Machine.id(:Struct)))
    zr_capi_set(Machine.global(:rb_eRangeError), zr_core_class(Machine.id(:RangeError)))
    zr_capi_set(Machine.global(:rb_eFloatDomainError), zr_core_class(Machine.id(:FloatDomainError)))
    zr_capi_set(Machine.global(:rb_eIOError), zr_core_class(Machine.id(:IOError)))
    zr_capi_set(Machine.global(:rb_eEOFError), zr_core_class(Machine.id(:EOFError)))
    zr_capi_set(Machine.global(:rb_eNoMemError), zr_core_class(Machine.id(:NoMemoryError)))
    zr_capi_set(Machine.global(:rb_eLoadError), zr_core_class(Machine.id(:LoadError)))
    zr_capi_set(Machine.global(:rb_eNotImpError), zr_core_class(Machine.id(:NotImplementedError)))
    zr_capi_set(Machine.global(:rb_eSystemCallError), zr_core_class(Machine.id(:SystemCallError)))
    zr_capi_set(Machine.global(:rb_eStopIteration), zr_core_class(Machine.id(:StopIteration)))
    zr_capi_set(Machine.global(:rb_eEncodingError), zr_core_class(Machine.id(:EncodingError)))
    zr_capi_set(Machine.global(:rb_eSecurityError), zr_core_class(Machine.id(:SecurityError)))
    zr_capi_set(Machine.global(:rb_eInterrupt), zr_core_class(Machine.id(:Interrupt)))
    zr_capi_set(Machine.global(:rb_eScriptError), zr_core_class(Machine.id(:ScriptError)))
    zr_capi_set(Machine.global(:rb_eSyntaxError), zr_core_class(Machine.id(:SyntaxError)))
    zr_capi_set(Machine.global(:rb_eThreadError), zr_core_class(Machine.id(:ThreadError)))
  end

  #: (ptr, value) -> void
  def zr_capi_set(word, v)
    Machine.store64(word, 0, Machine.word(v))
  end
end
