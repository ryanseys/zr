# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_x509.c: the OpenSSL::X509 module, its default paths, and the
# conversions of certificate stacks and times the X509 files share.
module OpenSSL
  Lib.attach_all(
    X509_get_default_cert_area: [[], :string],
    X509_get_default_cert_dir: [[], :string],
    X509_get_default_cert_file: [[], :string],
    X509_get_default_cert_dir_env: [[], :string],
    X509_get_default_cert_file_env: [[], :string],
    X509_get_default_private_dir: [[], :string],
    X509_time_adj_ex: [%i[pointer int long buffer], :pointer],
    X509_up_ref: [%i[pointer], :int],
    X509_free: [%i[pointer], :void],
    X509_dup: [%i[pointer], :pointer],
    X509_ALGOR_get0: [%i[buffer pointer pointer pointer], :void]
  )

  module X509
    { CERT_AREA: :X509_get_default_cert_area, CERT_DIR: :X509_get_default_cert_dir,
      CERT_FILE: :X509_get_default_cert_file, CERT_DIR_ENV: :X509_get_default_cert_dir_env,
      CERT_FILE_ENV: :X509_get_default_cert_file_env, PRIVATE_DIR: :X509_get_default_private_dir }.each do |name, function|
      const_set(:"DEFAULT_#{name}", Lib.public_send(function).freeze)
    end
  end

  module Ossl
    class << self
      # ossl_x509_time_adjust: an ASN1_TIME for `time`, into `asn1time`
      # or a new one, which the caller frees.
      def x509_time_adjust(asn1time, time)
        seconds, days = time_split(time)
        Lib.X509_time_adj_ex(asn1time, days, 0, [seconds].pack("q"))
      end

      # ossl_x509_ary2sk: a new STACK_OF(X509) holding a reference to each
      # certificate of `array`, which the caller frees with
      # sk_X509_pop_free.
      def x509_ary2sk(array)
        check_array(array)
        stack = Lib.OPENSSL_sk_new_null
        raise error(OpenSSLError) if stack.zero?

        array.each do |certificate|
          unless certificate.is_a?(X509::Certificate)
            free_x509_stack(stack)
            raise error(OpenSSLError, "object in array not of class ##type##")
          end
          x509 = dup_x509(certificate)
          next unless Lib.OPENSSL_sk_push(stack, x509).zero?

          Lib.X509_free(x509)
          free_x509_stack(stack)
          raise error(OpenSSLError)
        end
        stack
      end

      # sk_X509_pop_free(stack, X509_free).
      def free_x509_stack(stack)
        Lib.OPENSSL_sk_pop_free(stack, Lib.function_address(:X509_free)) unless stack.nil? || stack.zero?
      end

      # ossl_x509_sk2ary.
      def x509_sk2ary(stack) = stack_items(stack).map { |x509| x509_new(x509) }

      # The OID of an X509_ALGOR, by its long name.
      def algorithm_name(algor)
        out = Lib.buffer(8)
        Lib.X509_ALGOR_get0(out, nil, nil, algor)
        asn1obj_to_string_long_name(Lib.pointer_at(out))
      end

      # A setter's time: `set1` given a fresh ASN1_TIME for `time`,
      # which is freed afterwards.
      def set_x509_time(time, klass, message)
        asn1time = x509_time_adjust(nil, time)
        begin
          raise error(klass, message) if yield(asn1time).zero?
        ensure
          Lib.ASN1_TIME_free(asn1time)
        end
      end
    end
  end
end
