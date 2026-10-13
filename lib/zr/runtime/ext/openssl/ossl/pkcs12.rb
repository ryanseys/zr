# frozen_string_literal: true

# ossl_pkcs12.c: OpenSSL::PKCS12 over PKCS12.
module OpenSSL
  Lib.attach_all(
    PKCS12_new: [[], :pointer],
    PKCS12_free: [%i[pointer], :void],
    PKCS12_create: [%i[string string pointer pointer pointer int int int int int], :pointer],
    d2i_PKCS12_bio: [%i[pointer buffer], :pointer],
    i2d_PKCS12: [%i[pointer buffer], :int],
    PKCS12_parse: [%i[pointer string buffer buffer buffer], :int],
    PKCS12_set_mac: [%i[pointer buffer int buffer int int pointer], :int]
  )

  module Lib
    KEY_EX = 0x10 # pkcs12.h
    KEY_SIG = 0x80
  end

  class PKCS12
    class PKCS12Error < OpenSSLError; end
  end

  module Ossl
    PKCS12_STRUCT = DataType.new("OpenSSL/PKCS12", OpenSSL::PKCS12, :PKCS12_free, [RuntimeError, "PKCS12 wasn't initialized."], create: lambda {
      Lib.PKCS12_new.tap { |p12| raise Ossl.error(OpenSSL::PKCS12::PKCS12Error) if p12.zero? }
    })

    # A PBE algorithm's NID, 0 for nil.
    def self.pbe_nid(name)
      return 0 if name.nil?

      nid = Lib.OBJ_txt2nid(cstring_value(name))
      raise error(ArgumentError, "Unknown PBE algorithm #{name}") if nid == Lib::NID_undef

      nid
    end
  end

  class PKCS12
    def key = @key

    def certificate = @certificate

    def ca_certs = @ca_certs

    def self.create(pass, name, pkey, cert, ca = nil, key_nid = nil, cert_nid = nil, key_iter = nil, mac_iter = nil, keytype = nil)
      passphrase = pass.nil? ? nil : Ossl.cstring_value(pass)
      friendly_name = name.nil? ? nil : Ossl.cstring_value(name)
      key = Ossl.pkey(pkey)
      x509 = Ossl.x509(cert)
      key_algorithm = Ossl.pbe_nid(key_nid)
      cert_algorithm = Ossl.pbe_nid(cert_nid)
      key_iterations = key_iter.nil? ? 0 : Ossl.int(key_iter)
      mac_iterations = mac_iter.nil? ? 0 : Ossl.int(mac_iter)
      usage = keytype.nil? ? 0 : Ossl.int(keytype)
      raise Ossl.error(ArgumentError, "Unknown key usage type #{usage}") unless [0, Lib::KEY_SIG, Lib::KEY_EX].include?(usage)

      pkcs12 = Native.allocate(PKCS12)
      stack = ca.nil? ? nil : Ossl.x509_ary2sk(ca)
      p12 = Lib.PKCS12_create(passphrase, friendly_name, key, x509, stack, key_algorithm, cert_algorithm, key_iterations, mac_iterations, usage)
      Ossl.free_x509_stack(stack)
      raise Ossl.error(PKCS12Error) if p12.zero?

      Ossl::PKCS12_STRUCT.set(pkcs12, p12)
      pkcs12.instance_variable_set(:@key, pkey)
      pkcs12.instance_variable_set(:@certificate, cert)
      pkcs12.instance_variable_set(:@ca_certs, ca)
      pkcs12
    end

    def initialize_copy(other)
      Ossl::PKCS12_STRUCT.unshare(self, other) unless equal?(other)
      Ossl.want_uninitialized(self, Ossl::PKCS12_STRUCT)
      copy = Lib.ASN1_dup(Lib.function_address(:i2d_PKCS12), Lib.function_address(:d2i_PKCS12), Ossl::PKCS12_STRUCT.fetch(other))
      raise Ossl.error(PKCS12Error, "ASN1_dup") if copy.zero?

      Ossl::PKCS12_STRUCT.set(self, copy)
      self
    end

    def initialize(*args)
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

      Ossl.want_uninitialized(self, Ossl::PKCS12_STRUCT)
      return Ossl::PKCS12_STRUCT.create(self) if args.empty?

      arg, pass = args
      passphrase = pass.nil? ? nil : Ossl.cstring_value(pass)
      bio, _arg = Ossl.obj2bio(arg)
      p12 = Lib.d2i_PKCS12_bio(bio, nil)
      Lib.BIO_free(bio)
      raise Ossl.error(PKCS12Error, "d2i_PKCS12_bio") if p12.zero?

      Ossl::PKCS12_STRUCT.set(self, p12)
      key, x509, stack = Array.new(3) { Lib.buffer(8) }
      raise Ossl.error(PKCS12Error, "PKCS12_parse") if Lib.PKCS12_parse(Ossl::PKCS12_STRUCT.get(self), passphrase, key, x509, stack).zero?

      key = Lib.pointer_at(key)
      x509 = Lib.pointer_at(x509)
      stack = Lib.pointer_at(stack)
      pkey = certificate = ca = nil
      begin
        pkey = Ossl.pkey_wrap(key) unless key.zero?
        certificate = Ossl.x509_new(x509) unless x509.zero?
        ca = Ossl.x509_sk2ary(stack) unless stack.zero?
      ensure
        Lib.X509_free(x509) unless x509.zero?
        Ossl.free_x509_stack(stack)
        @key = pkey
        @certificate = certificate
        @ca_certs = ca
      end
      self
    end

    def to_der = Ossl.i2d(:i2d_PKCS12, Ossl::PKCS12_STRUCT.fetch(self), PKCS12Error)

    def set_mac(pass, salt = nil, iter = nil, md_name = nil)
      Ossl.check_frozen(self)
      p12 = Ossl::PKCS12_STRUCT.fetch(self)
      pass = Ossl.string_value(pass)
      salt = Ossl.string_value(salt) unless salt.nil?
      iterations = iter.nil? ? 0 : Ossl.int(iter)
      md, _holder = Ossl.optional_md(md_name)
      if Lib.PKCS12_set_mac(p12, pass, pass.bytesize, salt, salt&.bytesize || 0, iterations, md).zero?
        raise Ossl.error(PKCS12Error, "PKCS12_set_mac")
      end
      nil
    end
  end
end
