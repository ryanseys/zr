# frozen_string_literal: true

# LastError.c: the errno each thread's last C call left, kept apart from
# errno itself, which ruby's own calls change.
module FFI
  module LastError
    module_function

    def error = Primitive.zr_hidden_get(Thread.current, :ffi_errno) || 0

    def error=(value)
      Primitive.zr_ffi_set_errno(FFI.int_value(value))
      nil
    end

    # rbffi_save_errno.
    def save(errno)
      Primitive.attr! :hidden
      Primitive.zr_hidden_set(Thread.current, :ffi_errno, errno)
    end
  end
end
