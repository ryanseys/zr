# frozen_string_literal: true

# Derived from the C half of the ffi gem (BSD-3-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# Variadic.c: a call of a C function that takes arguments past its fixed
# ones, whose types each call names.
module FFI
  class VariadicInvoker
    def initialize(function, parameter_types, return_type, options)
      options = FFI.typed(options, ::Hash)
      @enums = options[:enums]
      @address = FFI.typed(function, Pointer).ffi_address
      @function = function
      @blocking = options[:blocking] ? true : false
      options[:convention].to_s
      @return_type = FFI.type_lookup(return_type) || raise(TypeError, "Invalid return type (#{return_type.inspect})")
      FFI.typed(return_type, Type)
      fixed = parameter_types.reject do |entry|
        type = FFI.type_lookup(entry) || raise(TypeError, "Invalid parameter type (#{entry.inspect})")
        type.ffi_kind == :VARARGS
      end
      instance_variable_set(:@fixed, fixed.freeze)
      instance_variable_set(:@type_map, options[:type_map])
      nil
    end

    def invoke(parameter_types, parameter_values)
      parameter_types = FFI.typed(parameter_types, ::Array)
      parameter_values = FFI.typed(parameter_values, ::Array)
      callbacks = []
      types = parameter_types.map do |type|
        raise TypeError, "wrong type.  Expected (FFI::Type)" unless type.is_a?(Type)

        case type.ffi_kind
        when :INT8, :INT16, :INT32 then Type::INT32
        when :UINT8, :UINT16, :UINT32 then Type::UINT32
        when :FLOAT32 then Type::DOUBLE
        when :FUNCTION
          raise TypeError, "Incorrect parameter type (#{type.inspect})" unless type.is_a?(FunctionType)

          callbacks << type
          type
        else type
        end
      end
      values = ::Array.new(types.size) { |i| parameter_values[i] }
      cif = FFIType.cif(@return_type, types, instance_variable_get(:@fixed).size)
      params, addresses, keep = FFI.call_params(values, nil, -1, types, callbacks, @enums)
      FFI.call_prepared(cif, @address, @return_type, params, addresses, keep, @blocking == true)
    end

    def return_type = @return_type
  end
end
