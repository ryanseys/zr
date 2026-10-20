# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_ssl_session.c: OpenSSL::SSL::Session over SSL_SESSION.
module OpenSSL
  Lib.attach_all(
    SSL_SESSION_free: [%i[pointer], :void],
    SSL_SESSION_up_ref: [%i[pointer], :int],
    SSL_get1_session: [%i[pointer], :pointer],
    PEM_read_bio_SSL_SESSION: [%i[pointer pointer pointer pointer], :pointer],
    ASN1_dup: [%i[pointer pointer pointer], :pointer],
    SSL_SESSION_get_id: [%i[pointer buffer], :pointer],
    SSL_SESSION_get_protocol_version: [%i[pointer], :int],
    SSL_SESSION_get_time: [%i[pointer], :long],
    SSL_SESSION_set_time: [%i[pointer long], :long],
    SSL_SESSION_get_timeout: [%i[pointer], :long],
    SSL_SESSION_set_timeout: [%i[pointer long], :long],
    i2d_SSL_SESSION: [%i[pointer buffer], :int],
    PEM_write_bio_SSL_SESSION: [%i[pointer pointer], :int],
    SSL_SESSION_print: [%i[pointer pointer], :int]
  )

  module Lib
    # d2i_SSL_SESSION_bio (ssl.h).
    def self.d2i_SSL_SESSION_bio(bio, out) = ASN1_d2i_bio(function_address(:SSL_SESSION_new), function_address(:d2i_SSL_SESSION), bio, out)
  end

  module SSL
    class SSLError < OpenSSLError; end

    class Session
      class SessionError < OpenSSLError; end
    end

    class SSLSocket; end
  end

  module Ossl
    SSL_SESSION = DataType.new("OpenSSL/SSL/Session", SSL::Session, :SSL_SESSION_free, [RuntimeError, "SSL Session wasn't initialized."])

    # A Session holding a reference to `session`, as the session callbacks
    # hand one to Ruby.
    def self.ssl_session_new(session)
      Lib.SSL_SESSION_up_ref(session)
      SSL_SESSION.wrap(SSL::Session, session)
    end
  end

  module SSL
    class Session
      def initialize(arg)
        Ossl.want_uninitialized(self, Ossl::SSL_SESSION)

        session = if arg.instance_of?(SSLSocket)
                    Lib.SSL_get1_session(Ossl.ssl(arg)).tap { |s| raise Ossl.error(SessionError, "no session available") if s.zero? }
                  else
                    bio, _arg = Ossl.obj2bio(arg)
                    s = Lib.d2i_SSL_SESSION_bio(bio, nil)
                    if s.zero?
                      Ossl.bio_reset(bio)
                      s = Lib.PEM_read_bio_SSL_SESSION(bio, nil, nil, nil)
                    end
                    Lib.BIO_free(bio)
                    raise Ossl.error(ArgumentError, "unknown type") if s.zero?

                    s
                  end
        Ossl::SSL_SESSION.set(self, session)
        self
      end

      def initialize_copy(other)
        Ossl::SSL_SESSION.unshare(self, other) unless equal?(other)
        Ossl.want_uninitialized(self, Ossl::SSL_SESSION)
        copy = Lib.ASN1_dup(Lib.function_address(:i2d_SSL_SESSION), Lib.function_address(:d2i_SSL_SESSION), Ossl::SSL_SESSION.fetch(other))
        raise Ossl.error(SessionError, "ASN1_dup") if copy.zero?

        Ossl::SSL_SESSION.set(self, copy)
        self
      end

      def ==(other)
        a = Ossl::SSL_SESSION.fetch(self)
        b = Ossl::SSL_SESSION.fetch(other)
        a_length = Lib.buffer(4)
        b_length = Lib.buffer(4)
        a_id = Lib.SSL_SESSION_get_id(a, a_length)
        b_id = Lib.SSL_SESSION_get_id(b, b_length)
        return false if Lib.SSL_SESSION_get_protocol_version(a) != Lib.SSL_SESSION_get_protocol_version(b)
        return false if a_length != b_length

        Lib.CRYPTO_memcmp(a_id, b_id, a_length.unpack1("L")).zero?
      end

      def time
        seconds = Lib.SSL_SESSION_get_time(Ossl::SSL_SESSION.fetch(self))
        seconds.zero? ? nil : Time.at(seconds)
      end

      def time=(time)
        session = Ossl::SSL_SESSION.fetch(self)
        time = time.to_i if time.instance_of?(Time)
        Lib.SSL_SESSION_set_time(session, Ossl.long(time))
        self.time
      end

      def timeout = Lib.SSL_SESSION_get_timeout(Ossl::SSL_SESSION.fetch(self))

      def timeout=(timeout)
        Lib.SSL_SESSION_set_timeout(Ossl::SSL_SESSION.fetch(self), Ossl.long(timeout))
        self.timeout
      end

      def id
        length = Lib.buffer(4)
        id = Lib.SSL_SESSION_get_id(Ossl::SSL_SESSION.fetch(self), length)
        Lib.read(id, length.unpack1("L"))
      end

      def to_der = Ossl.i2d(:i2d_SSL_SESSION, Ossl::SSL_SESSION.fetch(self), SessionError, "i2d_SSL_SESSION")

      def to_pem
        session = Ossl::SSL_SESSION.fetch(self)
        Ossl.bio_output(SessionError, "SSL_SESSION_print()") { |bio| Lib.PEM_write_bio_SSL_SESSION(bio, session) }
      end

      def to_text
        session = Ossl::SSL_SESSION.fetch(self)
        Ossl.bio_output(SessionError, "SSL_SESSION_print()") { |bio| Lib.SSL_SESSION_print(bio, session) }
      end
    end
  end
end
