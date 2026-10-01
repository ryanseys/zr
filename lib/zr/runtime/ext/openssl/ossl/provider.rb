# frozen_string_literal: true

# ossl_provider.c: OpenSSL::Provider, the OpenSSL 3 providers a program
# loads.
module OpenSSL
  Lib.attach_all(
    OSSL_PROVIDER_load: [%i[pointer string], :pointer],
    OSSL_PROVIDER_unload: [%i[pointer], :int],
    OSSL_PROVIDER_get0_name: [%i[pointer], :string],
    OSSL_PROVIDER_do_all: [%i[pointer pointer pointer], :int]
  )

  class Provider
    class ProviderError < OpenSSLError; end

    Native.undef_allocator(self)
  end

  module Ossl
    # The provider is OpenSSL's until unloaded; nothing frees it.
    PROVIDER = DataType.new("OpenSSL/Provider", Provider, nil, [RuntimeError, "PROVIDER wasn't initialized."])
  end

  class Provider
    def self.load(name)
      name = Ossl.cstring_value(name)
      provider = Lib.OSSL_PROVIDER_load(nil, name)
      raise Ossl.error(ProviderError, "Failed to load #{name} provider") if provider.zero?

      Ossl::PROVIDER.wrap(self, provider)
    end

    def self.provider_names
      result = 1
      providers = Ossl.collect { |callback, id| result = Lib.OSSL_PROVIDER_do_all(nil, callback, id) }
      raise Ossl.error(ProviderError, "Failed to load provider names") if result != 1

      providers.map { |provider| Lib.OSSL_PROVIDER_get0_name(provider) }
    end

    def unload
      provider = Ossl::PROVIDER.get(self)
      raise Ossl.error(ProviderError, "Provider already unloaded.") if provider.nil?
      raise Ossl.error(ProviderError, "Failed to unload provider") if Lib.OSSL_PROVIDER_unload(provider) != 1

      Ossl::PROVIDER.set(self, nil)
      true
    end

    def name
      provider = Ossl::PROVIDER.get(self)
      raise Ossl.error(ProviderError, "Provider already unloaded.") if provider.nil?

      Lib.OSSL_PROVIDER_get0_name(provider)
    end

    def inspect
      provider = Ossl::PROVIDER.get(self)
      return "#<#{self.class} unloaded provider>" if provider.nil?

      "#<#{self.class} name=\"#{Lib.OSSL_PROVIDER_get0_name(provider)}\">"
    end
  end
end
