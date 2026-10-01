# frozen_string_literal: true

# ossl_pkey.c: OpenSSL::PKey and PKey::PKey over EVP_PKEY: reading any
# key the library decodes, generating keys and parameters, and signing,
# verifying, deriving, encrypting and decrypting with them.
module OpenSSL
  Lib.attach_all(
    EVP_PKEY_new: [[], :pointer],
    EVP_PKEY_up_ref: [%i[pointer], :int],
    EVP_PKEY_dup: [%i[pointer], :pointer],
    EVP_PKEY_get_base_id: [%i[pointer], :int],
    EVP_PKEY_get_id: [%i[pointer], :int],
    EVP_PKEY_get_size: [%i[pointer], :int],
    EVP_PKEY_get0_type_name: [%i[pointer], :string],
    EVP_PKEY_get0_provider: [%i[pointer], :pointer],
    EVP_PKEY_missing_parameters: [%i[pointer], :int],
    EVP_PKEY_eq: [%i[pointer pointer], :int],
    EVP_PKEY_print_private: [%i[pointer pointer int pointer], :int],
    EVP_PKEY_print_public: [%i[pointer pointer int pointer], :int],
    EVP_PKEY_print_params: [%i[pointer pointer int pointer], :int],
    EVP_PKEY_new_raw_private_key_ex: [%i[pointer string pointer buffer size_t], :pointer],
    EVP_PKEY_new_raw_public_key_ex: [%i[pointer string pointer buffer size_t], :pointer],
    EVP_PKEY_get_raw_private_key: [%i[pointer buffer buffer], :int],
    EVP_PKEY_get_raw_public_key: [%i[pointer buffer buffer], :int],
    EVP_PKEY_CTX_new: [%i[pointer pointer], :pointer],
    EVP_PKEY_CTX_new_from_name: [%i[pointer string pointer], :pointer],
    EVP_PKEY_CTX_ctrl_str: [%i[pointer string string], :int],
    EVP_PKEY_CTX_set_app_data: [%i[pointer pointer], :void],
    EVP_PKEY_CTX_get_app_data: [%i[pointer], :pointer],
    EVP_PKEY_CTX_set_cb: [%i[pointer pointer], :void],
    EVP_PKEY_CTX_get_keygen_info: [%i[pointer int], :int],
    EVP_PKEY_CTX_set_signature_md: [%i[pointer pointer], :int],
    EVP_PKEY_paramgen_init: [%i[pointer], :int],
    EVP_PKEY_keygen_init: [%i[pointer], :int],
    EVP_PKEY_paramgen: [%i[pointer buffer], :int],
    EVP_PKEY_keygen: [%i[pointer buffer], :int],
    EVP_PKEY_sign_init: [%i[pointer], :int],
    EVP_PKEY_sign: [%i[pointer buffer buffer buffer size_t], :int],
    EVP_PKEY_verify_init: [%i[pointer], :int],
    EVP_PKEY_verify: [%i[pointer buffer size_t buffer size_t], :int],
    EVP_PKEY_verify_recover_init: [%i[pointer], :int],
    EVP_PKEY_verify_recover: [%i[pointer buffer buffer buffer size_t], :int],
    EVP_PKEY_derive_set_peer: [%i[pointer pointer], :int],
    EVP_PKEY_encrypt_init: [%i[pointer], :int],
    EVP_PKEY_encrypt: [%i[pointer buffer buffer buffer size_t], :int],
    EVP_PKEY_decrypt_init: [%i[pointer], :int],
    EVP_PKEY_decrypt: [%i[pointer buffer buffer buffer size_t], :int],
    EVP_PKEY_check: [%i[pointer], :int],
    EVP_PKEY_public_check: [%i[pointer], :int],
    EVP_PKEY_param_check: [%i[pointer], :int],
    EVP_DigestSign: [%i[pointer buffer buffer buffer size_t], :int],
    EVP_DigestVerifyInit: [%i[pointer buffer pointer pointer pointer], :int],
    EVP_DigestVerify: [%i[pointer buffer size_t buffer size_t], :int],
    OSSL_DECODER_CTX_new_for_pkey: [%i[buffer string pointer pointer int pointer pointer], :pointer],
    OSSL_DECODER_CTX_set_pem_password_cb: [%i[pointer pointer pointer], :int],
    OSSL_DECODER_from_bio: [%i[pointer pointer], :int],
    OSSL_DECODER_CTX_free: [%i[pointer], :void],
    i2d_PrivateKey_bio: [%i[pointer pointer], :int],
    i2d_PKCS8PrivateKey_bio: [%i[pointer pointer pointer pointer int pointer pointer], :int],
    i2d_PUBKEY_bio: [%i[pointer pointer], :int],
    PEM_write_bio_PrivateKey_traditional: [%i[pointer pointer pointer pointer int pointer pointer], :int],
    PEM_write_bio_PKCS8PrivateKey: [%i[pointer pointer pointer pointer int pointer pointer], :int],
    PEM_write_bio_PUBKEY: [%i[pointer pointer], :int],
    OBJ_sn2nid: [%i[string], :int]
  )

  module Lib
    EVP_PKEY_RSA = 6 # evp.h: NID_rsaEncryption
    EVP_PKEY_DSA = 116 # NID_dsa
    EVP_PKEY_DH = 28 # NID_dhKeyAgreement
    EVP_PKEY_EC = 408 # NID_X9_62_id_ecPublicKey
    EVP_PKEY_KEYMGMT = -1
    # evp.h's selections, over core_dispatch.h's OSSL_KEYMGMT_SELECT_*.
    EVP_PKEY_KEY_PARAMETERS = 0x84
    EVP_PKEY_PUBLIC_KEY = 0x86
    EVP_PKEY_KEYPAIR = 0x87
    BIO_CTRL_EOF = 2 # bio.h
    BIO_C_FILE_TELL = 133

    # BIO_eof (bio.h).
    def self.BIO_eof(bio) = RETURNS[:int].(BIO_ctrl(bio, BIO_CTRL_EOF, 0, nil))

    # BIO_tell (bio.h).
    def self.BIO_tell(bio) = RETURNS[:int].(BIO_ctrl(bio, BIO_C_FILE_TELL, 0, nil))
  end

  module PKey
    class PKeyError < OpenSSLError; end

    class PKey; end
  end

  module Ossl
    PKEY = DataType.new("OpenSSL/EVP_PKEY", PKey::PKey, :EVP_PKEY_free, [RuntimeError, "PKEY wasn't initialized!"])

    class << self
      # ossl_pkey_wrap: `pkey` in an instance of the class its type has,
      # which owns it from here.
      def pkey_wrap(pkey)
        klass = case Lib.EVP_PKEY_get_base_id(pkey)
                when Lib::EVP_PKEY_RSA then PKey::RSA
                when Lib::EVP_PKEY_DSA then PKey::DSA
                when Lib::EVP_PKEY_DH then PKey::DH
                when Lib::EVP_PKEY_EC then PKey::EC
                else PKey::PKey
                end
        PKEY.wrap(klass, pkey)
      rescue Exception # rubocop:disable Lint/RescueException
        Lib.EVP_PKEY_free(pkey)
        raise
      end

      # OSSL_BIO_reset.
      def bio_reset(bio)
        Lib.BIO_reset(bio)
        clear_error
      end

      # ossl_pkey_read: one decoder pass over the BIO, for one input type
      # and selection; the EVP_PKEY, or nil.
      def pkey_read(bio, input_type, selection, password)
        out = Lib.buffer(8)
        dctx = Lib.OSSL_DECODER_CTX_new_for_pkey(out, input_type, nil, nil, selection, nil, nil)
        begin
          return nil if dctx.zero?
          return nil if selection == Lib::EVP_PKEY_KEYPAIR && Lib.OSSL_DECODER_CTX_set_pem_password_cb(dctx, PEM_PASSWORD_CB, password) != 1

          position = 0
          loop do
            break if Lib.OSSL_DECODER_from_bio(dctx, bio) == 1
            break unless Lib.BIO_eof(bio).zero?

            now = Lib.BIO_tell(bio)
            break if now.negative? || now <= position

            clear_error
            position = now
          end
        ensure
          bio_reset(bio)
          Lib.OSSL_DECODER_CTX_free(dctx) unless dctx.nil? || dctx.zero?
        end
        pkey = Lib.pointer_at(out)
        pkey.zero? ? nil : pkey
      end

      # ossl_pkey_read_generic: DER, then PEM, each as a key pair, as
      # parameters, then as a public key. `password` is the Integer
      # with_password gives, so PEM_PASSWORD_CB finds the password.
      def pkey_read_generic(bio, password)
        %w[DER PEM].each do |input_type|
          [Lib::EVP_PKEY_KEYPAIR, Lib::EVP_PKEY_KEY_PARAMETERS, Lib::EVP_PKEY_PUBLIC_KEY].each do |selection|
            pkey = pkey_read(bio, input_type, selection, password)
            return pkey if pkey
          end
        end
        nil
      end

      # GetPKeyPtr.
      def pkey(object) = PKEY.fetch(object)

      # GetPrivPKeyPtr.
      def private_pkey(object)
        pkey = PKEY.fetch(object)
        return pkey if Native.hidden_get(object, :private) == true
        return pkey unless object.respond_to?(:private?)
        return pkey if object.private?

        raise ArgumentError, "private key is needed"
      end

      # DupPKeyPtr.
      def dup_pkey(object)
        pkey = PKEY.fetch(object)
        Lib.EVP_PKEY_up_ref(pkey)
        pkey
      end

      # ossl_pkey_check_public_key.
      def check_public_key(pkey)
        raise error(PKey::PKeyError, "parameters missing") unless Lib.EVP_PKEY_missing_parameters(pkey).zero?
      end

      # pkey_ctx_apply_options: each pair of `options` through
      # EVP_PKEY_CTX_ctrl_str.
      def apply_pkey_options(ctx, options)
        raise TypeError, "wrong argument type #{type_name(options)} (expected Hash)" unless options.is_a?(Hash)

        options.each do |key, value|
          key = key.to_s if key.is_a?(Symbol)
          value = Kernel.String(value)
          if Lib.EVP_PKEY_CTX_ctrl_str(ctx, cstring_value(key), cstring_value(value)) <= 0
            raise error(PKey::PKeyError, "EVP_PKEY_CTX_ctrl_str(ctx, #{key.inspect}, #{value.inspect})")
          end
        end
      end

      # Runs `yield` on a new EVP_PKEY_CTX, which is freed afterwards.
      def with_pkey_ctx(ctx)
        yield ctx
      ensure
        Lib.EVP_PKEY_CTX_free(ctx)
      end

      # The bytes that a function fills in two calls, the first for the
      # length and the second for the bytes. `yield` gets the buffer (nil
      # first) and the length buffer, and returns whether the call worked.
      # `too_large` is the message for a length past the maximum String size.
      def sized_output(error_class, message, too_large = nil)
        length = Lib.buffer(8)
        raise error(error_class, message) unless yield(nil, length)

        size = length.unpack1("J")
        raise error_class, too_large if too_large && size > (1 << 63) - 1

        out = Lib.buffer(size)
        raise error(error_class, message) unless yield(out, length)

        out.byteslice(0, length.unpack1("J"))
      end

      # pkey_generate.
      def pkey_generate(alg, options, generate_parameters, block)
        ctx = if alg.is_a?(PKey::PKey)
                Lib.EVP_PKEY_CTX_new(PKEY.fetch(alg), nil).tap { |c| raise error(PKey::PKeyError, "EVP_PKEY_CTX_new") if c.zero? }
              else
                Lib.EVP_PKEY_CTX_new_from_name(nil, cstring_value(alg), nil).tap { |c| raise error(PKey::PKeyError, "EVP_PKEY_CTX_new_from_name") if c.zero? }
              end
        state = nil
        pkey = Lib.buffer(8)
        with_pkey_ctx(ctx) do
          if generate_parameters
            raise error(PKey::PKeyError, "EVP_PKEY_paramgen_init") if Lib.EVP_PKEY_paramgen_init(ctx) <= 0
          elsif Lib.EVP_PKEY_keygen_init(ctx) <= 0
            raise error(PKey::PKeyError, "EVP_PKEY_keygen_init")
          end
          apply_pkey_options(ctx, options) unless options.nil?

          if block
            @generations ||= {}
            id = @generation_id = (@generation_id || 0) + 1
            state = @generations[id] = [block, nil]
            Lib.EVP_PKEY_CTX_set_app_data(ctx, id)
            Lib.EVP_PKEY_CTX_set_cb(ctx, KEYGEN_CB)
          end
          begin
            generate_parameters ? Lib.EVP_PKEY_paramgen(ctx, pkey) : Lib.EVP_PKEY_keygen(ctx, pkey)
          ensure
            @generations.delete(id) if id
          end
        end
        pkey = Lib.pointer_at(pkey)
        if pkey.zero?
          if state&.last
            clear_error
            raise state.last
          end
          raise error(PKey::PKeyError, generate_parameters ? "EVP_PKEY_paramgen" : "EVP_PKEY_keygen")
        end
        pkey_wrap(pkey)
      end

      # pkey_gen_cb: the block of the generate call, given the keygen
      # info; an exception it raises stops the generation, and is raised
      # again once the library returns.
      def keygen_progress(ctx)
        state = @generations[Lib.EVP_PKEY_CTX_get_app_data(ctx)]
        info = Array.new(Lib.EVP_PKEY_CTX_get_keygen_info(ctx, -1)) { |i| Lib.EVP_PKEY_CTX_get_keygen_info(ctx, i) }
        state.first.call(*info)
        1
      rescue Exception => e # rubocop:disable Lint/RescueException
        state[1] = e
        0
      end

      # ossl_pkey_export_traditional.
      def pkey_export_traditional(object, to_der, cipher = nil, password = nil)
        pkey = PKEY.fetch(object)
        unless cipher.nil?
          enc, _holder = fetch_cipher(cipher)
          password = pem_password_value(password)
        end
        bio = Lib.BIO_new(Lib.BIO_s_mem)
        raise error(PKey::PKeyError, "BIO_new") if bio.zero?

        if to_der
          if Lib.i2d_PrivateKey_bio(bio, pkey).zero?
            Lib.BIO_free(bio)
            raise error(PKey::PKeyError, "i2d_PrivateKey_bio")
          end
        else
          written = with_password(password, nil) do |id|
            Lib.PEM_write_bio_PrivateKey_traditional(bio, pkey, enc, nil, 0, PEM_PASSWORD_CB, id)
          end
          if written.zero?
            Lib.BIO_free(bio)
            raise error(PKey::PKeyError, "PEM_write_bio_PrivateKey_traditional")
          end
        end
        membio2str(bio)
      end

      # ossl_pkey_export_spki.
      def pkey_export_spki(object, to_der)
        pkey = PKEY.fetch(object)
        check_public_key(pkey)
        bio = Lib.BIO_new(Lib.BIO_s_mem)
        raise error(PKey::PKeyError, "BIO_new") if bio.zero?

        if (to_der ? Lib.i2d_PUBKEY_bio(bio, pkey) : Lib.PEM_write_bio_PUBKEY(bio, pkey)).zero?
          Lib.BIO_free(bio)
          raise error(PKey::PKeyError, to_der ? "i2d_PUBKEY_bio" : "PEM_write_bio_PUBKEY")
        end
        membio2str(bio)
      end

      # do_pkcs8_export.
      def pkcs8_export(object, to_der, args)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

        pkey = PKEY.fetch(object)
        cipher, password = args
        unless args.empty?
          enc, _holder = fetch_cipher(cipher)
          password = pem_password_value(password)
        end
        bio = Lib.BIO_new(Lib.BIO_s_mem)
        raise error(PKey::PKeyError, "BIO_new") if bio.zero?

        written = with_password(password, nil) do |id|
          if to_der
            Lib.i2d_PKCS8PrivateKey_bio(bio, pkey, enc, nil, 0, PEM_PASSWORD_CB, id)
          else
            Lib.PEM_write_bio_PKCS8PrivateKey(bio, pkey, enc, nil, 0, PEM_PASSWORD_CB, id)
          end
        end
        if written.zero?
          Lib.BIO_free(bio)
          raise error(PKey::PKeyError, to_der ? "i2d_PKCS8PrivateKey_bio" : "PEM_write_bio_PKCS8PrivateKey")
        end
        membio2str(bio)
      end

      # EVP_PKEY_CTX_new over `pkey`, raising when the library cannot.
      def new_pkey_ctx(pkey)
        ctx = Lib.EVP_PKEY_CTX_new(pkey, nil)
        raise error(PKey::PKeyError, "EVP_PKEY_CTX_new") if ctx.zero?

        ctx
      end

      # The EVP_MD a digest argument names, or nil for nil.
      def optional_md(digest) = digest.nil? ? [nil, nil] : fetch_md(digest)
    end

    KEYGEN_CB = Lib.callback { |ctx| keygen_progress(ctx) }
  end

  module PKey
    module_function

    def read(data, pass = nil, &block)
      bio, _data = Ossl.obj2bio(data)
      pkey = Ossl.with_password(Ossl.pem_password_value(pass), block) { |id| Ossl.pkey_read_generic(bio, id) }
      Lib.BIO_free(bio)
      raise Ossl.error(PKeyError, "Could not parse PKey") if pkey.nil?

      Ossl.pkey_wrap(pkey)
    end

    def generate_parameters(alg, options = nil, &block) = Ossl.pkey_generate(alg, options, true, block)

    def generate_key(alg, options = nil, &block) = Ossl.pkey_generate(alg, options, false, block)

    def new_raw_private_key(type, key)
      key = Ossl.string_value(key)
      pkey = Lib.EVP_PKEY_new_raw_private_key_ex(nil, Ossl.cstring_value(type), nil, key, key.bytesize)
      raise Ossl.error(PKeyError, "EVP_PKEY_new_raw_private_key_ex") if pkey.zero?

      Ossl.pkey_wrap(pkey)
    end

    def new_raw_public_key(type, key)
      key = Ossl.string_value(key)
      pkey = Lib.EVP_PKEY_new_raw_public_key_ex(nil, Ossl.cstring_value(type), nil, key, key.bytesize)
      raise Ossl.error(PKeyError, "EVP_PKEY_new_raw_public_key_ex") if pkey.zero?

      Ossl.pkey_wrap(pkey)
    end

    class PKey
      def initialize
        raise Ossl.error(TypeError, "OpenSSL::PKey::PKey can't be instantiated directly") if instance_of?(PKey)
      end

      def initialize_copy(other)
        Ossl::PKEY.unshare(self, other)
        raise TypeError, "pkey already initialized" if Ossl::PKEY.get(self)

        other_pkey = Ossl::PKEY.get(other)
        if other_pkey
          pkey = Lib.EVP_PKEY_dup(other_pkey)
          raise Ossl.error(PKeyError, "EVP_PKEY_dup") if pkey.zero?

          Ossl::PKEY.set(self, pkey)
        end
        self
      end

      def oid
        nid = Lib.EVP_PKEY_get_id(Ossl.pkey(self))
        raise Ossl.error(PKeyError, "EVP_PKEY_id") if nid == Lib::EVP_PKEY_KEYMGMT

        Lib.string(Lib.OBJ_nid2sn(nid))
      end

      def inspect
        pkey = Ossl.pkey(self)
        text = Object.instance_method(:to_s).bind_call(self).delete_suffix(">")
        nid = Lib.EVP_PKEY_get_id(pkey)
        text << " oid=#{Lib.string(Lib.OBJ_nid2sn(nid))}" unless nid == Lib::EVP_PKEY_KEYMGMT
        text << " type_name=#{Lib.EVP_PKEY_get0_type_name(pkey)}"
        provider = Lib.EVP_PKEY_get0_provider(pkey)
        text << " provider=#{Lib.OSSL_PROVIDER_get0_name(provider)}" unless provider.zero?
        text << ">"
      end

      def to_text
        pkey = Ossl.pkey(self)
        bio = Lib.BIO_new(Lib.BIO_s_mem)
        raise Ossl.error(PKeyError, "BIO_new") if bio.zero?

        %i[EVP_PKEY_print_private EVP_PKEY_print_public EVP_PKEY_print_params].each do |print|
          return Ossl.membio2str(bio) if Lib.public_send(print, bio, pkey, 0, nil) == 1
          break if print == :EVP_PKEY_print_params

          Ossl.bio_reset(bio)
        end
        Lib.BIO_free(bio)
        raise Ossl.error(PKeyError, "EVP_PKEY_print_params")
      end

      def private_to_der(*args) = Ossl.pkcs8_export(self, true, args)

      def private_to_pem(*args) = Ossl.pkcs8_export(self, false, args)

      def public_to_der = Ossl.pkey_export_spki(self, true)

      def public_to_pem = Ossl.pkey_export_spki(self, false)

      def raw_private_key
        pkey = Ossl.pkey(self)
        Ossl.sized_output(PKeyError, "EVP_PKEY_get_raw_private_key") { |out, length| Lib.EVP_PKEY_get_raw_private_key(pkey, out, length) == 1 }
      end

      def raw_public_key
        pkey = Ossl.pkey(self)
        Ossl.sized_output(PKeyError, "EVP_PKEY_get_raw_public_key") { |out, length| Lib.EVP_PKEY_get_raw_public_key(pkey, out, length) == 1 }
      end

      def compare?(other)
        self_pkey = Ossl.pkey(self)
        other_pkey = Ossl.pkey(other)
        raise Ossl.error(TypeError, "cannot match different PKey types") if Lib.EVP_PKEY_get_id(self_pkey) != Lib.EVP_PKEY_get_id(other_pkey)

        case Lib.EVP_PKEY_eq(self_pkey, other_pkey)
        when 0 then false
        when 1 then true
        else raise Ossl.error(PKeyError, "EVP_PKEY_eq")
        end
      end

      def sign(digest, data, options = nil)
        pkey = Ossl.private_pkey(self)
        md, _holder = Ossl.optional_md(digest)
        data = Ossl.string_value(data)
        ctx = Lib.EVP_MD_CTX_new
        raise Ossl.error(PKeyError, "EVP_MD_CTX_new") if ctx.zero?

        begin
          pctx = Lib.buffer(8)
          raise Ossl.error(PKeyError, "EVP_DigestSignInit") if Lib.EVP_DigestSignInit(ctx, pctx, md, nil, pkey) < 1

          Ossl.apply_pkey_options(Lib.pointer_at(pctx), options) unless options.nil?
          Ossl.sized_output(PKeyError, "EVP_DigestSign", "signature would be too large") do |out, length|
            Lib.EVP_DigestSign(ctx, out, length, data, data.bytesize) >= 1
          end
        ensure
          Lib.EVP_MD_CTX_free(ctx)
        end
      end

      def verify(digest, signature, data, options = nil)
        pkey = Ossl.pkey(self)
        Ossl.check_public_key(pkey)
        md, _holder = Ossl.optional_md(digest)
        signature = Ossl.string_value(signature)
        data = Ossl.string_value(data)
        ctx = Lib.EVP_MD_CTX_new
        raise Ossl.error(PKeyError, "EVP_MD_CTX_new") if ctx.zero?

        begin
          pctx = Lib.buffer(8)
          raise Ossl.error(PKeyError, "EVP_DigestVerifyInit") if Lib.EVP_DigestVerifyInit(ctx, pctx, md, nil, pkey) < 1

          Ossl.apply_pkey_options(Lib.pointer_at(pctx), options) unless options.nil?
          answer = Lib.EVP_DigestVerify(ctx, signature, signature.bytesize, data, data.bytesize)
        ensure
          Lib.EVP_MD_CTX_free(ctx)
        end
        raise Ossl.error(PKeyError, "EVP_DigestVerify") if answer.negative?

        Ossl.clear_error if answer.zero?
        answer != 0
      end

      def sign_raw(digest, data, options = nil)
        pkey = Ossl.pkey(self)
        md, _holder = Ossl.optional_md(digest)
        data = Ossl.string_value(data)
        Ossl.with_pkey_ctx(Ossl.new_pkey_ctx(pkey)) do |ctx|
          raise Ossl.error(PKeyError, "EVP_PKEY_sign_init") if Lib.EVP_PKEY_sign_init(ctx) <= 0
          raise Ossl.error(PKeyError, "EVP_PKEY_CTX_set_signature_md") if md && Lib.EVP_PKEY_CTX_set_signature_md(ctx, md) <= 0

          Ossl.apply_pkey_options(ctx, options) unless options.nil?
          Ossl.sized_output(PKeyError, "EVP_PKEY_sign", "signature would be too large") do |out, length|
            Lib.EVP_PKEY_sign(ctx, out, length, data, data.bytesize) > 0
          end
        end
      end

      def verify_raw(digest, signature, data, options = nil)
        pkey = Ossl.pkey(self)
        Ossl.check_public_key(pkey)
        md, _holder = Ossl.optional_md(digest)
        signature = Ossl.string_value(signature)
        data = Ossl.string_value(data)
        answer = Ossl.with_pkey_ctx(Ossl.new_pkey_ctx(pkey)) do |ctx|
          raise Ossl.error(PKeyError, "EVP_PKEY_verify_init") if Lib.EVP_PKEY_verify_init(ctx) <= 0
          raise Ossl.error(PKeyError, "EVP_PKEY_CTX_set_signature_md") if md && Lib.EVP_PKEY_CTX_set_signature_md(ctx, md) <= 0

          Ossl.apply_pkey_options(ctx, options) unless options.nil?
          Lib.EVP_PKEY_verify(ctx, signature, signature.bytesize, data, data.bytesize)
        end
        raise Ossl.error(PKeyError, "EVP_PKEY_verify") if answer.negative?

        Ossl.clear_error if answer.zero?
        answer != 0
      end

      def verify_recover(digest, signature, options = nil)
        pkey = Ossl.pkey(self)
        Ossl.check_public_key(pkey)
        md, _holder = Ossl.optional_md(digest)
        signature = Ossl.string_value(signature)
        Ossl.with_pkey_ctx(Ossl.new_pkey_ctx(pkey)) do |ctx|
          raise Ossl.error(PKeyError, "EVP_PKEY_verify_recover_init") if Lib.EVP_PKEY_verify_recover_init(ctx) <= 0
          raise Ossl.error(PKeyError, "EVP_PKEY_CTX_set_signature_md") if md && Lib.EVP_PKEY_CTX_set_signature_md(ctx, md) <= 0

          Ossl.apply_pkey_options(ctx, options) unless options.nil?
          Ossl.sized_output(PKeyError, "EVP_PKEY_verify_recover") do |out, length|
            Lib.EVP_PKEY_verify_recover(ctx, out, length, signature, signature.bytesize) > 0
          end
        end
      end

      def derive(peer)
        pkey = Ossl.pkey(self)
        peer_pkey = Ossl.pkey(peer)
        Ossl.with_pkey_ctx(Ossl.new_pkey_ctx(pkey)) do |ctx|
          raise Ossl.error(PKeyError, "EVP_PKEY_derive_init") if Lib.EVP_PKEY_derive_init(ctx) <= 0
          raise Ossl.error(PKeyError, "EVP_PKEY_derive_set_peer") if Lib.EVP_PKEY_derive_set_peer(ctx, peer_pkey) <= 0

          Ossl.sized_output(PKeyError, "EVP_PKEY_derive", "derived key would be too large") do |out, length|
            Lib.EVP_PKEY_derive(ctx, out, length) > 0
          end
        end
      end

      def encrypt(data, options = nil)
        pkey = Ossl.pkey(self)
        data = Ossl.string_value(data)
        Ossl.with_pkey_ctx(Ossl.new_pkey_ctx(pkey)) do |ctx|
          raise Ossl.error(PKeyError, "EVP_PKEY_encrypt_init") if Lib.EVP_PKEY_encrypt_init(ctx) <= 0

          Ossl.apply_pkey_options(ctx, options) unless options.nil?
          Ossl.sized_output(PKeyError, "EVP_PKEY_encrypt", "encrypted data would be too large") do |out, length|
            Lib.EVP_PKEY_encrypt(ctx, out, length, data, data.bytesize) > 0
          end
        end
      end

      def decrypt(data, options = nil)
        pkey = Ossl.pkey(self)
        data = Ossl.string_value(data)
        Ossl.with_pkey_ctx(Ossl.new_pkey_ctx(pkey)) do |ctx|
          raise Ossl.error(PKeyError, "EVP_PKEY_decrypt_init") if Lib.EVP_PKEY_decrypt_init(ctx) <= 0

          Ossl.apply_pkey_options(ctx, options) unless options.nil?
          Ossl.sized_output(PKeyError, "EVP_PKEY_decrypt", "decrypted data would be too large") do |out, length|
            Lib.EVP_PKEY_decrypt(ctx, out, length, data, data.bytesize) > 0
          end
        end
      end
    end
  end
end
