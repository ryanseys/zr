# frozen_string_literal: true

# The reach into C the port stands on, over the kernel's calls
# (rt/kernel/ffi.rb): dlopen and dlsym, a call through an address with
# up to eight integer or pointer arguments, or through libffi with more,
# raw memory by address, and the kernel's callback entries. This is the one file of the port
# that names Primitive.
module OpenSSL
  module Native
    # dlopen's mode: every symbol bound now, and none of them seen by a
    # later dlopen's lookups.
    RTLD_NOW = 2
    RTLD_LOCAL = RUBY_PLATFORM.include?("darwin") ? 4 : 0
    # sizeof(ffi_cif), and FFI_DEFAULT_ABI.
    CIF_SIZE = 40
    DEFAULT_ABI = 1

    class << self
      # The handle of the image at `path`, or nil.
      def open(path) = Primitive.zr_ffi_dlopen(path, RTLD_NOW | RTLD_LOCAL)

      # Why the last open failed.
      def error = Primitive.zr_ffi_dlerror

      # The address of `name` in the image of `handle`, or 0.
      def symbol(handle, name) = Primitive.zr_ffi_dlsym(handle, name)

      # The function at `address` called with `words`, Integers in the
      # signed 64-bit range: x0 as a signed Integer.
      def call(address, words) = Primitive.zr_c_call(address, words)

      # #call, answering [x0, errno].
      def call_errno(address, words) = Primitive.zr_c_call_errno(address, words)

      # #call for a function that also takes `float`, a double, as its
      # last argument.
      def call_double(address, words, float) = Primitive.zr_c_call_f64(address, words, float)

      # #call for a function of more than eight arguments, whose last ones
      # go on the stack, where each takes its own width: libffi places
      # them. `widths` gives each argument's, 32 or 64 bits.
      def call_wide(address, widths, words)
        types = widths.map { |bits| Primitive.zr_ffi_type(bits == 32 ? "ffi_type_sint32" : "ffi_type_sint64") }.pack("J*")
        cif = "\0".b * CIF_SIZE
        status = Primitive.zr_ffi_prep(address(cif), DEFAULT_ABI, -1, words.size, Primitive.zr_ffi_type("ffi_type_sint64"), address(types))
        raise ArgumentError, "ffi_prep_cif answered #{status}" unless status.zero?

        values = words.pack("q*")
        pointers = Array.new(words.size) { |i| address(values) + (8 * i) }.pack("J*")
        result = "\0".b * 8
        Primitive.zr_ffi_call(address(cif), address, address(result), address(pointers))
        result.unpack1("q")
      end

      # Where `string` keeps its bytes, which end in a NUL, for C to read
      # or write while the String stays as it is.
      def address(string) = Primitive.zr_ffi_str_addr(string)

      # A String argument C reads up to its NUL.
      alias cstring address

      # `length` bytes at `address`, in binary.
      def read(address, length) = Primitive.zr_ffi_read(address, length)

      # How many bytes at `address` come before a NUL.
      def strlen(address) = Primitive.zr_ffi_strlen(address, nil)

      # `string`'s bytes written at `address`.
      def write(address, string) = Primitive.zr_ffi_write(address, string, 0, string.bytesize)

      # The address of callback entry `index`, which runs the callable
      # #dispatch set with the entry's index and its arguments.
      def callback(index) = Primitive.zr_c_callback_addr(index)

      def dispatch(callable) = Primitive.zr_c_callback_set(callable)

      # State kept on `object` under `key` that no Ruby name reaches, as
      # CRuby's C keeps a TypedData pointer and its ivars without an @.
      def hidden_get(object, key) = Primitive.zr_hidden_get(object, key)

      def hidden_set(object, key, value) = Primitive.zr_state_set(object, key, value)

      # An instance of `klass` as its allocator makes one, even where
      # #undef_allocator took `allocate` and `new` away from programs.
      def allocate(klass) = Primitive.zr_obj_alloc(klass)

      # Whether a frame at `path` is the port's own, which the C
      # extension has no frame for.
      def internal_path?(path) = path.start_with?(File.dirname(__dir__))

      # rb_undef_alloc_func.
      def undef_allocator(klass) = Primitive.zr_undef_allocator(klass)
    end
  end
  private_constant :Native
end
