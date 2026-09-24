# frozen_string_literal: true

# ossl_bio.c: a String as a memory BIO for the library to read, and a
# memory BIO's bytes as a String.
module OpenSSL
  Lib.attach_all(
    BIO_new: [%i[pointer], :pointer],
    BIO_new_mem_buf: [%i[buffer int], :pointer],
    BIO_s_mem: [[], :pointer],
    BIO_new_file: [%i[string string], :pointer],
    BIO_free: [%i[pointer], :int],
    BIO_ctrl: [%i[pointer int long pointer], :long],
    BIO_write: [%i[pointer buffer int], :int],
    BIO_read: [%i[pointer buffer int], :int],
    BIO_test_flags: [%i[pointer int], :int],
    OPENSSL_sk_num: [%i[pointer], :int],
    OPENSSL_sk_value: [%i[pointer int], :pointer],
    OPENSSL_sk_new_null: [[], :pointer],
    OPENSSL_sk_push: [%i[pointer pointer], :int],
    OPENSSL_sk_pop: [%i[pointer], :pointer],
    OPENSSL_sk_free: [%i[pointer], :void],
    OPENSSL_sk_pop_free: [%i[pointer pointer], :void]
  )

  module Lib
    BIO_CTRL_RESET = 1 # bio.h
    BIO_C_GET_BUF_MEM_PTR = 115 # bio.h

    # BIO_get_mem_ptr (bio.h): the BUF_MEM behind a memory BIO, into the
    # pointer buffer `out`.
    def self.BIO_get_mem_ptr(bio, out) = BIO_ctrl(bio, BIO_C_GET_BUF_MEM_PTR, 0, Native.address(out))

    # BIO_reset (bio.h).
    def self.BIO_reset(bio) = RETURNS[:int].(BIO_ctrl(bio, BIO_CTRL_RESET, 0, nil))

    # The address of a function the library frees with, to hand it back
    # as a pointer: sk_X509_pop_free(sk, X509_free).
    def self.function_address(name) = Native.symbol(@handle, name.to_s)
  end

  module Ossl
    class << self
      # ossl_obj2bio: a read-only memory BIO over `object`'s bytes (a File
      # is read first), and the String that contains those bytes, which the
      # caller keeps while the BIO is in use.
      def obj2bio(object)
        object = object.read if object.is_a?(File)
        object = string_value(object)
        bio = Lib.BIO_new_mem_buf(object, object.bytesize)
        raise error(OpenSSLError, "BIO_new_mem_buf") if bio.zero?

        [bio, object]
      end

      # ossl_membio2str: the bytes in a memory BIO, freeing the BIO.
      def membio2str(bio)
        out = Lib.buffer(8)
        if Lib.BIO_get_mem_ptr(bio, out) <= 0
          Lib.BIO_free(bio)
          raise error(OpenSSLError, "BIO_get_mem_ptr")
        end
        # BUF_MEM: size_t length, char *data, ...
        memory = Lib.pointer_at(out)
        length, data = Lib.read(memory, 16).unpack("JJ")
        Lib.read(data, length)
      ensure
        Lib.BIO_free(bio) if memory
      end

      # A new memory BIO to write into, for membio2str to read.
      def mem_bio
        bio = Lib.BIO_new(Lib.BIO_s_mem)
        raise error(OpenSSLError, "BIO_new") if bio.zero?

        bio
      end

      # The items of an OpenSSL STACK, as addresses.
      def stack_items(stack)
        return [] if stack.zero?

        Array.new(Lib.OPENSSL_sk_num(stack)) { |i| Lib.OPENSSL_sk_value(stack, i) }
      end
    end
  end
end
