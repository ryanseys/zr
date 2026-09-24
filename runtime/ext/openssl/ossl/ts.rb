# frozen_string_literal: true

# ossl_ts.c: OpenSSL::Timestamp, the Time-Stamp Protocol of RFC 3161.
module OpenSSL
  Lib.attach_all(
    TS_REQ_new: [[], :pointer],
    TS_REQ_free: [%i[pointer], :void],
    TS_RESP_new: [[], :pointer],
    TS_RESP_free: [%i[pointer], :void],
    TS_TST_INFO_new: [[], :pointer],
    TS_TST_INFO_free: [%i[pointer], :void],
    TS_TST_INFO_dup: [%i[pointer], :pointer],
    d2i_TS_REQ_bio: [%i[pointer pointer], :pointer],
    i2d_TS_REQ: [%i[pointer buffer], :int],
    d2i_TS_RESP_bio: [%i[pointer pointer], :pointer],
    i2d_TS_RESP: [%i[pointer buffer], :int],
    d2i_TS_TST_INFO_bio: [%i[pointer pointer], :pointer],
    i2d_TS_TST_INFO: [%i[pointer buffer], :int],
    TS_REQ_set_version: [%i[pointer long], :int],
    TS_REQ_get_version: [%i[pointer], :long],
    TS_REQ_set_cert_req: [%i[pointer int], :int],
    TS_REQ_get_cert_req: [%i[pointer], :int],
    TS_REQ_get_msg_imprint: [%i[pointer], :pointer],
    TS_MSG_IMPRINT_get_algo: [%i[pointer], :pointer],
    TS_MSG_IMPRINT_get_msg: [%i[pointer], :pointer],
    TS_MSG_IMPRINT_set_msg: [%i[pointer buffer int], :int],
    X509_ALGOR_set0: [%i[pointer pointer int pointer], :int],
    TS_REQ_get_policy_id: [%i[pointer], :pointer],
    TS_REQ_set_policy_id: [%i[pointer pointer], :int],
    TS_REQ_get_nonce: [%i[pointer], :pointer],
    TS_REQ_set_nonce: [%i[pointer pointer], :int],
    TS_REQ_print_bio: [%i[pointer pointer], :int],
    TS_RESP_get_status_info: [%i[pointer], :pointer],
    TS_STATUS_INFO_get0_status: [%i[pointer], :pointer],
    TS_STATUS_INFO_get0_failure_info: [%i[pointer], :pointer],
    TS_STATUS_INFO_get0_text: [%i[pointer], :pointer],
    ASN1_BIT_STRING_get_bit: [%i[pointer int], :int],
    TS_RESP_get_token: [%i[pointer], :pointer],
    TS_RESP_get_tst_info: [%i[pointer], :pointer],
    PKCS7_cert_from_signer_info: [%i[pointer pointer], :pointer],
    TS_RESP_print_bio: [%i[pointer pointer], :int],
    TS_REQ_to_TS_VERIFY_CTX: [%i[pointer pointer], :pointer],
    TS_VERIFY_CTX_free: [%i[pointer], :void],
    TS_VERIFY_CTX_set0_certs: [%i[pointer pointer], :int],
    TS_VERIFY_CTX_set0_store: [%i[pointer pointer], :int],
    TS_VERIFY_CTX_set_certs: [%i[pointer pointer], :pointer],
    TS_VERIFY_CTX_set_store: [%i[pointer pointer], :pointer],
    TS_VERIFY_CTX_add_flags: [%i[pointer int], :int],
    TS_RESP_verify_response: [%i[pointer pointer], :int],
    TS_TST_INFO_get_version: [%i[pointer], :long],
    TS_TST_INFO_get_policy_id: [%i[pointer], :pointer],
    TS_TST_INFO_get_msg_imprint: [%i[pointer], :pointer],
    TS_TST_INFO_get_serial: [%i[pointer], :pointer],
    TS_TST_INFO_get_time: [%i[pointer], :pointer],
    TS_TST_INFO_get_ordering: [%i[pointer], :int],
    TS_TST_INFO_get_nonce: [%i[pointer], :pointer],
    TS_TST_INFO_print_bio: [%i[pointer pointer], :int],
    TS_RESP_CTX_new: [[], :pointer],
    TS_RESP_CTX_free: [%i[pointer], :void],
    TS_RESP_CTX_set_serial_cb: [%i[pointer pointer pointer], :void],
    TS_RESP_CTX_set_time_cb: [%i[pointer pointer pointer], :void],
    TS_RESP_CTX_set_signer_cert: [%i[pointer pointer], :int],
    TS_RESP_CTX_set_signer_key: [%i[pointer pointer], :int],
    TS_RESP_CTX_set_certs: [%i[pointer pointer], :int],
    TS_RESP_CTX_set_def_policy: [%i[pointer pointer], :int],
    TS_RESP_CTX_add_md: [%i[pointer pointer], :int],
    TS_RESP_create_response: [%i[pointer pointer], :pointer]
  )

  module Lib
    TS_VFY_SIGNATURE = 1 # ts.h
    PKCS7_SIGNED_SIGNER_INFO = 32 # PKCS7_SIGNED (pkcs7.h), after crl

    # The failure-info bits (ts.h), in the order ruby tests them.
    TS_FAILURE_INFO = {
      BAD_ALG: 0, BAD_REQUEST: 2, BAD_DATA_FORMAT: 5, TIME_NOT_AVAILABLE: 14,
      UNACCEPTED_POLICY: 15, UNACCEPTED_EXTENSION: 16, ADD_INFO_NOT_AVAILABLE: 17, SYSTEM_FAILURE: 25
    }.freeze
  end

  module Timestamp
    class TimestampError < OpenSSLError; end

    class Response; end

    class TokenInfo; end

    class Request; end

    class Factory; end
  end

  module Ossl
    TS_REQUEST = DataType.new("OpenSSL/Timestamp/Request", Timestamp::Request, :TS_REQ_free,
                              [RuntimeError, "TS_REQ wasn't initialized."], alloc: lambda {
      req = Lib.TS_REQ_new
      raise Ossl.error(Timestamp::TimestampError) if req.zero?

      Lib.TS_REQ_set_version(req, 1)
      Lib.TS_REQ_set_cert_req(req, 1)
      req
    })
    TS_RESPONSE = DataType.new("OpenSSL/Timestamp/Response", Timestamp::Response, :TS_RESP_free,
                               [RuntimeError, "TS_RESP wasn't initialized."], alloc: lambda {
      Lib.TS_RESP_new.tap { |resp| raise Ossl.error(Timestamp::TimestampError) if resp.zero? }
    })
    TS_TOKEN_INFO = DataType.new("OpenSSL/Timestamp/TokenInfo", Timestamp::TokenInfo, :TS_TST_INFO_free,
                                 [RuntimeError, "TS_TST_INFO wasn't initialized."], alloc: lambda {
      Lib.TS_TST_INFO_new.tap { |info| raise Ossl.error(Timestamp::TimestampError) if info.zero? }
    })

    # ossl_tsfac_serial_cb: gives the library the serial ASN1_INTEGER in
    # the data word, which the library frees after this.
    TS_SERIAL_CB = Lib.callback do |_ctx, data|
      serial = Lib.read_pointer(data)
      Lib.write(data, [0].pack("J"))
      serial
    end

    # ossl_tsfac_time_cb: the seconds in the data word, no microseconds.
    TS_TIME_CB = Lib.callback do |_ctx, data, sec, usec|
      Lib.write(sec, Lib.read(data, 8))
      Lib.write(usec, [0].pack("q"))
      1
    end

    class << self
      # asn1_to_der.
      def ts_to_der(function, struct) = i2d(function, struct, Timestamp::TimestampError, "Error when encoding to DER")

      # The initialize of Request, Response and TokenInfo: a struct a
      # d2i_*_bio function decodes from `der`.
      def ts_decode(object, der, type, function, message)
        bio, _bytes = obj2bio(to_der_if_possible(der))
        struct = Lib.public_send(function, bio, nil)
        Lib.BIO_free(bio)
        type.check(object)
        type.set(object, struct)
        raise error(Timestamp::TimestampError, message) if struct.zero?

        object
      end

      # The OID of a TS_MSG_IMPRINT's algorithm.
      def ts_imprint_algorithm(imprint)
        out = Lib.buffer(8)
        Lib.X509_ALGOR_get0(out, nil, nil, Lib.TS_MSG_IMPRINT_get_algo(imprint))
        Lib.pointer_at(out)
      end

      # to_text of each Timestamp class.
      def ts_text(function, struct)
        out = Lib.BIO_new(Lib.BIO_s_mem)
        raise error(Timestamp::TimestampError) if out.zero?
        if Lib.public_send(function, out, struct).zero?
          Lib.BIO_free(out)
          raise error(Timestamp::TimestampError)
        end
        membio2str(out)
      end

      # ossl_pkcs7_new.
      def pkcs7_new(p7)
        copy = Lib.PKCS7_dup(p7)
        raise error(PKCS7::PKCS7Error, "PKCS7_dup") if copy.zero?

        PKCS7_STRUCT.wrap(OpenSSL::PKCS7, copy)
      end

      # The signed content of a TS token: the PKCS7_SIGNED in its union.
      def pkcs7_signed(p7) = Lib.read_pointer(p7 + Lib::PKCS7_D)
    end
  end

  module Timestamp
    class Request
      def initialize(arg = (omitted = true; nil))
        return self if omitted

        Ossl.ts_decode(self, arg, Ossl::TS_REQUEST, :d2i_TS_REQ_bio, "Error when decoding the timestamp request")
      end

      def algorithm = Ossl.asn1obj_to_string(Ossl.ts_imprint_algorithm(Lib.TS_REQ_get_msg_imprint(Ossl::TS_REQUEST.fetch(self))))

      def algorithm=(algo)
        req = Ossl::TS_REQUEST.fetch(self)
        obj = Ossl.to_asn1obj(algo)
        algor = Lib.TS_MSG_IMPRINT_get_algo(Lib.TS_REQ_get_msg_imprint(req))
        if Lib.X509_ALGOR_set0(algor, obj, Lib::V_ASN1_NULL, nil).zero?
          Lib.ASN1_OBJECT_free(obj)
          raise Ossl.error(TimestampError, "X509_ALGOR_set0")
        end
        algo
      end

      def message_imprint = Ossl.asn1str_to_str(Lib.TS_MSG_IMPRINT_get_msg(Lib.TS_REQ_get_msg_imprint(Ossl::TS_REQUEST.fetch(self))))

      def message_imprint=(hash)
        hash = Ossl.string_value(hash)
        imprint = Lib.TS_REQ_get_msg_imprint(Ossl::TS_REQUEST.fetch(self))
        raise Ossl.error(TimestampError, "TS_MSG_IMPRINT_set_msg") if Lib.TS_MSG_IMPRINT_set_msg(imprint, hash, hash.bytesize).zero?

        hash
      end

      def version = Lib.TS_REQ_get_version(Ossl::TS_REQUEST.fetch(self))

      def version=(version)
        raise Ossl.error(TimestampError, "version must be >= 0!") if (ver = Ossl.long(version)).negative?
        raise Ossl.error(TimestampError, "TS_REQ_set_version") if Lib.TS_REQ_set_version(Ossl::TS_REQUEST.fetch(self), ver).zero?

        version
      end

      def policy_id
        id = Lib.TS_REQ_get_policy_id(Ossl::TS_REQUEST.fetch(self))
        id.zero? ? nil : Ossl.asn1obj_to_string(id)
      end

      def policy_id=(oid)
        req = Ossl::TS_REQUEST.fetch(self)
        obj = Ossl.to_asn1obj(oid)
        ok = Lib.TS_REQ_set_policy_id(req, obj)
        Lib.ASN1_OBJECT_free(obj)
        raise Ossl.error(TimestampError, "TS_REQ_set_policy_id") if ok.zero?

        oid
      end

      def nonce
        nonce = Lib.TS_REQ_get_nonce(Ossl::TS_REQUEST.fetch(self))
        nonce.zero? ? nil : Ossl.asn1integer_to_num(nonce)
      end

      def nonce=(num)
        req = Ossl::TS_REQUEST.fetch(self)
        nonce = Ossl.num_to_asn1integer(num)
        ok = Lib.TS_REQ_set_nonce(req, nonce)
        Lib.ASN1_INTEGER_free(nonce)
        raise Ossl.error(TimestampError) if ok.zero?

        num
      end

      def cert_requested? = !Lib.TS_REQ_get_cert_req(Ossl::TS_REQUEST.fetch(self)).zero?

      def cert_requested=(requested)
        Lib.TS_REQ_set_cert_req(Ossl::TS_REQUEST.fetch(self), requested ? 1 : 0)
        requested
      end

      def to_der
        req = Ossl::TS_REQUEST.fetch(self)
        imprint = Lib.TS_REQ_get_msg_imprint(req)
        raise Ossl.error(TimestampError, "Message imprint missing algorithm") if Lib.OBJ_obj2nid(Ossl.ts_imprint_algorithm(imprint)) == Lib::NID_undef
        raise Ossl.error(TimestampError, "Message imprint missing hashed message") if Lib.ASN1_STRING_length(Lib.TS_MSG_IMPRINT_get_msg(imprint)).zero?

        Ossl.ts_to_der(:i2d_TS_REQ, req)
      end

      def to_text = Ossl.ts_text(:TS_REQ_print_bio, Ossl::TS_REQUEST.fetch(self))
    end

    class Response
      def initialize(der) = Ossl.ts_decode(self, der, Ossl::TS_RESPONSE, :d2i_TS_RESP_bio, "Error when decoding the timestamp response")

      def status = Ossl.asn1integer_to_num(Lib.TS_STATUS_INFO_get0_status(Lib.TS_RESP_get_status_info(Ossl::TS_RESPONSE.fetch(self))))

      def failure_info
        info = Lib.TS_STATUS_INFO_get0_failure_info(Lib.TS_RESP_get_status_info(Ossl::TS_RESPONSE.fetch(self)))
        return nil if info.zero?

        Lib::TS_FAILURE_INFO.each { |name, bit| return name unless Lib.ASN1_BIT_STRING_get_bit(info, bit).zero? }
        raise Ossl.error(TimestampError, "Unrecognized failure info.")
      end

      def status_text
        text = Lib.TS_STATUS_INFO_get0_text(Lib.TS_RESP_get_status_info(Ossl::TS_RESPONSE.fetch(self)))
        Ossl.stack_items(text).map { |string| Ossl.asn1str_to_str(string) }
      end

      def token
        p7 = Lib.TS_RESP_get_token(Ossl::TS_RESPONSE.fetch(self))
        p7.zero? ? nil : Ossl.pkcs7_new(p7)
      end

      def token_info
        info = Lib.TS_RESP_get_tst_info(Ossl::TS_RESPONSE.fetch(self))
        return nil if info.zero?

        copy = Lib.TS_TST_INFO_dup(info)
        raise Ossl.error(TimestampError) if copy.zero?

        Ossl::TS_TOKEN_INFO.wrap(TokenInfo, copy)
      end

      def tsa_certificate
        p7 = Lib.TS_RESP_get_token(Ossl::TS_RESPONSE.fetch(self))
        return nil if p7.zero?

        signers = Lib.read_pointer(Ossl.pkcs7_signed(p7) + Lib::PKCS7_SIGNED_SIGNER_INFO)
        cert = Lib.PKCS7_cert_from_signer_info(p7, Lib.OPENSSL_sk_value(signers, 0))
        cert.zero? ? nil : Ossl.x509_new(cert)
      end

      def to_der = Ossl.ts_to_der(:i2d_TS_RESP, Ossl::TS_RESPONSE.fetch(self))

      def to_text = Ossl.ts_text(:TS_RESP_print_bio, Ossl::TS_RESPONSE.fetch(self))

      def verify(ts_req, store, intermediates = nil)
        resp = Ossl::TS_RESPONSE.fetch(self)
        req = Ossl::TS_REQUEST.fetch(ts_req)
        x509store = Ossl.x509store(store)
        ctx = Lib.TS_REQ_to_TS_VERIFY_CTX(req, nil)
        raise Ossl.error(TimestampError, "Error when creating the verification context.") if ctx.zero?

        stack = nil
        begin
          stack = intermediates.nil? ? Lib.OPENSSL_sk_new_null : Ossl.x509_ary2sk(intermediates)
        ensure
          Lib.TS_VERIFY_CTX_free(ctx) if stack.nil? || stack.zero?
        end
        raise Ossl.error(TimestampError, "sk_X509_new_null") if stack.zero?

        failure = lambda do |message|
          Ossl.free_x509_stack(stack)
          Lib.TS_VERIFY_CTX_free(ctx)
          raise Ossl.error(TimestampError, message)
        end
        p7 = Lib.TS_RESP_get_token(resp)
        failure.("TS_RESP_get_token") if p7.zero?

        Ossl.stack_items(Lib.read_pointer(Ossl.pkcs7_signed(p7) + Lib::PKCS7_SIGNED_CERT)).each do |cert|
          failure.("sk_X509_push") if Lib.OPENSSL_sk_push(stack, cert).zero?
          Lib.X509_up_ref(cert)
        end
        failure.("X509_STORE_up_ref") if Lib.X509_STORE_up_ref(x509store).zero?

        if Lib.respond_to?(:TS_VERIFY_CTX_set0_certs)
          Lib.TS_VERIFY_CTX_set0_certs(ctx, stack)
          Lib.TS_VERIFY_CTX_set0_store(ctx, x509store)
        else
          Lib.TS_VERIFY_CTX_set_certs(ctx, stack)
          Lib.TS_VERIFY_CTX_set_store(ctx, x509store)
        end
        Lib.TS_VERIFY_CTX_add_flags(ctx, Lib::TS_VFY_SIGNATURE)
        ok = Lib.TS_RESP_verify_response(ctx, resp)
        Lib.TS_VERIFY_CTX_free(ctx)
        raise Ossl.error(TimestampError, "TS_RESP_verify_response") if ok.zero?

        self
      end
    end

    class TokenInfo
      def initialize(der) = Ossl.ts_decode(self, der, Ossl::TS_TOKEN_INFO, :d2i_TS_TST_INFO_bio, "Error when decoding the timestamp token info")

      def version = Lib.TS_TST_INFO_get_version(Ossl::TS_TOKEN_INFO.fetch(self))

      def policy_id = Ossl.asn1obj_to_string(Lib.TS_TST_INFO_get_policy_id(Ossl::TS_TOKEN_INFO.fetch(self)))

      def algorithm = Ossl.asn1obj_to_string(Ossl.ts_imprint_algorithm(Lib.TS_TST_INFO_get_msg_imprint(Ossl::TS_TOKEN_INFO.fetch(self))))

      def message_imprint = Ossl.asn1str_to_str(Lib.TS_MSG_IMPRINT_get_msg(Lib.TS_TST_INFO_get_msg_imprint(Ossl::TS_TOKEN_INFO.fetch(self))))

      def serial_number = Ossl.asn1integer_to_num(Lib.TS_TST_INFO_get_serial(Ossl::TS_TOKEN_INFO.fetch(self)))

      def gen_time = Ossl.asn1time_to_time(Lib.TS_TST_INFO_get_time(Ossl::TS_TOKEN_INFO.fetch(self)))

      def ordering = !Lib.TS_TST_INFO_get_ordering(Ossl::TS_TOKEN_INFO.fetch(self)).zero?

      def nonce
        nonce = Lib.TS_TST_INFO_get_nonce(Ossl::TS_TOKEN_INFO.fetch(self))
        nonce.zero? ? nil : Ossl.asn1integer_to_num(nonce)
      end

      def to_der = Ossl.ts_to_der(:i2d_TS_TST_INFO, Ossl::TS_TOKEN_INFO.fetch(self))

      def to_text = Ossl.ts_text(:TS_TST_INFO_print_bio, Ossl::TS_TOKEN_INFO.fetch(self))
    end

    class Factory
      # rb_attr: the C reads each through its instance variable.
      %i[allowed_digests default_policy_id serial_number gen_time additional_certs].each do |name|
        variable = :"@#{name}"
        define_method(name) { instance_variable_get(variable) }
        define_method(:"#{name}=") { |value| instance_variable_set(variable, value) }
      end

      def create_timestamp(key, certificate, request)
        tsresp = Native.allocate(Response)
        tsa_cert = Ossl.x509(certificate)
        sign_key = Ossl.private_pkey(key)
        req = Ossl::TS_REQUEST.fetch(request)
        serial_holder = Lib.buffer(8)
        def_policy_id_obj = ctx = nil
        begin
          gen_time = instance_variable_get(:@gen_time)
          raise Ossl.error(TimestampError, "@gen_time must be a Time.") unless gen_time.instance_of?(Time)

          seconds = [Ossl.long(gen_time.to_i)].pack("q")
          serial_number = instance_variable_get(:@serial_number)
          raise Ossl.error(TimestampError, "@serial_number must be set.") if serial_number.nil?

          Lib.write(Native.address(serial_holder), [Ossl.num_to_asn1integer(serial_number)].pack("J"))
          def_policy_id = instance_variable_get(:@default_policy_id)
          request_policy = Lib.TS_REQ_get_policy_id(req)
          raise Ossl.error(TimestampError, "No policy id in the request and no default policy set") if def_policy_id.nil? && request_policy.zero?

          def_policy_id_obj = Ossl.to_asn1obj(def_policy_id) if !def_policy_id.nil? && request_policy.zero?
          ctx = Lib.TS_RESP_CTX_new
          raise Ossl.error(TimestampError, "Memory allocation failed.") if ctx.zero?

          Lib.TS_RESP_CTX_set_serial_cb(ctx, Ossl::TS_SERIAL_CB, serial_holder)
          raise Ossl.error(TimestampError, "Certificate does not contain the timestamping extension") if Lib.TS_RESP_CTX_set_signer_cert(ctx, tsa_cert).zero?

          additional_certs = instance_variable_get(:@additional_certs)
          if additional_certs.is_a?(Array)
            inter_certs = Ossl.x509_ary2sk(additional_certs)
            Lib.TS_RESP_CTX_set_certs(ctx, inter_certs)
            Ossl.free_x509_stack(inter_certs)
          end
          Lib.TS_RESP_CTX_set_signer_key(ctx, sign_key)
          Lib.TS_RESP_CTX_set_def_policy(ctx, def_policy_id_obj) if def_policy_id_obj
          Lib.TS_RESP_CTX_set_def_policy(ctx, request_policy) unless request_policy.zero?
          Lib.TS_RESP_CTX_set_time_cb(ctx, Ossl::TS_TIME_CB, seconds)
          allowed_digests = instance_variable_get(:@allowed_digests)
          holders = []
          if allowed_digests.is_a?(Array)
            allowed_digests.each do |digest|
              md, holder = Ossl.fetch_md(digest)
              holders << holder
              return nil if Lib.TS_RESP_CTX_add_md(ctx, md).zero?
            end
          end
          str = Ossl.to_der(request)
          req_bio, _bytes = Ossl.obj2bio(str)
          response = Lib.TS_RESP_create_response(ctx, req_bio)
          Lib.BIO_free(req_bio)
          raise Ossl.error(TimestampError, "Error during response generation") if response.zero?

          Ossl.clear_error
          Ossl::TS_RESPONSE.set(tsresp, response)
          tsresp
        ensure
          Lib.ASN1_INTEGER_free(Lib.pointer_at(serial_holder))
          Lib.ASN1_OBJECT_free(def_policy_id_obj) if def_policy_id_obj
          Lib.TS_RESP_CTX_free(ctx) if ctx
        end
      end
    end
  end
end
