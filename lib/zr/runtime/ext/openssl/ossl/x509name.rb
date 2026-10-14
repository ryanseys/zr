# frozen_string_literal: true

# ossl_x509name.c: OpenSSL::X509::Name over X509_NAME.
module OpenSSL
  Lib.attach_all(
    X509_NAME_new: [[], :pointer],
    X509_NAME_free: [%i[pointer], :void],
    X509_NAME_dup: [%i[pointer], :pointer],
    d2i_X509_NAME: [%i[buffer buffer long], :pointer],
    i2d_X509_NAME: [%i[pointer buffer], :int],
    X509_NAME_add_entry_by_txt: [%i[pointer string int buffer int int int], :int],
    X509_NAME_oneline: [%i[pointer pointer int], :pointer],
    X509_NAME_print_ex: [%i[pointer pointer int ulong], :int],
    X509_NAME_entry_count: [%i[pointer], :int],
    X509_NAME_get_entry: [%i[pointer int], :pointer],
    X509_NAME_ENTRY_get_object: [%i[pointer], :pointer],
    X509_NAME_ENTRY_get_data: [%i[pointer], :pointer],
    X509_NAME_cmp: [%i[pointer pointer], :int],
    X509_NAME_hash_ex: [%i[pointer pointer pointer buffer], :ulong],
    X509_NAME_hash_old: [%i[pointer], :ulong]
  )

  module Lib
    XN_FLAG_COMPAT = 0 # x509.h
    ASN1_STRFLGS_ESC_MSB = 4 # asn1.h

    # X509_NAME_hash (x509.h).
    def self.X509_NAME_hash(name) = X509_NAME_hash_ex(name, nil, nil, nil)
  end

  module X509
    class NameError < OpenSSLError; end

    class Name
      include Comparable
    end
  end

  module Ossl
    X509_NAME = DataType.new("OpenSSL/X509/NAME", X509::Name, :X509_NAME_free, [RuntimeError, "Name wasn't initialized."], create: lambda {
      Lib.X509_NAME_new.tap { |name| raise Ossl.error(X509::NameError) if name.zero? }
    })

    class << self
      # ossl_x509name_new.
      def x509name_new(name)
        copy = Lib.X509_NAME_dup(name)
        raise error(X509::NameError, "X509_NAME_dup") if copy.zero?

        X509_NAME.wrap(X509::Name, copy)
      end

      # x509name_print.
      def x509name_print(object, flags)
        name = X509_NAME.fetch(object)
        bio = Lib.BIO_new(Lib.BIO_s_mem)
        raise error(X509::NameError) if bio.zero?

        written = Lib.X509_NAME_print_ex(bio, name, 0, flags)
        if written.negative? || (flags == Lib::XN_FLAG_COMPAT && written.zero?)
          Lib.BIO_free(bio)
          raise error(X509::NameError, "X509_NAME_print_ex")
        end
        membio2str(bio)
      end
    end
  end

  module X509
    class Name
      def initialize(*args)
        raise ArgumentError, wrong_arity(args.size, 0..2) if args.size > 2

        Ossl.want_uninitialized(self, Ossl::X509_NAME)
        arg, template = args
        entries = Array.try_convert(arg) unless args.empty?
        if args.empty? || entries
          Ossl::X509_NAME.create(self)
          return if args.empty?

          template = OBJECT_TYPE_TEMPLATE if template.nil?
          entries.each do |entry|
            Ossl.check_array(entry)
            oid, value, type = entry
            type = template[oid] if type.nil?
            type = DEFAULT_OBJECT_TYPE if type.nil?
            Ossl.x509name_add_entry(self, oid, value, type)
          end
          return
        end
        der = Ossl.string_value(Ossl.to_der_if_possible(arg))
        decoded = Lib.d2i_X509_NAME(nil, [Native.address(der)].pack("J"), der.bytesize)
        raise Ossl.error(NameError, "d2i_X509_NAME") if decoded.zero?

        Ossl::X509_NAME.set(self, decoded)
        self
      end

      def initialize_copy(other)
        Ossl::X509_NAME.unshare(self, other) unless equal?(other)
        Ossl.want_uninitialized(self, Ossl::X509_NAME)
        copy = Lib.X509_NAME_dup(Ossl::X509_NAME.fetch(other))
        raise Ossl.error(NameError, "X509_NAME_dup") if copy.zero?

        Ossl::X509_NAME.set(self, copy)
        self
      end

      def add_entry(oid, value, type = nil, loc: -1, set: 0)
        Ossl.x509name_add_entry(self, oid, value, type, loc, set)
        self
      end

      def to_s(*args)
        raise ArgumentError, wrong_arity(args.size, 0..1) if args.size > 1
        return Ossl.x509name_print(self, Ossl.ulong(args.first)) unless args.empty? || args.first.nil?

        text = Lib.X509_NAME_oneline(Ossl::X509_NAME.fetch(self), nil, 0)
        raise Ossl.error(NameError, "X509_NAME_oneline") if text.zero?

        begin
          Lib.string(text)
        ensure
          Lib.OPENSSL_free(text)
        end
      end

      def to_utf8 = Ossl.x509name_print(self, RFC2253 & ~Lib::ASN1_STRFLGS_ESC_MSB).force_encoding(Encoding::UTF_8)

      def inspect = "#<#{self.class} #{to_utf8}>"

      def to_a
        name = Ossl::X509_NAME.fetch(self)
        Array.new(Lib.X509_NAME_entry_count(name)) do |i|
          entry = Lib.X509_NAME_get_entry(name, i)
          raise Ossl.error(NameError, "X509_NAME_get_entry") if entry.zero?

          data = Lib.X509_NAME_ENTRY_get_data(entry)
          [Ossl.asn1obj_to_string(Lib.X509_NAME_ENTRY_get_object(entry)), Ossl.asn1str_to_str(data), Lib.ASN1_STRING_type(data)]
        end
      end

      def cmp(other)
        return nil unless other.is_a?(Name)

        Lib.X509_NAME_cmp(Ossl::X509_NAME.fetch(self), Ossl::X509_NAME.fetch(other)) <=> 0
      end
      alias <=> cmp

      def eql?(other)
        return false unless other.is_a?(Name)

        Lib.X509_NAME_cmp(Ossl::X509_NAME.fetch(self), Ossl::X509_NAME.fetch(other)).zero?
      end

      def hash = Lib.X509_NAME_hash(Ossl::X509_NAME.fetch(self))

      def hash_old = Lib.X509_NAME_hash_old(Ossl::X509_NAME.fetch(self))

      def to_der = Ossl.i2d(:i2d_X509_NAME, Ossl::X509_NAME.fetch(self), NameError)

      OBJECT_TYPE_TEMPLATE = Hash.new(Lib::V_ASN1_UTF8STRING).merge!(
        "C" => Lib::V_ASN1_PRINTABLESTRING, "countryName" => Lib::V_ASN1_PRINTABLESTRING,
        "serialNumber" => Lib::V_ASN1_PRINTABLESTRING, "dnQualifier" => Lib::V_ASN1_PRINTABLESTRING,
        "DC" => Lib::V_ASN1_IA5STRING, "domainComponent" => Lib::V_ASN1_IA5STRING,
        "emailAddress" => Lib::V_ASN1_IA5STRING
      ).freeze
    end
  end

  module Ossl
    # ossl_x509name_add_entry.
    def self.x509name_add_entry(object, oid, value, type, loc = -1, set = 0)
      oid = cstring_value(oid)
      value = string_value(value)
      type = X509::Name::OBJECT_TYPE_TEMPLATE[oid] if type.nil?
      loc = int(loc)
      set = int(set)
      name = X509_NAME.fetch(object)
      raise error(X509::NameError, "X509_NAME_add_entry_by_txt") if Lib.X509_NAME_add_entry_by_txt(name, oid, int(type), value, value.bytesize, loc, set).zero?
    end
  end
end
