# frozen_string_literal: true

# Derived from the C half of the ffi gem (BSD-3-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# FunctionInfo.c, Function.c and Call.c: a C function's signature, a
# function to call through it, a Proc C can call through a closure, and
# how a call turns ruby values into C arguments and a C result back.
module FFI
  class FunctionType < Type
    def initialize(return_type, param_types, options = nil)
      unless options.nil?
        @enums = options[:enums]
        @blocking = options[:blocking] ? true : false
      end
      @params = FFI.typed(param_types, ::Array, "Array").map do |entry|
        FFI.type_lookup(entry) || raise(TypeError, "Invalid parameter type (#{entry.inspect})")
      end
      @callbacks = @params.grep(FunctionType)
      @return = FFI.type_lookup(return_type) || raise(TypeError, "Invalid return type (#{return_type.inspect})")
      @cif = FFIType.cif(@return, @params, nil)
      @params.freeze
      freeze
    end

    def return_type = @return

    def param_types = @params.dup

    # Whether a call runs without the GVL (`blocking: true`).
    def ffi_blocking
      Primitive.attr! :hidden
      @blocking == true
    end

    def ffi_native
      Primitive.attr! :hidden
      NATIVE[:FUNCTION]
    end

    def ffi_type
      Primitive.attr! :hidden
      FFIType.builtin("pointer", 14, 8)
    end

    # What a call through this signature reads: the prepared cif, and the
    # types, callback signatures and enums it converts arguments with.
    def ffi_cif
      Primitive.attr! :hidden
      @cif
    end

    def ffi_params
      Primitive.attr! :hidden
      @params
    end

    def ffi_callbacks
      Primitive.attr! :hidden
      @callbacks
    end

    def ffi_enums
      Primitive.attr! :hidden
      @enums
    end
  end

  class FFIType
    # sizeof(ffi_cif), 40 at most.
    CIF_SIZE = 40
    # libffi's FFI_DEFAULT_ABI: FFI_UNIX64 on x86_64, FFI_SYSV on arm64.
    DEFAULT_ABI = RUBY_PLATFORM.start_with?("x86_64") ? 2 : 1

    # ffi_prep_cif, or ffi_prep_cif_var when `fixed` of the parameters are
    # fixed: the cif's bytes, with the type list they name and the types
    # that list's elements are, which live as long as the cif.
    def self.cif(return_type, params, fixed)
      atypes = FFI.storage(8 * [params.size, 1].max)
      list = params.map { |type| type.ffi_type.address }.pack("Q*")
      Primitive.zr_ffi_write(FFI.address_of(atypes), list, 0, list.bytesize)
      cif = FFI.storage(CIF_SIZE)
      status = Primitive.zr_ffi_prep(FFI.address_of(cif), DEFAULT_ABI, fixed || -1, params.size, return_type.ffi_type.address, FFI.address_of(atypes))
      case status
      when 0 then [cif, atypes, return_type, params]
      when 1 then raise ArgumentError, "Invalid argument type specified"
      when 2 then raise ArgumentError, "Invalid ABI specified"
      else raise ArgumentError, "Unknown FFI error"
      end
    end
  end

  CallbackInfo = FunctionType
  FunctionInfo = FunctionType
  Type::Function = FunctionType

  class Function < Pointer
    Primitive.zr_define_alloc(self)

    # sizeof(Closure), the size that a function over a Proc returns.
    CLOSURE_SIZE = 48
    MEM_RD = 0x01
    private_constant :CLOSURE_SIZE, :MEM_RD

    class << self
      # rbffi_Function_NewInstance.
      def new_instance(info, proc)
        Primitive.attr! :hidden
        Primitive.zr_class_build(Function).__send__(:ffi_init, info, proc)
      end

      # rbffi_Function_ForProc: the one function that a Proc has for a
      # signature, which the Proc keeps.
      def for_proc(info, proc)
        Primitive.attr! :hidden
        ref = proc.instance_variable_defined?(:@__ffi_callback__) ? proc.instance_variable_get(:@__ffi_callback__) : nil
        return ref if Primitive.zr_real_class(ref) == Function && ref.__send__(:type).equal?(info)

        table = proc.instance_variable_defined?(:@__ffi_callback_table__) ? proc.instance_variable_get(:@__ffi_callback_table__) : nil
        found = table && table[info]
        return found unless found.nil?

        callback = new_instance(info, proc)
        if ref.nil?
          proc.instance_variable_set(:@__ffi_callback__, callback)
        else
          table ||= proc.instance_variable_set(:@__ffi_callback_table__, {})
          table[info] = callback
        end
        callback
      end

      # The functions whose closures C can call, by the id in each
      # closure. C calls this with the id and the addresses of the result
      # and the arguments.
      def closure_id
        Primitive.attr! :hidden
        @closure_id = (@closure_id || 0) + 1
      end

      def closures
        Primitive.attr! :hidden
        @closures ||= begin
          Primitive.zr_ffi_callback_set(->(id, result, params) { closures[id]&.__send__(:ffi_invoke, result, params) })
          ObjectSpace::WeakMap.new
        end
      end
    end

    def initialize(return_type, param_types, *rest, &block)
      raise ArgumentError, wrong_arity(rest.size + 2, 2..4) if rest.size > 2

      if block
        raise ArgumentError, "cannot create function with both proc/address and block" if rest.size > 1

        options = rest[0]
        proc = block
      else
        proc, options = rest
      end
      info = options.nil? ? FunctionType.new(return_type, param_types) : FunctionType.new(return_type, param_types, options)
      ffi_init(info, proc)
    end

    def initialize_copy(_other)
      raise RuntimeError, "cannot duplicate function instances"
    end

    def call(*args, &block) = FFI.call_function(args, block, ffi_address, @info)

    def attach(mod, name)
      name = Primitive.zr_str_operand(name)
      raise RuntimeError, "trying to attach function to non-module" unless mod.is_a?(Module)

      function = self
      mod.singleton_class.define_method(name) { |*args, &block| function.call(*args, &block) }
      mod.define_method(name) { |*args, &block| function.call(*args, &block) }
      self
    end

    def free
      raise RuntimeError, "cannot free function which was not allocated" if @closure.nil?

      Function.closures.delete(@closure[1])
      Primitive.zr_ffi_closure_free(@closure[0])
      @closure = nil
      self
    end

    def autorelease=(autorelease)
      Primitive.zr_frozen_error(self) if frozen?

      @autorelease = autorelease ? true : false
      self
    end

    def autorelease = @autorelease != false

    alias autorelease? autorelease

    private

    def type = @info

    # function_init: a function at a pointer's address, or over a Proc
    # through a closure of its own.
    def ffi_init(info, proc)
      Primitive.attr! :hidden
      @info = FFI.typed(info, FunctionType)
      @flags = MEM_RD
      if proc.is_a?(Pointer)
        @parent = proc
        ffi_memory(proc.ffi_address, proc.ffi_size, proc.ffi_flags, proc.type_size)
      elsif proc.is_a?(Proc) || proc.respond_to?(:call)
        id = Function.closure_id
        closure, code = Primitive.zr_ffi_closure(FFI.address_of(@info.ffi_cif[0]), id)
        raise NoMemoryError, "failed to create closure pool" if closure.nil?

        @closure = [closure, id]
        Function.closures[id] = self
        ffi_memory(code, CLOSURE_SIZE, MEM_RD, type_size)
      else
        raise TypeError, "wrong argument type #{Primitive.zr_class_path(Primitive.zr_real_class(proc))}, expected pointer or proc"
      end
      @proc = proc
      self
    end

    # invoke_callback: C called the closure. Each argument reads as its
    # type, the Proc runs, and its return value goes where C reads the
    # result. An error clears the result and raises again after C returns.
    def ffi_invoke(result, params)
      Primitive.attr! :hidden
      return_type = @info.return_type
      addresses = @info.ffi_params.empty? ? [] : Primitive.zr_ffi_read(params, 8 * @info.ffi_params.size).unpack("Q*")
      args = @info.ffi_params.each_with_index.map do |type, i|
        native = type.ffi_kind == :MAPPED ? type.native_type : type
        value = FFI.callback_arg(native, addresses[i])
        type.ffi_kind == :MAPPED ? type.converter.__send__(:from_native, value, nil) : value
      end
      value = @proc.__send__(:call, *args)
      if return_type.ffi_kind == :MAPPED
        value = return_type.converter.__send__(:to_native, value, nil)
        return_type = return_type.native_type
      end
      FFI.callback_result(return_type, result, value)
    rescue Exception
      Primitive.zr_ffi_fill(result, 0, return_type.ffi_type.size)
      raise
    end
  end

  # How each number reads from the bytes C left it in.
  NATIVE_DIRECTIVES = { INT8: "c", INT16: "s", INT32: "l", INT64: "q", LONG: "q", UINT8: "C", UINT16: "S", UINT32: "L",
                        UINT64: "Q", ULONG: "Q", FLOAT32: "f", FLOAT64: "d", LONGDOUBLE: "d" }.freeze
  private_constant :NATIVE_DIRECTIVES

  class << self
    # rbffi_CallFunction: a call of the function at `address` with the
    # arguments converted by `info`. Returns its result as a Ruby value.
    def call_function(args, block, address, info)
      Primitive.attr! :hidden
      params, values, keep = call_params(args, block, info.ffi_params.size, info.ffi_params, info.ffi_callbacks, info.ffi_enums)
      call_prepared(info.ffi_cif, address, info.return_type, params, values, keep, info.ffi_blocking)
    end

    # A blocking call (rbffi_do_blocking_call) runs without the GVL, while
    # the program's other threads run.
    def call_prepared(cif, address, return_type, params, values, keep, blocking = false)
      Primitive.attr! :hidden
      result = storage([return_type.ffi_type.size, 8].max)
      errno = Primitive.zr_ffi_call(address_of(cif[0]), address, address_of(result), address_of(values), blocking)
      LastError.save(errno)
      native_to_ruby(return_type, address_of(result))
    end

    # rbffi_SetupCallParams: every argument in its C form, eight bytes
    # each, and the address of each; a struct passes the address of its
    # own bytes. `keep` contains the objects that those addresses point into.
    def call_params(args, block, param_count, types, callbacks, enums)
      Primitive.attr! :hidden
      if param_count != -1 && param_count != args.size
        raise ArgumentError, "wrong number of arguments (#{args.size} for #{param_count})" unless args.size == param_count - 1 && callbacks.size == 1 && block

        callback = block
      end
      args = args.dup
      count = param_count == -1 ? args.size : param_count
      params = storage(8 * [count, 1].max)
      base = address_of(params)
      keep = [callback]
      words = []
      addresses = []
      index = 0
      callback_index = 0
      count.times do |i|
        type = types[i]
        if type.ffi_kind == :MAPPED
          args[index] = type.converter.__send__(:to_native, args[index], nil)
          type = type.native_type
        end
        arg = args[index]
        addresses << base + 8 * i
        case type.ffi_kind
        when :INT8, :INT16, :INT32 then words << int_value(enum_value(arg, enums))
        when :UINT8, :UINT16, :UINT32 then words << uint_value(enum_value(arg, enums))
        when :INT64 then words << ll_value(enum_value(arg, enums))
        when :UINT64 then words << ull_value(enum_value(arg, enums))
        when :LONG then words << long_value(enum_value(arg, enums))
        when :ULONG then words << ulong_value(enum_value(arg, enums))
        when :FLOAT32 then words << [dbl_value(enum_value(arg, enums))].pack("f").unpack1("L")
        when :FLOAT64 then words << [dbl_value(enum_value(arg, enums))].pack("d").unpack1("Q")
        when :LONGDOUBLE then words << [longdouble_value(enum_value(arg, enums))].pack("d").unpack1("Q")
        when :BOOL
          raise TypeError, "wrong argument type  (expected a boolean parameter)" unless arg == true || arg == false

          words << (arg == true ? 1 : 0)
        when :STRING
          text = arg.nil? ? nil : cstr_value(arg)
          keep << text
          words << (text ? address_of(text) : 0)
        when :POINTER, :BUFFER_IN, :BUFFER_OUT, :BUFFER_INOUT
          keep << arg
          words << pointer_address(arg, keep)
        when :FUNCTION
          target = callback || arg
          words << callback_address(target, callbacks[callback_index], keep)
          callback_index += 1
          index -= 1 if callback
        when :STRUCT
          keep << arg
          addresses[i] = pointer_address(arg, keep)
          words << 0
        else
          raise ArgumentError, "Invalid parameter type: #{type.ffi_native}"
        end
        index += 1
      end
      bytes = words.map { |word| word % 2**64 }.pack("Q*")
      Primitive.zr_ffi_write(base, bytes, 0, bytes.bytesize)
      [params, addresses.pack("Q*"), keep]
    end

    def enum_value(arg, enums)
      Primitive.attr! :hidden
      arg.is_a?(Symbol) && !enums.nil? ? enums.__send__(:__map_symbol, arg) : arg
    end

    # getPointer: the address a pointer argument passes.
    def pointer_address(value, keep)
      Primitive.attr! :hidden
      case value
      when AbstractMemory then value.ffi_address
      when FFI::Struct
        pointer = value.__send__(:ffi_pointer)
        pointer.nil? ? 0 : pointer.ffi_address
      when ::String then address_of(value)
      when nil then 0
      else
        raise ArgumentError, ":pointer argument is not a valid pointer" unless value.respond_to?(:to_ptr)

        pointer = value.to_ptr
        raise ArgumentError, "to_ptr returned an invalid pointer" unless pointer.is_a?(AbstractMemory)

        keep << pointer
        pointer.ffi_address
      end
    end

    # callback_param: the address C calls a callback argument at.
    def callback_address(value, info, keep)
      Primitive.attr! :hidden
      return 0 if value.nil?
      return value.ffi_address if value.is_a?(Function)

      function = Function.for_proc(info, value)
      keep << function
      function.ffi_address
    end

    # rbffi_NativeValue_ToRuby: what a C result reads as.
    def native_to_ruby(type, address)
      Primitive.attr! :hidden
      kind = type.ffi_kind
      case kind
      when :VOID then nil
      when *NATIVE_DIRECTIVES.keys, :BOOL
        from_native_number(kind, Primitive.zr_ffi_read(address, 8).unpack1(NATIVE_DIRECTIVES.fetch(kind, "C")))
      when :STRING then string_at(Primitive.zr_ffi_read(address, 8).unpack1("Q"))
      when :POINTER then Pointer.new_instance(Primitive.zr_ffi_read(address, 8).unpack1("Q"))
      when :FUNCTION
        pointer = Primitive.zr_ffi_read(address, 8).unpack1("Q")
        pointer.zero? ? nil : Function.new_instance(type, Pointer.new_instance(pointer))
      when :STRUCT
        memory = MemoryPointer.new_instance(1, type.ffi_type.size, false)
        Primitive.zr_ffi_copy(memory.ffi_address, address, type.ffi_type.size)
        struct = Class.instance_method(:allocate).bind_call(type.struct_class)
        struct.__send__(:initialize, memory)
        struct
      when :MAPPED
        type.converter.__send__(:from_native, native_to_ruby(type.native_type, address), nil)
      else
        raise RuntimeError, "Unknown type: #{type.ffi_native}"
      end
    end

    # An argument C passed a callback, at `address`.
    def callback_arg(type, address)
      Primitive.attr! :hidden
      kind = type.ffi_kind
      case kind
      when :FUNCTION, :STRUCT, :STRING, :POINTER then native_to_ruby(type, address)
      when :BOOL then Primitive.zr_ffi_read(address, 1).getbyte(0) != 0
      when *NATIVE_DIRECTIVES.keys
        from_native_number(kind, Primitive.zr_ffi_read(address, AbstractMemory.op_size(kind)).unpack1(NATIVE_DIRECTIVES.fetch(kind)))
      end
    end

    # A callback's return value, written where C reads it.
    def callback_result(type, address, value)
      Primitive.attr! :hidden
      size = type.ffi_type.size
      return Primitive.zr_ffi_fill(address, 0, size) if value.nil?

      bytes = case type.ffi_kind
              when :INT8, :INT16, :INT32 then [int_value(value)].pack("q")
              when :UINT8, :UINT16, :UINT32 then [uint_value(value) % 2**32].pack("Q")
              when :INT64 then [ll_value(value)].pack("q")
              when :UINT64 then [ull_value(value) % 2**64].pack("Q")
              when :LONG then [long_value(value)].pack("q")
              when :ULONG then [ulong_value(value) % 2**64].pack("Q")
              when :FLOAT32 then [dbl_value(value)].pack("f")
              when :FLOAT64 then [dbl_value(value)].pack("d")
              when :LONGDOUBLE then [longdouble_value(value)].pack("d")
              when :POINTER then [value.is_a?(Pointer) ? value.ffi_address : 0].pack("Q")
              when :BOOL then [value == true ? 1 : 0].pack("Q")
              when :FUNCTION
                address_of_function = if value.is_a?(Pointer) then value.ffi_address
                                      elsif value.is_a?(Proc) || value.respond_to?(:call) then Function.for_proc(type, value).ffi_address
                                      else 0
                                      end
                [address_of_function].pack("Q")
              when :STRUCT
                pointer = value.is_a?(FFI::Struct) ? value.__send__(:ffi_pointer) : nil
                return Primitive.zr_ffi_fill(address, 0, size) if pointer.nil? || pointer.ffi_address.zero?

                return Primitive.zr_ffi_copy(address, pointer.ffi_address, size)
              else [0].pack("Q")
              end
      Primitive.zr_ffi_write(address, bytes, 0, bytes.bytesize)
    end
  end
end
