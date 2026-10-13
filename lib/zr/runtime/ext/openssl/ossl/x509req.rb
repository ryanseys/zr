# frozen_string_literal: true

# ossl_x509req.c: OpenSSL::X509::Request over X509_REQ.
module OpenSSL
  Lib.attach_all(
    X509_REQ_new: [[], :pointer],
    X509_REQ_free: [%i[pointer], :void],
    X509_REQ_dup: [%i[pointer], :pointer],
    d2i_X509_REQ_bio: [%i[pointer pointer], :pointer],
    PEM_read_bio_X509_REQ: [%i[pointer pointer pointer pointer], :pointer],
    PEM_write_bio_X509_REQ: [%i[pointer pointer], :int],
    i2d_X509_REQ: [%i[pointer buffer], :int],
    X509_REQ_print: [%i[pointer pointer], :int],
    X509_REQ_get_version: [%i[pointer], :long],
    X509_REQ_set_version: [%i[pointer long], :int],
    X509_REQ_get_subject_name: [%i[pointer], :pointer],
    X509_REQ_set_subject_name: [%i[pointer pointer], :int],
    X509_REQ_get0_signature: [%i[pointer buffer buffer], :void],
    X509_REQ_get_pubkey: [%i[pointer], :pointer],
    X509_REQ_set_pubkey: [%i[pointer pointer], :int],
    X509_REQ_sign: [%i[pointer pointer pointer], :int],
    X509_REQ_verify: [%i[pointer pointer], :int],
    X509_REQ_get_attr_count: [%i[pointer], :int],
    X509_REQ_get_attr: [%i[pointer int], :pointer],
    X509_REQ_delete_attr: [%i[pointer int], :pointer],
    X509_REQ_add1_attr: [%i[pointer pointer], :int]
  )

  module X509
    class RequestError < OpenSSLError; end

    class Request; end
  end

  module Ossl
    X509_REQ = DataType.new("OpenSSL/X509/REQ", X509::Request, :X509_REQ_free, [RuntimeError, "Req wasn't initialized!"], create: lambda {
      Lib.X509_REQ_new.tap { |req| raise Ossl.error(X509::RequestError) if req.zero? }
    })

    # GetX509ReqPtr.
    def self.x509req(object) = X509_REQ.fetch(object)
  end

  module X509
    class Request
      def initialize(*args)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..1)" if args.size > 1

        Ossl.want_uninitialized(self, Ossl::X509_REQ)
        return Ossl::X509_REQ.create(self) if args.empty?

        bio, _arg = Ossl.obj2bio(Ossl.to_der_if_possible(args.first))
        req = Lib.d2i_X509_REQ_bio(bio, nil)
        if req.zero?
          Ossl.bio_reset(bio)
          req = Lib.PEM_read_bio_X509_REQ(bio, nil, nil, nil)
        end
        Lib.BIO_free(bio)
        raise Ossl.error(RequestError, "PEM_read_bio_X509_REQ") if req.zero?

        Ossl::X509_REQ.set(self, req)
        self
      end

      def initialize_copy(other)
        Ossl::X509_REQ.unshare(self, other) unless equal?(other)
        Ossl.want_uninitialized(self, Ossl::X509_REQ)
        copy = Lib.X509_REQ_dup(Ossl::X509_REQ.fetch(other))
        raise Ossl.error(RequestError) if copy.zero?

        Ossl::X509_REQ.set(self, copy)
        self
      end

      def to_pem
        req = Ossl.x509req(self)
        Ossl.bio_output(RequestError) { |bio| Lib.PEM_write_bio_X509_REQ(bio, req) }
      end
      alias to_s to_pem

      def to_der = Ossl.i2d(:i2d_X509_REQ, Ossl.x509req(self), RequestError)

      def to_text
        req = Ossl.x509req(self)
        Ossl.bio_output(RequestError) { |bio| Lib.X509_REQ_print(bio, req) }
      end

      def version = Lib.X509_REQ_get_version(Ossl.x509req(self))

      def version=(version)
        raise Ossl.error(RequestError, "version must be >= 0!") if Ossl.long(version).negative?
        raise Ossl.error(RequestError, "X509_REQ_set_version") if Lib.X509_REQ_set_version(Ossl.x509req(self), Ossl.long(version)).zero?

        version
      end

      def subject
        name = Lib.X509_REQ_get_subject_name(Ossl.x509req(self))
        raise Ossl.error(RequestError) if name.zero?

        Ossl.x509name_new(name)
      end

      def subject=(subject)
        req = Ossl.x509req(self)
        raise Ossl.error(RequestError) if Lib.X509_REQ_set_subject_name(req, Ossl::X509_NAME.fetch(subject)).zero?

        subject
      end

      def signature_algorithm
        algor = Lib.buffer(8)
        Lib.X509_REQ_get0_signature(Ossl.x509req(self), nil, algor)
        Ossl.algorithm_name(Lib.pointer_at(algor))
      end

      def public_key
        pkey = Lib.X509_REQ_get_pubkey(Ossl.x509req(self))
        raise Ossl.error(RequestError) if pkey.zero?

        Ossl.pkey_wrap(pkey)
      end

      def public_key=(key)
        req = Ossl.x509req(self)
        pkey = Ossl.pkey(key)
        Ossl.check_public_key(pkey)
        raise Ossl.error(RequestError, "X509_REQ_set_pubkey") if Lib.X509_REQ_set_pubkey(req, pkey).zero?

        key
      end

      def sign(key, digest)
        req = Ossl.x509req(self)
        pkey = Ossl.private_pkey(key)
        md, _holder = Ossl.optional_md(digest)
        raise Ossl.error(RequestError, "X509_REQ_sign") if Lib.X509_REQ_sign(req, pkey, md).zero?

        self
      end

      def verify(key)
        req = Ossl.x509req(self)
        pkey = Ossl.pkey(key)
        Ossl.check_public_key(pkey)
        case Lib.X509_REQ_verify(req, pkey)
        when 1 then true
        when 0
          Ossl.clear_error
          false
        else raise Ossl.error(RequestError)
        end
      end

      def attributes
        req = Ossl.x509req(self)
        count = Lib.X509_REQ_get_attr_count(req)
        return [] if count.negative?

        Array.new(count) { |i| Ossl.x509attr_new(Lib.X509_REQ_get_attr(req, i)) }
      end

      def attributes=(attributes)
        Ossl.check_array(attributes)
        attributes.each { |attribute| Ossl.check_kind(attribute, Attribute) }
        req = Ossl.x509req(self)
        Lib.X509_REQ_get_attr_count(req).times { Lib.X509_ATTRIBUTE_free(Lib.X509_REQ_delete_attr(req, 0)) }
        attributes.each do |attribute|
          raise Ossl.error(RequestError, "X509_REQ_add1_attr") if Lib.X509_REQ_add1_attr(req, Ossl::X509_ATTR.fetch(attribute)).zero?
        end
        attributes
      end

      def add_attribute(attribute)
        req = Ossl.x509req(self)
        raise Ossl.error(RequestError) if Lib.X509_REQ_add1_attr(req, Ossl::X509_ATTR.fetch(attribute)).zero?

        attribute
      end
    end
  end
end
