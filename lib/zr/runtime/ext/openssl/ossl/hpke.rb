# frozen_string_literal: true

# ossl_hpke.c: OpenSSL::HPKE, hybrid public key encryption (RFC 9180) in
# its base mode. A Suite names the KEM, the KDF and the AEAD; a
# Context::Sender encapsulates a key for a recipient's public key and
# seals with it, and a Context::Receiver decapsulates the key with the
# private key and opens.
module OpenSSL
  # OSSL_HPKE_SUITE is three uint16_t that the library takes by value,
  # which the C calling conventions pass as one integer register: the
  # three IDs packed low to high.
  Lib.attach_all(
    OSSL_HPKE_CTX_new: [%i[int ulong int pointer pointer], :pointer],
    OSSL_HPKE_CTX_free: [%i[pointer], :void],
    OSSL_HPKE_suite_check: [%i[ulong], :int],
    OSSL_HPKE_str2suite: [%i[string buffer], :int],
    OSSL_HPKE_get_public_encap_size: [%i[ulong], :size_t],
    OSSL_HPKE_get_ciphertext_size: [%i[ulong size_t], :size_t],
    OSSL_HPKE_keygen: [%i[ulong buffer buffer buffer pointer size_t pointer pointer], :int],
    OSSL_HPKE_encap: [%i[pointer buffer buffer buffer size_t buffer size_t], :int],
    OSSL_HPKE_seal: [%i[pointer buffer buffer buffer size_t buffer size_t], :int],
    OSSL_HPKE_decap: [%i[pointer buffer size_t pointer buffer size_t], :int],
    OSSL_HPKE_open: [%i[pointer buffer buffer buffer size_t buffer size_t], :int],
    OSSL_HPKE_export: [%i[pointer buffer size_t buffer size_t], :int]
  )

  module Lib
    OSSL_HPKE_MODE_BASE = 0
    OSSL_HPKE_ROLE_SENDER = 0
    OSSL_HPKE_ROLE_RECEIVER = 1
  end

  module HPKE
    class HPKEError < OpenSSLError; end

    class Context
      class Sender < Context; end

      class Receiver < Context; end
    end
  end

  module Ossl
    HPKE_CTX = DataType.new("OpenSSL/HPKE_CTX", HPKE::Context, :OSSL_HPKE_CTX_free, [RuntimeError, "OSSL_HPKE_CTX wasn't initialized!"])

    # As RFC 9180 section 7.1 has it, no KEM's public key is longer.
    HPKE_MAX_PUBLIC_KEY = 133

    class << self
      # GetHpkeSuite: the suite's IDs packed as the library takes them.
      def hpke_suite(suite)
        unless suite.is_a?(HPKE::Suite)
          raise TypeError, "wrong argument type #{conversion_name(suite)} (expected OpenSSL/HPKE_SUITE)"
        end

        ids = Native.hidden_get(suite, :suite) or raise RuntimeError, "OSSL_HPKE_SUITE wasn't initialized!"
        ids[0] | (ids[1] << 16) | (ids[2] << 32)
      end

      # ossl_hpke_suite_id: an ID of 16 bits.
      def hpke_suite_id(value, label)
        id = long(value)
        raise HPKE::HPKEError, "#{label} id out of range (0..0xFFFF): #{id}" unless id.between?(0, 0xFFFF)

        id
      end

      # ossl_hpke_ctx_new_sender and _receiver.
      def hpke_context(context, suite, role)
        want_uninitialized(context, HPKE_CTX)
        raise error(HPKE::HPKEError, "invalid suite specified") unless suite.is_a?(HPKE::Suite)

        ctx = Lib.OSSL_HPKE_CTX_new(Lib::OSSL_HPKE_MODE_BASE, hpke_suite(suite), role, nil, nil)
        raise error(HPKE::HPKEError, "could not create ctx") if ctx.zero?

        HPKE_CTX.set(context, ctx)
        Native.hidden_set(context, :suite, hpke_suite(suite))
        context
      end
    end
  end

  module HPKE
    # ossl_hpke_keygen: a new key pair for the suite's KEM.
    def self.keygen(suite)
      raise Ossl.error(HPKEError, "invalid suite specified") unless suite.is_a?(Suite)

      packed = Ossl.hpke_suite(suite)
      public_key = Lib.buffer(Ossl::HPKE_MAX_PUBLIC_KEY)
      length = [Ossl::HPKE_MAX_PUBLIC_KEY].pack("J")
      pkey = Lib.buffer(8)
      raise Ossl.error(HPKEError, "could not keygen") if Lib.OSSL_HPKE_keygen(packed, public_key, length, pkey, nil, 0, nil, nil).zero?

      Ossl.pkey_wrap(Lib.pointer_at(pkey))
    end

    class Suite
      # The IDs as Integers, or the names that OSSL_HPKE_str2suite reads.
      # A suite cannot change, so it is frozen.
      def initialize(kem, kdf, aead)
        raise TypeError, "#{self.class} already initialized" if Native.hidden_get(self, :suite)

        Ossl.check_frozen(self)
        ids = if [kem, kdf, aead].all?(Integer)
                [Ossl.hpke_suite_id(kem, "KEM"), Ossl.hpke_suite_id(kdf, "KDF"), Ossl.hpke_suite_id(aead, "AEAD")].tap do |found|
                  unless Lib.OSSL_HPKE_suite_check(found[0] | (found[1] << 16) | (found[2] << 32)) == 1
                    raise Ossl.error(HPKEError, format("unsupported HPKE suite: kem=0x%04x kdf=0x%04x aead=0x%04x", *found))
                  end
                end
              else
                text = "#{kem},#{kdf},#{aead}"
                out = Lib.buffer(8)
                raise Ossl.error(HPKEError, "unsupported HPKE suite: #{text}") unless Lib.OSSL_HPKE_str2suite(Ossl.cstring_value(text), out) == 1

                out.unpack("S3")
              end
        Native.hidden_set(self, :suite, ids)
        freeze
      end

      def kem_id = ids[0]
      def kdf_id = ids[1]
      def aead_id = ids[2]

      private

      def ids = Native.hidden_get(self, :suite) || raise(RuntimeError, "OSSL_HPKE_SUITE wasn't initialized!")
    end

    class Context
      # ossl_hpke_export: `length` bytes of secret for `label`.
      def export(length, label)
        out_length = Ossl.int(length)
        label = Ossl.string_value(label)
        raise ArgumentError, "negative string size (or size too big)" if out_length.negative?

        out = Lib.buffer(out_length)
        ctx = Ossl::HPKE_CTX.fetch(self)
        raise Ossl.error(HPKEError, "could not export") unless Lib.OSSL_HPKE_export(ctx, out, out_length, label, label.bytesize) == 1

        out
      end

      class Sender
        def initialize(suite) = Ossl.hpke_context(self, suite, Lib::OSSL_HPKE_ROLE_SENDER)

        # The encapsulated key for the recipient's public key `public_key`.
        def encap(public_key, info)
          ctx = Ossl::HPKE_CTX.fetch(self)
          public_key = Ossl.string_value(public_key)
          info = Ossl.string_value(info)
          size = Lib.OSSL_HPKE_get_public_encap_size(Native.hidden_get(self, :suite))
          out = Lib.buffer(size)
          length = [size].pack("J")
          unless Lib.OSSL_HPKE_encap(ctx, out, length, public_key, public_key.bytesize, info, info.bytesize) == 1
            raise Ossl.error(HPKEError, "could not encap")
          end

          out.byteslice(0, length.unpack1("J"))
        end

        def seal(aad, plaintext)
          ctx = Ossl::HPKE_CTX.fetch(self)
          aad = Ossl.string_value(aad)
          plaintext = Ossl.string_value(plaintext)
          size = Lib.OSSL_HPKE_get_ciphertext_size(Native.hidden_get(self, :suite), plaintext.bytesize)
          out = Lib.buffer(size)
          length = [size].pack("J")
          unless Lib.OSSL_HPKE_seal(ctx, out, length, aad, aad.bytesize, plaintext, plaintext.bytesize) == 1
            raise Ossl.error(HPKEError, "could not seal")
          end

          out
        end
      end

      class Receiver
        def initialize(suite) = Ossl.hpke_context(self, suite, Lib::OSSL_HPKE_ROLE_RECEIVER)

        # Takes the key that `encapsulated` holds with the private key
        # `private_key`.
        def decap(encapsulated, private_key, info) # rubocop:disable Naming/PredicateMethod -- ruby's name, which answers true
          ctx = Ossl::HPKE_CTX.fetch(self)
          pkey = Ossl.pkey(private_key)
          encapsulated = Ossl.string_value(encapsulated)
          info = Ossl.string_value(info)
          unless Lib.OSSL_HPKE_decap(ctx, encapsulated, encapsulated.bytesize, pkey, info, info.bytesize) == 1
            raise Ossl.error(HPKEError, "could not decap")
          end

          true
        end

        def open(aad, ciphertext)
          aad = Ossl.string_value(aad)
          ciphertext = Ossl.string_value(ciphertext)
          out = Lib.buffer(ciphertext.bytesize)
          length = [ciphertext.bytesize].pack("J")
          ctx = Ossl::HPKE_CTX.fetch(self)
          unless Lib.OSSL_HPKE_open(ctx, out, length, aad, aad.bytesize, ciphertext, ciphertext.bytesize) == 1
            raise Ossl.error(HPKEError, "could not open")
          end

          out.byteslice(0, length.unpack1("J"))
        end
      end
    end
  end

  # ossl_hpke.c defines HPKE only where the library has it (OpenSSL 3.2).
  remove_const(:HPKE) unless Lib.respond_to?(:OSSL_HPKE_CTX_new)
end
