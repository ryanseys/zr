# frozen_string_literal: true

# ossl_cipher.c: OpenSSL::Cipher over EVP_CIPHER_CTX.
module OpenSSL
  Lib.attach_all(
    EVP_CIPHER_CTX_new: [[], :pointer],
    EVP_CIPHER_CTX_free: [%i[pointer], :void],
    EVP_CIPHER_CTX_copy: [%i[pointer pointer], :int],
    EVP_CIPHER_CTX_get0_cipher: [%i[pointer], :pointer],
    EVP_CIPHER_CTX_get_key_length: [%i[pointer], :int],
    EVP_CIPHER_CTX_get_iv_length: [%i[pointer], :int],
    EVP_CIPHER_CTX_get_block_size: [%i[pointer], :int],
    EVP_CIPHER_CTX_get_app_data: [%i[pointer], :pointer],
    EVP_CIPHER_CTX_set_app_data: [%i[pointer pointer], :void],
    EVP_CIPHER_CTX_ctrl: [%i[pointer int int pointer], :int],
    EVP_CIPHER_CTX_set_padding: [%i[pointer int], :int],
    EVP_CIPHER_CTX_set_key_length: [%i[pointer int], :int],
    EVP_CIPHER_get_flags: [%i[pointer], :ulong],
    EVP_CIPHER_get0_name: [%i[pointer], :string],
    EVP_CIPHER_up_ref: [%i[pointer], :int],
    EVP_CIPHER_free: [%i[pointer], :void],
    EVP_CIPHER_fetch: [%i[pointer string string], :pointer],
    EVP_get_cipherbyname: [%i[string], :pointer],
    EVP_CipherInit_ex: [%i[pointer pointer pointer buffer buffer int], :int],
    EVP_CipherUpdate: [%i[pointer pointer buffer pointer int], :int],
    EVP_CipherFinal_ex: [%i[pointer buffer buffer], :int],
    EVP_BytesToKey: [%i[pointer pointer buffer buffer int int buffer buffer], :int],
    EVP_md5: [[], :pointer],
    OPENSSL_cleanse: [%i[buffer size_t], :void]
  )

  module Lib
    OBJ_NAME_TYPE_CIPHER_METH = 0x02 # objects.h
    EVP_MAX_KEY_LENGTH = 64 # evp.h
    EVP_MAX_IV_LENGTH = 16 # evp.h
    EVP_MAX_BLOCK_LENGTH = 32 # evp.h
    PKCS5_SALT_LEN = 8 # evp.h
    EVP_CIPH_FLAG_AEAD_CIPHER = 0x200000 # evp.h
    EVP_CTRL_AEAD_SET_IVLEN = 0x9 # evp.h
    EVP_CTRL_AEAD_GET_TAG = 0x10 # evp.h
    EVP_CTRL_AEAD_SET_TAG = 0x11 # evp.h
  end

  class Cipher
    class CipherError < OpenSSLError; end
    class AuthTagError < CipherError; end
  end

  module Ossl
    CIPHER = DataType.new("OpenSSL/Cipher", Cipher, :EVP_CIPHER_CTX_free, [RuntimeError, "Cipher not initialized!"])

    class << self
      # ossl_evp_cipher_fetch: the EVP_CIPHER `object` names (a Cipher, or
      # an algorithm's name), and the handle that keeps a fetched one alive
      # while the caller uses it.
      def fetch_cipher(object)
        if object.is_a?(Cipher)
          cipher = Lib.EVP_CIPHER_CTX_get0_cipher(CIPHER.fetch(object))
          raise error(Cipher::CipherError, "EVP_CIPHER_up_ref") if Lib.EVP_CIPHER_up_ref(cipher) != 1

          return [cipher, Handle.new(cipher, :EVP_CIPHER_free)]
        end

        name = cstring_value(object)
        cipher = Lib.EVP_get_cipherbyname(name)
        holder = nil
        if cipher.zero?
          clear_error
          cipher = Lib.EVP_CIPHER_fetch(nil, name, nil)
          holder = Handle.new(cipher, :EVP_CIPHER_free) unless cipher.zero?
        end
        raise error(Cipher::CipherError, "unsupported cipher algorithm: #{object}") if cipher.zero?

        [cipher, holder]
      end

      # AllocCipher.
      def alloc_cipher(object)
        ctx = Lib.EVP_CIPHER_CTX_new
        raise error(RuntimeError) if ctx.zero?

        CIPHER.set(object, ctx)
      end

      # EVP_CIPHER_flags(EVP_CIPHER_CTX_cipher(ctx)) & EVP_CIPH_FLAG_AEAD_CIPHER.
      def aead?(ctx) = Lib.EVP_CIPHER_get_flags(Lib.EVP_CIPHER_CTX_get0_cipher(ctx)) & Lib::EVP_CIPH_FLAG_AEAD_CIPHER != 0

      # ossl_cipher_init.
      def cipher_init(cipher, enc)
        raise error(Cipher::CipherError, "EVP_CipherInit_ex") if Lib.EVP_CipherInit_ex(CIPHER.fetch(cipher), nil, nil, nil, nil, enc) != 1

        Native.hidden_set(cipher, :key_set, false)
        cipher
      end

      # The IV length iv_len= set for an AEAD cipher, else the cipher's own.
      def cipher_iv_length(ctx)
        length = aead?(ctx) ? Lib.EVP_CIPHER_CTX_get_app_data(ctx) : 0
        length.zero? ? Lib.EVP_CIPHER_CTX_get_iv_length(ctx) : length
      end

      # ossl_cipher_update_long: `length` bytes at `input` through
      # EVP_CipherUpdate in parts an int can count, into `output` (an
      # address, or nil for additional authenticated data); the bytes
      # written, or nil when the library fails.
      def cipher_update(ctx, output, input, length)
        limit = 0x7fff_ffff / 2 + 1
        written = 0
        part = Lib.buffer(4)
        loop do
          size = [length, limit].min
          return nil if Lib.EVP_CipherUpdate(ctx, output && output + written, part, input, size).zero?

          written += part.unpack1("l")
          input += size
          length -= limit
          break unless length.positive?
        end
        written
      end
    end
  end

  class Cipher
    def initialize(str)
      Ossl.want_uninitialized(self, Ossl::CIPHER)

      cipher, holder = Ossl.fetch_cipher(str)
      ctx = Ossl.alloc_cipher(self)
      raise Ossl.error(CipherError, "EVP_CipherInit_ex") if Lib.EVP_CipherInit_ex(ctx, cipher, nil, nil, nil, -1) != 1

      Native.hidden_set(self, :cipher_holder, holder)
      self
    end

    def initialize_copy(other)
      Ossl::CIPHER.unshare(self, other) unless equal?(other)
      Ossl.want_uninitialized(self, Ossl::CIPHER)
      ctx = Ossl.alloc_cipher(self)
      raise Ossl.error(CipherError) if Lib.EVP_CIPHER_CTX_copy(ctx, Ossl::CIPHER.fetch(other)) != 1

      self
    end

    def self.ciphers = Ossl.names(Lib::OBJ_NAME_TYPE_CIPHER_METH)

    private def ciphers = Cipher.ciphers

    def reset
      raise Ossl.error(CipherError) if Lib.EVP_CipherInit_ex(Ossl::CIPHER.fetch(self), nil, nil, nil, nil, -1) != 1

      self
    end

    def encrypt = Ossl.cipher_init(self, 1)

    def decrypt = Ossl.cipher_init(self, 0)

    def pkcs5_keyivgen(pass, salt = nil, iterations = nil, digest = nil)
      pass = Ossl.string_value(pass)
      unless salt.nil?
        salt = Ossl.string_value(salt)
        raise Ossl.error(CipherError, "salt must be an 8-octet string") if salt.bytesize != Lib::PKCS5_SALT_LEN
      end
      iterations = iterations.nil? ? 2048 : Ossl.int(iterations)
      raise ArgumentError, "iterations must be a positive integer" if iterations <= 0

      md, _holder = digest.nil? ? [Lib.EVP_md5, nil] : Ossl.fetch_md(digest)
      ctx = Ossl::CIPHER.fetch(self)
      key = Lib.buffer(Lib::EVP_MAX_KEY_LENGTH)
      iv = Lib.buffer(Lib::EVP_MAX_IV_LENGTH)
      Lib.EVP_BytesToKey(Lib.EVP_CIPHER_CTX_get0_cipher(ctx), md, salt, pass, pass.bytesize, iterations, key, iv)
      begin
        raise Ossl.error(CipherError) if Lib.EVP_CipherInit_ex(ctx, nil, nil, key, iv, -1) != 1
      ensure
        Lib.OPENSSL_cleanse(key, key.bytesize)
        Lib.OPENSSL_cleanse(iv, iv.bytesize)
      end
      Native.hidden_set(self, :key_set, true)
      nil
    end

    def update(data, buffer = nil)
      raise Ossl.error(CipherError, "key not set") unless Native.hidden_get(self, :key_set)

      data = Ossl.string_value(data)
      ctx = Ossl::CIPHER.fetch(self)
      length = data.bytesize
      raise Ossl.error(RangeError, "data too big to make output buffer: #{length} bytes") if length > (1 << 63) - 1 - Lib::EVP_MAX_BLOCK_LENGTH

      buffer = Ossl.string_value(buffer).tap { |b| Ossl.check_frozen(b) } unless buffer.nil?
      out = Lib.buffer(length + Lib::EVP_MAX_BLOCK_LENGTH)
      written = Ossl.cipher_update(ctx, Native.address(out), Native.address(data), length)
      raise Ossl.error(CipherError, "EVP_CipherUpdate") if written.nil?

      out = out.byteslice(0, written)
      return out if buffer.nil?

      buffer.replace(out.force_encoding(buffer.encoding))
    end

    def final
      ctx = Ossl::CIPHER.fetch(self)
      out = Lib.buffer(Lib.EVP_CIPHER_CTX_get_block_size(ctx))
      written = Lib.buffer(4)
      if Lib.EVP_CipherFinal_ex(ctx, out, written).zero?
        raise Ossl.error(AuthTagError, "AEAD authentication tag verification failed") if Ossl.aead?(ctx)

        raise Ossl.error(CipherError, "cipher final failed")
      end
      out.byteslice(0, written.unpack1("l"))
    end

    def name = Lib.EVP_CIPHER_get0_name(Lib.EVP_CIPHER_CTX_get0_cipher(Ossl::CIPHER.fetch(self)))

    def key=(key)
      key = Ossl.string_value(key)
      ctx = Ossl::CIPHER.fetch(self)
      length = Lib.EVP_CIPHER_CTX_get_key_length(ctx)
      raise Ossl.error(ArgumentError, "key must be #{length} bytes") if key.bytesize != length
      raise Ossl.error(CipherError) if Lib.EVP_CipherInit_ex(ctx, nil, nil, key, nil, -1) != 1

      Native.hidden_set(self, :key_set, true)
      key
    end

    def iv=(iv)
      iv = Ossl.string_value(iv)
      ctx = Ossl::CIPHER.fetch(self)
      length = Ossl.cipher_iv_length(ctx)
      raise Ossl.error(ArgumentError, "iv must be #{length} bytes") if iv.bytesize != length
      raise Ossl.error(CipherError) if Lib.EVP_CipherInit_ex(ctx, nil, nil, nil, iv, -1) != 1

      iv
    end

    def authenticated? = Ossl.aead?(Ossl::CIPHER.fetch(self))

    def auth_data=(data)
      data = Ossl.string_value(data)
      ctx = Ossl::CIPHER.fetch(self)
      raise Ossl.error(CipherError, "AEAD not supported by this cipher") unless Ossl.aead?(ctx)
      raise Ossl.error(CipherError, "couldn't set additional authenticated data") if Ossl.cipher_update(ctx, nil, Native.address(data), data.bytesize).nil?

      data
    end

    def auth_tag(tag_len = nil)
      tag_len = Native.hidden_get(self, :auth_tag_len) if tag_len.nil?
      tag_len = tag_len.nil? ? 16 : Ossl.int(tag_len)
      ctx = Ossl::CIPHER.fetch(self)
      raise Ossl.error(CipherError, "authentication tag not supported by this cipher") unless Ossl.aead?(ctx)

      tag = Lib.buffer(tag_len)
      raise Ossl.error(CipherError, "retrieving the authentication tag failed") if Lib.EVP_CIPHER_CTX_ctrl(ctx, Lib::EVP_CTRL_AEAD_GET_TAG, tag_len, Native.address(tag)).zero?

      tag
    end

    def auth_tag=(tag)
      tag = Ossl.string_value(tag)
      ctx = Ossl::CIPHER.fetch(self)
      raise Ossl.error(CipherError, "authentication tag not supported by this cipher") unless Ossl.aead?(ctx)
      raise Ossl.error(CipherError, "unable to set AEAD tag") if Lib.EVP_CIPHER_CTX_ctrl(ctx, Lib::EVP_CTRL_AEAD_SET_TAG, tag.bytesize, Native.address(tag)).zero?

      tag
    end

    def auth_tag_len=(length)
      tag_len = Ossl.int(length)
      ctx = Ossl::CIPHER.fetch(self)
      raise Ossl.error(CipherError, "AEAD not supported by this cipher") unless Ossl.aead?(ctx)
      raise Ossl.error(CipherError, "unable to set authentication tag length") if Lib.EVP_CIPHER_CTX_ctrl(ctx, Lib::EVP_CTRL_AEAD_SET_TAG, tag_len, nil).zero?

      Native.hidden_set(self, :auth_tag_len, tag_len)
      length
    end

    def key_len=(key_length)
      length = Ossl.int(key_length)
      raise Ossl.error(CipherError) if Lib.EVP_CIPHER_CTX_set_key_length(Ossl::CIPHER.fetch(self), length) != 1

      key_length
    end

    def key_len = Lib.EVP_CIPHER_CTX_get_key_length(Ossl::CIPHER.fetch(self))

    def iv_len=(iv_length)
      length = Ossl.int(iv_length)
      ctx = Ossl::CIPHER.fetch(self)
      raise Ossl.error(CipherError, "cipher does not support AEAD") unless Ossl.aead?(ctx)
      raise Ossl.error(CipherError, "unable to set IV length") if Lib.EVP_CIPHER_CTX_ctrl(ctx, Lib::EVP_CTRL_AEAD_SET_IVLEN, length, nil).zero?

      # The C extension keeps the length in the context's app data, where
      # iv_len and iv= find it.
      Lib.EVP_CIPHER_CTX_set_app_data(ctx, length)
      iv_length
    end

    def iv_len = Ossl.cipher_iv_length(Ossl::CIPHER.fetch(self))

    def block_size = Lib.EVP_CIPHER_CTX_get_block_size(Ossl::CIPHER.fetch(self))

    def padding=(padding)
      pad = Ossl.int(padding)
      raise Ossl.error(CipherError) if Lib.EVP_CIPHER_CTX_set_padding(Ossl::CIPHER.fetch(self), pad) != 1

      padding
    end

    def ccm_data_len=(data_len)
      length = Ossl.int(data_len)
      ctx = Ossl::CIPHER.fetch(self)
      raise Ossl.error(CipherError) if Lib.EVP_CipherUpdate(ctx, nil, Lib.buffer(4), nil, length) != 1

      data_len
    end
  end
end
