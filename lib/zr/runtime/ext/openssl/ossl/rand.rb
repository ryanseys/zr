# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_rand.c: OpenSSL::Random, OpenSSL's CSPRNG.
module OpenSSL
  Lib.attach_all(
    RAND_seed: [%i[buffer int], :void],
    RAND_add: [%i[buffer int double], :void],
    RAND_load_file: [%i[string long], :int],
    RAND_write_file: [%i[string], :int],
    RAND_bytes: [%i[buffer int], :int],
    RAND_status: [[], :int]
  )

  module Random
    class RandomError < OpenSSLError; end

    module_function

    def seed(str)
      str = Ossl.string_value(str)
      Lib.RAND_seed(str, Ossl.int(str.bytesize))
      str
    end

    def random_add(str, entropy)
      str = Ossl.string_value(str)
      Lib.RAND_add(str, Ossl.int(str.bytesize), Ossl.double(entropy))
      self
    end

    def load_random_file(filename)
      raise Ossl.error(RandomError) if Lib.RAND_load_file(Ossl.cstring_value(filename), -1).zero?

      true
    end

    def write_random_file(filename)
      raise Ossl.error(RandomError) if Lib.RAND_write_file(Ossl.cstring_value(filename)) == -1

      true
    end

    def random_bytes(len)
      n = Ossl.int(len)
      out = Lib.buffer(n)
      case Lib.RAND_bytes(out, n)
      when 0 then raise Ossl.error(RandomError, "RAND_bytes")
      when -1 then raise Ossl.error(RandomError, "RAND_bytes is not supported")
      end
      out
    end

    def status? = Lib.RAND_status != 0

    singleton_class.alias_method :pseudo_bytes, :random_bytes
  end
end
