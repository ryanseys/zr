# frozen_string_literal: true

# Derived from the C half of the ffi gem (BSD-3-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# DynamicLibrary.c: a library dlopen opened, and the symbols dlsym finds
# in it. The dlopen flags are the OS's own.
require "ffi_c/rtld"

module FFI
  class DynamicLibrary
    class Symbol < Pointer
      Primitive.zr_define_alloc(self)

      def inspect = Primitive.zr_obj_form("#<FFI::DynamicLibrary::Symbol name=#{@name} address=#{FFI.hex(ffi_address)}>")

      def initialize_copy(_other)
        raise RuntimeError, "cannot duplicate symbol"
      end

      private

      def assign(library, address, name)
        Primitive.attr! :hidden
        @parent = library
        @name = name.frozen? ? name : name.dup.freeze
        ffi_memory(address, 2**63 - 1, 0x3, 1)
        freeze
      end
    end

    def self.open(name, flags) = instance_method(:initialize).bind_call(allocate, name, flags)

    def self.last_error = Primitive.zr_ffi_dlerror

    def initialize(name, flags)
      flags = FFI.typed(flags, Integer)
      raise TypeError, "wrong argument type Integer (expected Integer)" unless flags.between?(-2**62, 2**62 - 1)

      path = name.nil? ? nil : FFI.cstr_value(name)
      @handle = Primitive.zr_ffi_dlopen(path, (FFI.uint_value(flags) % 2**32).nonzero? || RTLD_LAZY)
      raise LoadError, "Could not open library '#{path || "[current process]"}': #{Primitive.zr_ffi_dlerror}" if @handle.nil?

      instance_variable_set(:@name, path.nil? ? +"[current process]" : (path.frozen? ? path : path.dup.freeze))
      freeze
    end

    def find_symbol(name)
      name = FFI.typed(name, ::String)
      address = Primitive.zr_ffi_dlsym(@handle || 0, FFI.cstr_value(name))
      address.zero? ? nil : Primitive.zr_class_build(Symbol).__send__(:assign, self, address, name)
    end

    alias find_function find_symbol
    alias find_variable find_symbol

    def last_error = Primitive.zr_ffi_dlerror

    def name = instance_variable_get(:@name)
  end

  NativeLibrary = DynamicLibrary
end
