# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_ocsp.c: OpenSSL::OCSP, requests and responses of the Online
# Certificate Status Protocol.
module OpenSSL
  Lib.attach_all(
    ASN1_item_dup: [%i[pointer pointer], :pointer],
    OCSP_REQUEST_it: [[], :pointer],
    OCSP_RESPONSE_it: [[], :pointer],
    OCSP_BASICRESP_it: [[], :pointer],
    OCSP_SINGLERESP_it: [[], :pointer],
    OCSP_REQUEST_new: [[], :pointer],
    OCSP_REQUEST_free: [%i[pointer], :void],
    OCSP_RESPONSE_new: [[], :pointer],
    OCSP_RESPONSE_free: [%i[pointer], :void],
    OCSP_BASICRESP_new: [[], :pointer],
    OCSP_BASICRESP_free: [%i[pointer], :void],
    OCSP_SINGLERESP_new: [[], :pointer],
    OCSP_SINGLERESP_free: [%i[pointer], :void],
    OCSP_CERTID_new: [[], :pointer],
    OCSP_CERTID_free: [%i[pointer], :void],
    OCSP_CERTID_dup: [%i[pointer], :pointer],
    d2i_OCSP_REQUEST: [%i[pointer buffer long], :pointer],
    i2d_OCSP_REQUEST: [%i[pointer buffer], :int],
    d2i_OCSP_RESPONSE: [%i[pointer buffer long], :pointer],
    i2d_OCSP_RESPONSE: [%i[pointer buffer], :int],
    d2i_OCSP_BASICRESP: [%i[pointer buffer long], :pointer],
    i2d_OCSP_BASICRESP: [%i[pointer buffer], :int],
    d2i_OCSP_SINGLERESP: [%i[pointer buffer long], :pointer],
    i2d_OCSP_SINGLERESP: [%i[pointer buffer], :int],
    d2i_OCSP_CERTID: [%i[pointer buffer long], :pointer],
    i2d_OCSP_CERTID: [%i[pointer buffer], :int],
    OCSP_request_add1_nonce: [%i[pointer buffer int], :int],
    OCSP_check_nonce: [%i[pointer pointer], :int],
    OCSP_request_add0_id: [%i[pointer pointer], :pointer],
    OCSP_request_onereq_count: [%i[pointer], :int],
    OCSP_request_onereq_get0: [%i[pointer int], :pointer],
    OCSP_onereq_get0_id: [%i[pointer], :pointer],
    OCSP_request_sign: [%i[pointer pointer pointer pointer pointer ulong], :int],
    OCSP_request_verify: [%i[pointer pointer pointer ulong], :int],
    OCSP_request_is_signed: [%i[pointer], :int],
    OCSP_response_create: [%i[int pointer], :pointer],
    OCSP_response_status: [%i[pointer], :int],
    OCSP_response_status_str: [%i[long], :string],
    OCSP_response_get1_basic: [%i[pointer], :pointer],
    OCSP_copy_nonce: [%i[pointer pointer], :int],
    OCSP_basic_add1_nonce: [%i[pointer buffer int], :int],
    X509_gmtime_adj: [%i[pointer long], :pointer],
    OCSP_basic_add1_status: [%i[pointer pointer int int pointer pointer pointer], :pointer],
    OCSP_SINGLERESP_add_ext: [%i[pointer pointer int], :int],
    OCSP_resp_count: [%i[pointer], :int],
    OCSP_resp_get0: [%i[pointer int], :pointer],
    OCSP_single_get0_status: [%i[pointer buffer buffer buffer buffer], :int],
    OCSP_SINGLERESP_get0_id: [%i[pointer], :pointer],
    OCSP_SINGLERESP_get_ext_count: [%i[pointer], :int],
    OCSP_SINGLERESP_get_ext: [%i[pointer int], :pointer],
    OCSP_resp_find: [%i[pointer pointer int], :int],
    OCSP_basic_sign: [%i[pointer pointer pointer pointer pointer ulong], :int],
    OCSP_basic_verify: [%i[pointer pointer pointer ulong], :int],
    OCSP_check_validity: [%i[pointer pointer long long], :int],
    OCSP_cert_to_id: [%i[pointer pointer pointer], :pointer],
    OCSP_id_cmp: [%i[pointer pointer], :int],
    OCSP_id_issuer_cmp: [%i[pointer pointer], :int],
    OCSP_id_get0_info: [%i[buffer buffer buffer buffer pointer], :int]
  )

  module Lib
    OCSP_NOCERTS = 0x1 # ocsp.h
    V_OCSP_CERTSTATUS_REVOKED = 1
  end

  module OCSP
    class OCSPError < OpenSSLError; end

    class Request; end

    class Response; end

    class BasicResponse; end

    class SingleResponse; end

    class CertificateId; end
  end

  module Ossl
    # What each class's initialize makes with no argument: OCSP_*_new.
    def self.ocsp_alloc(new_function) = lambda {
      Lib.public_send(new_function).tap { |struct| raise Ossl.error(OCSP::OCSPError, new_function.to_s) if struct.zero? }
    }

    OCSP_REQUEST = DataType.new("OpenSSL/OCSP/REQUEST", OCSP::Request, :OCSP_REQUEST_free,
                                [RuntimeError, "Request wasn't initialized!"], create: ocsp_alloc(:OCSP_REQUEST_new))
    OCSP_RESPONSE = DataType.new("OpenSSL/OCSP/RESPONSE", OCSP::Response, :OCSP_RESPONSE_free,
                                 [RuntimeError, "Response wasn't initialized!"], create: ocsp_alloc(:OCSP_RESPONSE_new))
    OCSP_BASICRESP = DataType.new("OpenSSL/OCSP/BASICRESP", OCSP::BasicResponse, :OCSP_BASICRESP_free,
                                  [RuntimeError, "Response wasn't initialized!"], create: ocsp_alloc(:OCSP_BASICRESP_new))
    OCSP_SINGLERESP = DataType.new("OpenSSL/OCSP/SINGLERESP", OCSP::SingleResponse, :OCSP_SINGLERESP_free,
                                   [RuntimeError, "SingleResponse wasn't initialized!"], create: ocsp_alloc(:OCSP_SINGLERESP_new))
    OCSP_CERTID = DataType.new("OpenSSL/OCSP/CERTID", OCSP::CertificateId, :OCSP_CERTID_free,
                               [RuntimeError, "Cert ID wasn't initialized!"], create: ocsp_alloc(:OCSP_CERTID_new))

    class << self
      # ossl_ocspcid_new.
      def ocsp_certid_new(cid)
        copy = Lib.OCSP_CERTID_dup(cid)
        raise error(OCSP::OCSPError, "OCSP_CERTID_dup") if copy.zero?

        OCSP_CERTID.wrap(OCSP::CertificateId, copy)
      end

      # ossl_ocspsres_new.
      def ocsp_singleresp_new(single)
        copy = Lib.ASN1_item_dup(Lib.OCSP_SINGLERESP_it, single)
        raise error(OCSP::OCSPError, "ASN1_item_dup") if copy.zero?

        OCSP_SINGLERESP.wrap(OCSP::SingleResponse, copy)
      end

      # The initialize_copy of each OCSP class: an ASN1_item_dup of the
      # other's struct.
      def ocsp_copy(object, other, type, item)
        type.unshare(object, other) unless object.equal?(other)
        want_uninitialized(object, type)
        copy = Lib.ASN1_item_dup(Lib.public_send(item), type.fetch(other))
        raise error(OCSP::OCSPError, "ASN1_item_dup") if copy.zero?

        type.set(object, copy)
        object
      end

      # The initialize of each OCSP class given DER.
      def ocsp_decode(object, arg, type, d2i)
        der = string_value(to_der_if_possible(arg))
        decoded = d2i(d2i, der)
        raise error(OCSP::OCSPError, d2i.to_s) if decoded.zero?

        type.set(object, decoded)
        object
      end

      # add_nonce of a request or a basic response.
      def ocsp_add_nonce(object, type, function, value)
        if value.nil?
          answer = Lib.public_send(function, type.fetch(object), nil, -1)
        else
          value = string_value(value)
          answer = Lib.public_send(function, type.fetch(object), value, value.bytesize)
        end
        raise error(OCSP::OCSPError) if answer.zero?

        object
      end

      # sign of a request or a basic response.
      def ocsp_sign(object, type, function, signer_cert, signer_key, certs, flags, digest)
        struct = type.fetch(object)
        signer = x509(signer_cert)
        key = private_pkey(signer_key)
        flags = optional_int(flags)
        md, _holder = optional_md(digest)
        stack = nil
        if certs.nil?
          flags |= Lib::OCSP_NOCERTS
        else
          stack = x509_ary2sk(certs)
        end
        answer = Lib.public_send(function, struct, signer, key, md, stack, flags)
        free_x509_stack(stack)
        raise error(OCSP::OCSPError, function.to_s) if answer.zero?

        object
      end

      # verify of a request or a basic response.
      def ocsp_verify(object, type, function, certs, store, flags)
        struct = type.fetch(object)
        x509store = x509store(store)
        flags = optional_int(flags)
        stack = x509_ary2sk(certs)
        answer = Lib.public_send(function, struct, stack, x509store, flags)
        free_x509_stack(stack)
        clear_error if answer <= 0
        answer.positive?
      end

      # add_status_convert_time.
      def ocsp_time(value)
        time = value.is_a?(Integer) ? Lib.X509_gmtime_adj(nil, int(value)) : x509_time_adjust(nil, value)
        raise error(OCSP::OCSPError) if time.zero?

        time
      end

      # OCSP_single_get0_status, raising on failure: [status, reason,
      # revtime, thisupd, nextupd].
      def ocsp_single_status(single)
        reason = [-1].pack("l")
        times = Array.new(3) { Lib.buffer(8) }
        status = Lib.OCSP_single_get0_status(single, reason, *times)
        raise error(OCSP::OCSPError, "OCSP_single_get0_status") if status.negative?

        [status, reason.unpack1("l"), *times.map { |time| Lib.pointer_at(time) }]
      end

      def time_or_nil(time) = time.zero? ? nil : asn1time_to_time(time)

      # A hash's bytes in lower-case hex, as ossl_bin2hex writes them.
      def hex(asn1_string) = asn1str_to_str(asn1_string).unpack1("H*").b

      # OCSP_id_get0_info's one out-parameter at `index`.
      def ocsp_id_info(cid, index)
        out = Lib.buffer(8)
        Lib.OCSP_id_get0_info(*Array.new(4) { |i| out if i == index }, cid)
        Lib.pointer_at(out)
      end
    end
  end

  module OCSP
    class Request
      def initialize_copy(other) = Ossl.ocsp_copy(self, other, Ossl::OCSP_REQUEST, :OCSP_REQUEST_it)

      def initialize(arg = nil)
        Ossl.want_uninitialized(self, Ossl::OCSP_REQUEST)
        arg.nil? ? Ossl::OCSP_REQUEST.create(self) : Ossl.ocsp_decode(self, arg, Ossl::OCSP_REQUEST, :d2i_OCSP_REQUEST)
      end

      def add_nonce(value = nil) = Ossl.ocsp_add_nonce(self, Ossl::OCSP_REQUEST, :OCSP_request_add1_nonce, value)

      def check_nonce(basic_resp)
        req = Ossl::OCSP_REQUEST.fetch(self)
        Lib.OCSP_check_nonce(req, Ossl::OCSP_BASICRESP.fetch(basic_resp))
      end

      def add_certid(certid)
        req = Ossl::OCSP_REQUEST.fetch(self)
        copy = Lib.OCSP_CERTID_dup(Ossl::OCSP_CERTID.fetch(certid))
        raise Ossl.error(OCSPError, "OCSP_CERTID_dup") if copy.zero?

        if Lib.OCSP_request_add0_id(req, copy).zero?
          Lib.OCSP_CERTID_free(copy)
          raise Ossl.error(OCSPError, "OCSP_request_add0_id")
        end
        self
      end

      def certid
        req = Ossl::OCSP_REQUEST.fetch(self)
        count = Lib.OCSP_request_onereq_count(req)
        raise Ossl.error(OCSPError, "OCSP_request_onereq_count") if count.negative?
        return nil if count.zero?

        Array.new(count) { |i| Ossl.ocsp_certid_new(Lib.OCSP_onereq_get0_id(Lib.OCSP_request_onereq_get0(req, i))) }
      end

      def signed? = !Lib.OCSP_request_is_signed(Ossl::OCSP_REQUEST.fetch(self)).zero?

      def sign(signer_cert, signer_key, certs = nil, flags = nil, digest = nil)
        Ossl.ocsp_sign(self, Ossl::OCSP_REQUEST, :OCSP_request_sign, signer_cert, signer_key, certs, flags, digest)
      end

      def verify(certs, store, flags = nil) = Ossl.ocsp_verify(self, Ossl::OCSP_REQUEST, :OCSP_request_verify, certs, store, flags)

      def to_der = Ossl.i2d(:i2d_OCSP_REQUEST, Ossl::OCSP_REQUEST.fetch(self), OCSPError)
    end

    class Response
      def self.create(status, basic_resp)
        status = Ossl.int(status)
        bs = basic_resp.nil? ? nil : Ossl::OCSP_BASICRESP.fetch(basic_resp)
        response = Native.allocate(self)
        res = Lib.OCSP_response_create(status, bs)
        raise Ossl.error(OCSPError) if res.zero?

        Ossl::OCSP_RESPONSE.set(response, res)
        response
      end

      def initialize_copy(other) = Ossl.ocsp_copy(self, other, Ossl::OCSP_RESPONSE, :OCSP_RESPONSE_it)

      def initialize(arg = nil)
        Ossl.want_uninitialized(self, Ossl::OCSP_RESPONSE)
        arg.nil? ? Ossl::OCSP_RESPONSE.create(self) : Ossl.ocsp_decode(self, arg, Ossl::OCSP_RESPONSE, :d2i_OCSP_RESPONSE)
      end

      def status = Lib.OCSP_response_status(Ossl::OCSP_RESPONSE.fetch(self))

      def status_string = Lib.OCSP_response_status_str(Lib.OCSP_response_status(Ossl::OCSP_RESPONSE.fetch(self)))

      def basic
        bs = Lib.OCSP_response_get1_basic(Ossl::OCSP_RESPONSE.fetch(self))
        bs.zero? ? nil : Ossl::OCSP_BASICRESP.wrap(BasicResponse, bs)
      end

      def to_der = Ossl.i2d(:i2d_OCSP_RESPONSE, Ossl::OCSP_RESPONSE.fetch(self), OCSPError)
    end

    class BasicResponse
      def initialize_copy(other) = Ossl.ocsp_copy(self, other, Ossl::OCSP_BASICRESP, :OCSP_BASICRESP_it)

      def initialize(arg = nil)
        arg.nil? ? Ossl::OCSP_BASICRESP.create(self) : Ossl.ocsp_decode(self, arg, Ossl::OCSP_BASICRESP, :d2i_OCSP_BASICRESP)
      end

      def copy_nonce(request)
        bs = Ossl::OCSP_BASICRESP.fetch(self)
        Lib.OCSP_copy_nonce(bs, Ossl::OCSP_REQUEST.fetch(request))
      end

      def add_nonce(value = nil) = Ossl.ocsp_add_nonce(self, Ossl::OCSP_BASICRESP, :OCSP_basic_add1_nonce, value)

      def add_status(certid, status, reason, revocation_time, this_update, next_update, extensions)
        bs = Ossl::OCSP_BASICRESP.fetch(self)
        id = Ossl::OCSP_CERTID.fetch(certid)
        status = Ossl.int(status)
        unless extensions.nil?
          extensions = Array.try_convert(extensions)
          extensions.each { |extension| Ossl.check_kind(extension, X509::Extension) }
        end
        times = []
        begin
          code = 0
          revoked = nil
          if status == Lib::V_OCSP_CERTSTATUS_REVOKED
            code = Ossl.int(reason)
            times << (revoked = Ossl.ocsp_time(revocation_time))
          end
          times << (this = Ossl.ocsp_time(this_update))
          times << (nxt = Ossl.ocsp_time(next_update)) unless next_update.nil?
          single = Lib.OCSP_basic_add1_status(bs, id, status, code, revoked, this, nxt)
          raise Ossl.error(OCSPError) if single.zero?

          extensions&.each do |extension|
            raise Ossl.error(OCSPError) if Lib.OCSP_SINGLERESP_add_ext(single, Ossl::X509_EXT.fetch(extension), -1).zero?
          end
        ensure
          times.each { |time| Lib.ASN1_TIME_free(time) }
        end
        self
      end

      def status
        bs = Ossl::OCSP_BASICRESP.fetch(self)
        Array.new(Lib.OCSP_resp_count(bs)) do |i|
          single = Lib.OCSP_resp_get0(bs, i)
          status, reason, revoked, this, nxt = Ossl.ocsp_single_status(single)
          extensions = Array.new(Lib.OCSP_SINGLERESP_get_ext_count(single)) { |j| Ossl.x509ext_new(Lib.OCSP_SINGLERESP_get_ext(single, j)) }
          [Ossl.ocsp_certid_new(Lib.OCSP_SINGLERESP_get0_id(single)), status, reason,
           Ossl.time_or_nil(revoked), Ossl.time_or_nil(this), Ossl.time_or_nil(nxt), extensions]
        end
      end

      def responses
        bs = Ossl::OCSP_BASICRESP.fetch(self)
        Array.new(Lib.OCSP_resp_count(bs)) { |i| Ossl.ocsp_singleresp_new(Lib.OCSP_resp_get0(bs, i)) }
      end

      def find_response(certid)
        id = Ossl::OCSP_CERTID.fetch(certid)
        bs = Ossl::OCSP_BASICRESP.fetch(self)
        index = Lib.OCSP_resp_find(bs, id, -1)
        index == -1 ? nil : Ossl.ocsp_singleresp_new(Lib.OCSP_resp_get0(bs, index))
      end

      def sign(signer_cert, signer_key, certs = nil, flags = nil, digest = nil)
        Ossl.ocsp_sign(self, Ossl::OCSP_BASICRESP, :OCSP_basic_sign, signer_cert, signer_key, certs, flags, digest)
      end

      def verify(certs, store, flags = nil) = Ossl.ocsp_verify(self, Ossl::OCSP_BASICRESP, :OCSP_basic_verify, certs, store, flags)

      def to_der = Ossl.i2d(:i2d_OCSP_BASICRESP, Ossl::OCSP_BASICRESP.fetch(self), OCSPError)
    end

    class SingleResponse
      def initialize(arg)
        Ossl.want_uninitialized(self, Ossl::OCSP_SINGLERESP)
        Ossl.ocsp_decode(self, arg, Ossl::OCSP_SINGLERESP, :d2i_OCSP_SINGLERESP)
      end

      def initialize_copy(other) = Ossl.ocsp_copy(self, other, Ossl::OCSP_SINGLERESP, :OCSP_SINGLERESP_it)

      def check_validity(nsec = nil, maxsec = nil)
        nsec = nsec.nil? ? 0 : Ossl.int(nsec)
        maxsec = maxsec.nil? ? -1 : Ossl.int(maxsec)
        _, _, _, this, nxt = Ossl.ocsp_single_status(Ossl::OCSP_SINGLERESP.fetch(self))
        return true unless Lib.OCSP_check_validity(this, nxt, nsec, maxsec).zero?

        Ossl.clear_error
        false
      end

      def certid = Ossl.ocsp_certid_new(Lib.OCSP_SINGLERESP_get0_id(Ossl::OCSP_SINGLERESP.fetch(self)))

      def cert_status = Ossl.ocsp_single_status(Ossl::OCSP_SINGLERESP.fetch(self))[0]

      def this_update = Ossl.time_or_nil(Ossl.ocsp_single_status(Ossl::OCSP_SINGLERESP.fetch(self))[3])

      def next_update = Ossl.time_or_nil(Ossl.ocsp_single_status(Ossl::OCSP_SINGLERESP.fetch(self))[4])

      def revocation_time
        status, _, revoked, = Ossl.ocsp_single_status(Ossl::OCSP_SINGLERESP.fetch(self))
        raise Ossl.error(OCSPError, "certificate is not revoked") if status != Lib::V_OCSP_CERTSTATUS_REVOKED

        Ossl.time_or_nil(revoked)
      end

      def revocation_reason
        status, reason, = Ossl.ocsp_single_status(Ossl::OCSP_SINGLERESP.fetch(self))
        raise Ossl.error(OCSPError, "certificate is not revoked") if status != Lib::V_OCSP_CERTSTATUS_REVOKED

        reason
      end

      def extensions
        single = Ossl::OCSP_SINGLERESP.fetch(self)
        Array.new(Lib.OCSP_SINGLERESP_get_ext_count(single)) { |i| Ossl.x509ext_new(Lib.OCSP_SINGLERESP_get_ext(single, i)) }
      end

      def to_der = Ossl.i2d(:i2d_OCSP_SINGLERESP, Ossl::OCSP_SINGLERESP.fetch(self), OCSPError)
    end

    class CertificateId
      def initialize_copy(other)
        Ossl::OCSP_CERTID.unshare(self, other) unless equal?(other)
        Ossl.want_uninitialized(self, Ossl::OCSP_CERTID)
        copy = Lib.OCSP_CERTID_dup(Ossl::OCSP_CERTID.fetch(other))
        raise Ossl.error(OCSPError, "OCSP_CERTID_dup") if copy.zero?

        Ossl::OCSP_CERTID.set(self, copy)
        self
      end

      def initialize(subject, issuer = (only_der = true; nil), digest = nil)
        Ossl.want_uninitialized(self, Ossl::OCSP_CERTID)
        if only_der
          der = Ossl.string_value(Ossl.to_der_if_possible(subject))
          id = Ossl.d2i(:d2i_OCSP_CERTID, der)
          raise Ossl.error(OCSPError, "d2i_OCSP_CERTID") if id.zero?
        else
          subject_x509 = Ossl.x509(subject)
          issuer_x509 = Ossl.x509(issuer)
          md, _holder = Ossl.optional_md(digest)
          id = Lib.OCSP_cert_to_id(md, subject_x509, issuer_x509)
          raise Ossl.error(OCSPError, "OCSP_cert_to_id") if id.zero?
        end
        Ossl::OCSP_CERTID.set(self, id)
        self
      end

      def cmp(other) = Lib.OCSP_id_cmp(Ossl::OCSP_CERTID.fetch(self), Ossl::OCSP_CERTID.fetch(other)).zero?

      def cmp_issuer(other) = Lib.OCSP_id_issuer_cmp(Ossl::OCSP_CERTID.fetch(self), Ossl::OCSP_CERTID.fetch(other)).zero?

      def serial = Ossl.asn1integer_to_num(Ossl.ocsp_id_info(Ossl::OCSP_CERTID.fetch(self), 3))

      def issuer_name_hash = Ossl.hex(Ossl.ocsp_id_info(Ossl::OCSP_CERTID.fetch(self), 0))

      def issuer_key_hash = Ossl.hex(Ossl.ocsp_id_info(Ossl::OCSP_CERTID.fetch(self), 2))

      def hash_algorithm = Ossl.asn1obj_to_string_long_name(Ossl.ocsp_id_info(Ossl::OCSP_CERTID.fetch(self), 1))

      def to_der = Ossl.i2d(:i2d_OCSP_CERTID, Ossl::OCSP_CERTID.fetch(self), OCSPError)
    end
  end
end
