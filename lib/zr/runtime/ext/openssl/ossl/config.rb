# frozen_string_literal: true

# ossl_config.c: OpenSSL::Config, an OpenSSL configuration file.
module OpenSSL
  Lib.attach_all(
    NCONF_new: [%i[pointer], :pointer],
    NCONF_free: [%i[pointer], :void],
    NCONF_load_bio: [%i[pointer pointer buffer], :int],
    NCONF_get_string: [%i[pointer string string], :string],
    NCONF_get_section: [%i[pointer string], :pointer],
    CONF_get1_default_config_file: [[], :pointer],
    OPENSSL_LH_doall_arg: [%i[pointer pointer pointer], :void]
  )

  class Config
    include Enumerable
  end

  class ConfigError < OpenSSLError; end

  module Ossl
    CONFIG = DataType.new("OpenSSL/CONF", Config, :NCONF_free, [RuntimeError, "CONF is not initialized"], alloc: lambda {
      Lib.NCONF_new(nil).tap { |conf| raise Ossl.error(ConfigError, "NCONF_new") if conf.zero? }
    }, shareable: true)

    class << self
      # GetConfig.
      def config_of(object) = CONFIG.fetch(object)

      # config_load_bio, which consumes the BIO.
      def config_load(conf, bio)
        line = [-1].pack("q")
        loaded = Lib.NCONF_load_bio(conf, bio, line)
        Lib.BIO_free(bio)
        if loaded.zero?
          line = line.unpack1("q")
          raise error(ConfigError, "wrong config format") if line <= 0

          raise error(ConfigError, "error in line #{line}")
        end
        clear_error
      end

      # The CONF_VALUEs of the CONF's hash, in the hash's order, as
      # [section, name, value] addresses; a section's own entry has no
      # name, and its value is the STACK of its entries.
      def config_values(conf)
        # struct conf_st: CONF_METHOD *meth, void *meth_data,
        # LHASH_OF(CONF_VALUE) *data, ...
        data = Lib.read_pointer(conf + 16)
        entries = collect { |callback, id| Lib.OPENSSL_LH_doall_arg(data, callback, id) }
        entries.map { |entry| Lib.read(entry, 24).unpack("JJJ") }
      end

      def c_string(address) = address.zero? ? nil : Lib.string(address)
    end
  end

  class Config
    def self.parse(str)
      config = Native.allocate(self)
      conf = Ossl.config_of(config)
      bio, _str = Ossl.obj2bio(str)
      Ossl.config_load(conf, bio)
      config.freeze
    end

    def self.parse_config(io)
      config = parse(io)
      config.sections.to_h { |section| [section, config[section]] }
    end

    singleton_class.alias_method :load, :new

    def initialize(filename = nil)
      conf = Ossl.config_of(self)
      Ossl.check_frozen(self)
      unless filename.nil?
        bio = Lib.BIO_new_file(Ossl.cstring_value(filename), "rb")
        raise Ossl.error(ConfigError, "BIO_new_file") if bio.zero?

        Ossl.config_load(conf, bio)
      end
      freeze
    end

    def initialize_copy(other)
      Ossl::CONFIG.unshare(self, other)
      conf = Ossl.config_of(self)
      text = other.to_s
      Ossl.check_frozen(self)
      bio, _text = Ossl.obj2bio(text)
      Ossl.config_load(conf, bio)
      freeze
    end

    def get_value(section, key)
      conf = Ossl.config_of(self)
      section = Ossl.cstring_value(section)
      key = Ossl.cstring_value(key)
      value = Lib.NCONF_get_string(conf, section.empty? ? nil : section, key)
      if value.nil?
        Ossl.clear_error
        return nil
      end
      value
    end

    def [](section)
      conf = Ossl.config_of(self)
      hash = {}
      stack = Lib.NCONF_get_section(conf, Ossl.cstring_value(section))
      if stack.zero?
        Ossl.clear_error
        return hash
      end
      Ossl.stack_items(stack).each do |entry|
        _, name, value = Lib.read(entry, 24).unpack("JJJ")
        hash[Lib.string(name)] = Lib.string(value)
      end
      hash
    end

    def sections
      values = Ossl.config_values(Ossl.config_of(self))
      values.filter_map { |section, name, _| Lib.string(section) if name.zero? }
    end

    def to_s
      text = "".b
      Ossl.config_values(Ossl.config_of(self)).each do |section, name, stack|
        next unless name.zero?

        text << "[ " << Lib.string(section) << " ]\n"
        Ossl.stack_items(stack).each do |entry|
          _, key, value = Lib.read(entry, 24).unpack("JJJ")
          text << (Ossl.c_string(key) || "None") << "=" << (Ossl.c_string(value) || "None") << "\n"
        end
        text << "\n"
      end
      text
    end

    def each
      return enum_for(:each) unless block_given?

      Ossl.config_values(Ossl.config_of(self)).each do |section, name, stack|
        next unless name.zero?

        section = Lib.string(section)
        Ossl.stack_items(stack).each do |entry|
          _, key, value = Lib.read(entry, 24).unpack("JJJ")
          yield [section, Ossl.c_string(key), Ossl.c_string(value)]
        end
      end
      self
    end

    def inspect = "#<#{self.class.name} sections=#{sections.inspect}>"

    DEFAULT_CONFIG_FILE = begin
      path = Lib.CONF_get1_default_config_file
      Lib.string(path).freeze
    ensure
      Lib.OPENSSL_free(path)
    end
  end
end
