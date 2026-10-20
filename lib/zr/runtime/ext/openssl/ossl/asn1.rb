# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_asn1.c: OpenSSL::ASN1, DER in and out through the library's
# ASN1_get_object and i2d/d2i functions, and the conversions between
# ASN1_* values and Ruby objects every other file uses.
module OpenSSL
  Lib.attach_all(
    ASN1_get_object: [%i[buffer buffer buffer buffer long], :int],
    ASN1_put_object: [%i[buffer int int int int], :void],
    ASN1_put_eoc: [%i[buffer], :int],
    ASN1_object_size: [%i[int int int], :int],
    ASN1_TIME_to_tm: [%i[pointer buffer], :int],
    ASN1_STRING_get0_data: [%i[pointer], :pointer],
    ASN1_STRING_length: [%i[pointer], :int],
    ASN1_STRING_type: [%i[pointer], :int],
    ASN1_STRING_new: [[], :pointer],
    ASN1_STRING_set: [%i[pointer buffer int], :int],
    ASN1_STRING_free: [%i[pointer], :void],
    ASN1_ENUMERATED_to_BN: [%i[pointer pointer], :pointer],
    ASN1_INTEGER_to_BN: [%i[pointer pointer], :pointer],
    BN_to_ASN1_INTEGER: [%i[pointer pointer], :pointer],
    BN_value_one: [[], :pointer],
    ASN1_INTEGER_free: [%i[pointer], :void],
    ASN1_ENUMERATED_free: [%i[pointer], :void],
    ASN1_BIT_STRING_new: [[], :pointer],
    ASN1_BIT_STRING_free: [%i[pointer], :void],
    ASN1_BIT_STRING_set1: [%i[pointer buffer size_t int], :int],
    ASN1_BIT_STRING_get_length: [%i[pointer buffer buffer], :int],
    ASN1_NULL_new: [[], :pointer],
    ASN1_NULL_free: [%i[pointer], :void],
    ASN1_TIME_free: [%i[pointer], :void],
    ASN1_UTCTIME_adj: [%i[pointer long int long], :pointer],
    ASN1_GENERALIZEDTIME_adj: [%i[pointer long int long], :pointer],
    ASN1_TYPE_new: [[], :pointer],
    ASN1_TYPE_set: [%i[pointer int pointer], :void],
    ASN1_TYPE_free: [%i[pointer], :void],
    i2d_ASN1_TYPE: [%i[pointer buffer], :int],
    d2i_ASN1_INTEGER: [%i[pointer buffer long], :pointer],
    d2i_ASN1_ENUMERATED: [%i[pointer buffer long], :pointer],
    d2i_ASN1_BIT_STRING: [%i[pointer buffer long], :pointer],
    d2i_ASN1_NULL: [%i[pointer buffer long], :pointer],
    d2i_ASN1_OBJECT: [%i[pointer buffer long], :pointer],
    d2i_ASN1_TIME: [%i[pointer buffer long], :pointer],
    OBJ_obj2txt: [%i[buffer int pointer int], :int],
    OBJ_nid2ln: [%i[int], :string],
    OBJ_txt2nid: [%i[string], :int],
    OBJ_create: [%i[string string string], :int]
  )

  module Lib
    V_ASN1_UNIVERSAL = 0x00 # asn1.h
    V_ASN1_APPLICATION = 0x40
    V_ASN1_CONTEXT_SPECIFIC = 0x80
    V_ASN1_PRIVATE = 0xc0
    V_ASN1_CONSTRUCTED = 0x20
    V_ASN1_EOC = 0
    V_ASN1_BOOLEAN = 1
    V_ASN1_INTEGER = 2
    V_ASN1_BIT_STRING = 3
    V_ASN1_OCTET_STRING = 4
    V_ASN1_NULL = 5
    V_ASN1_OBJECT = 6
    V_ASN1_ENUMERATED = 10
    V_ASN1_UTF8STRING = 12
    V_ASN1_SEQUENCE = 16
    V_ASN1_SET = 17
    V_ASN1_NUMERICSTRING = 18
    V_ASN1_PRINTABLESTRING = 19
    V_ASN1_T61STRING = 20
    V_ASN1_VIDEOTEXSTRING = 21
    V_ASN1_IA5STRING = 22
    V_ASN1_UTCTIME = 23
    V_ASN1_GENERALIZEDTIME = 24
    V_ASN1_GRAPHICSTRING = 25
    V_ASN1_ISO64STRING = 26
    V_ASN1_GENERALSTRING = 27
    V_ASN1_UNIVERSALSTRING = 28
    V_ASN1_BMPSTRING = 30
    ASN1_STRING_FLAG_BITS_LEFT = 0x08
    NID_undef = 0 # obj_mac.h

    # struct asn1_string_st: int length, int type, unsigned char *data,
    # long flags.
    ASN1_STRING_FLAGS_OFFSET = 16

    unless respond_to?(:ASN1_BIT_STRING_set1)
      # openssl_missing.h: the bits left over, from before OpenSSL 4.0
      # offered a function for them.
      def self.ASN1_BIT_STRING_set1(bitstr, data, length, unused_bits)
        return 0 if length > 0x7fff_ffff || ASN1_STRING_set(bitstr, data, length).zero?

        flags = Native.read(bitstr + ASN1_STRING_FLAGS_OFFSET, 8).unpack1("q")
        flags = (flags & ~(ASN1_STRING_FLAG_BITS_LEFT | 0x07)) | ASN1_STRING_FLAG_BITS_LEFT | unused_bits
        Native.write(bitstr + ASN1_STRING_FLAGS_OFFSET, [flags].pack("q"))
        1
      end

      def self.ASN1_BIT_STRING_get_length(bitstr, length, unused_bits)
        length[0, 8] = [ASN1_STRING_length(bitstr)].pack("J")
        unused_bits[0, 4] = [Native.read(bitstr + ASN1_STRING_FLAGS_OFFSET, 8).unpack1("q") & 0x07].pack("l")
        1
      end
    end
  end

  module ASN1
    class ASN1Error < OpenSSLError; end

    # The UNIVERSAL tags by number, where the C extension gives a name.
    UNIVERSAL_TAG_NAME = %w[
      EOC BOOLEAN INTEGER BIT_STRING OCTET_STRING NULL OBJECT OBJECT_DESCRIPTOR
      EXTERNAL REAL ENUMERATED EMBEDDED_PDV UTF8STRING RELATIVE_OID
    ].then { |names| names + [nil, nil] + %w[
      SEQUENCE SET NUMERICSTRING PRINTABLESTRING T61STRING VIDEOTEXSTRING IA5STRING
      UTCTIME GENERALIZEDTIME GRAPHICSTRING ISO64STRING GENERALSTRING UNIVERSALSTRING
      CHARACTER_STRING BMPSTRING
    ] }.map { |name| name&.freeze }.freeze

    class ASN1Data
      def value = @value
      def value=(value)
        @value = value
      end

      def tag = @tag
      def tag=(tag)
        @tag = tag
      end

      def tag_class = @tag_class
      def tag_class=(tag_class)
        @tag_class = tag_class
      end

      def indefinite_length = @indefinite_length
      def indefinite_length=(indefinite_length)
        @indefinite_length = indefinite_length
      end
      alias infinite_length indefinite_length
      alias infinite_length= indefinite_length=

      def initialize(value, tag, tag_class) = Ossl.asn1data_initialize(self, value, tag, tag_class)

      def to_der
        if @value.is_a?(Array)
          Ossl.asn1_constructive_to_der(self)
        else
          raise Ossl.error(ASN1Error, "indefinite length form cannot be used with primitive encoding") if @indefinite_length

          Ossl.asn1_primitive_to_der(self)
        end
      end
    end

    class Primitive < ASN1Data
      def tagging = @tagging
      def tagging=(tagging)
        @tagging = tagging
      end

      undef_method :indefinite_length=, :infinite_length=

      def initialize(value, *rest)
        raise ArgumentError, wrong_arity(rest.size + 1, 1..4) if rest.size > 3

        tag, tagging, tag_class = rest
        Ossl.asn1_initialize(self, value, tag, tagging, tag_class, rest.size + 1)
      end

      def to_der = Ossl.asn1_primitive_to_der(self)
    end

    class Constructive < ASN1Data
      include Enumerable

      def tagging = @tagging
      def tagging=(tagging)
        @tagging = tagging
      end

      def initialize(value, *rest)
        raise ArgumentError, wrong_arity(rest.size + 1, 1..4) if rest.size > 3

        tag, tagging, tag_class = rest
        Ossl.asn1_initialize(self, value, tag, tagging, tag_class, rest.size + 1)
      end

      def to_der = Ossl.asn1_constructive_to_der(self)

      def each(&block)
        @value.each(&block)
        self
      end
    end

    %i[Boolean Integer Enumerated BitString OctetString UTF8String NumericString PrintableString
       T61String VideotexString IA5String GraphicString ISO64String GeneralString UniversalString
       BMPString Null ObjectId UTCTime GeneralizedTime].each { |name| const_set(name, Class.new(Primitive)) }
    %i[Sequence Set].each { |name| const_set(name, Class.new(Constructive)) }
    const_set(:EndOfContent, Class.new(ASN1Data))

    %i[Boolean Integer Enumerated BitString OctetString UTF8String NumericString PrintableString
       T61String VideotexString IA5String GraphicString ISO64String GeneralString UniversalString
       BMPString Null ObjectId UTCTime GeneralizedTime Sequence Set EndOfContent].each do |name|
      klass = const_get(name)
      define_method(name, &Ractor.make_shareable(proc { |*args| klass.new(*args) }))
      module_function name
    end

    class ObjectId
      def self.register(oid, sn, ln)
        oid = Ossl.cstring_value(oid)
        sn = Ossl.cstring_value(sn)
        ln = Ossl.cstring_value(ln)
        raise Ossl.error(ASN1Error) if Lib.OBJ_create(oid, sn, ln).zero?

        true
      end

      def sn
        nid = Lib.OBJ_txt2nid(Ossl.cstring_value(@value))
        nid == Lib::NID_undef ? nil : Lib.string(Lib.OBJ_nid2sn(nid))
      end
      alias short_name sn

      def ln
        nid = Lib.OBJ_txt2nid(Ossl.cstring_value(@value))
        nid == Lib::NID_undef ? nil : Lib.OBJ_nid2ln(nid)
      end
      alias long_name ln

      def oid
        object = Ossl.to_asn1obj(@value)
        Ossl.asn1obj_to_string_oid(object)
      ensure
        Lib.ASN1_OBJECT_free(object) if object
      end

      def ==(other)
        return false unless other.is_a?(ObjectId)

        oid == other.oid
      end
    end

    class BitString
      def unused_bits = @unused_bits
      def unused_bits=(unused_bits)
        @unused_bits = unused_bits
      end
    end

    class EndOfContent
      def initialize
        @tag = 0
        @value = "".b
        @tagging = nil
        @tag_class = :UNIVERSAL
        @indefinite_length = false
      end

      def to_der = "\0\0".b
    end

    module_function

    def traverse(obj)
      Ossl::ASN1Decoder.new(obj, ->(row) { yield row }).decode_one
      nil
    end

    def decode(obj) = Ossl::ASN1Decoder.new(obj, nil).decode_one

    def decode_all(obj) = Ossl::ASN1Decoder.new(obj, nil).decode_all
  end

  module Ossl
    # The class each UNIVERSAL tag decodes to, and the tag each class
    # encodes with.
    ASN1_CLASS_TAGS = {
      ASN1::EndOfContent => Lib::V_ASN1_EOC, ASN1::Boolean => Lib::V_ASN1_BOOLEAN,
      ASN1::Integer => Lib::V_ASN1_INTEGER, ASN1::BitString => Lib::V_ASN1_BIT_STRING,
      ASN1::OctetString => Lib::V_ASN1_OCTET_STRING, ASN1::Null => Lib::V_ASN1_NULL,
      ASN1::ObjectId => Lib::V_ASN1_OBJECT, ASN1::Enumerated => Lib::V_ASN1_ENUMERATED,
      ASN1::UTF8String => Lib::V_ASN1_UTF8STRING, ASN1::Sequence => Lib::V_ASN1_SEQUENCE,
      ASN1::Set => Lib::V_ASN1_SET, ASN1::NumericString => Lib::V_ASN1_NUMERICSTRING,
      ASN1::PrintableString => Lib::V_ASN1_PRINTABLESTRING, ASN1::T61String => Lib::V_ASN1_T61STRING,
      ASN1::VideotexString => Lib::V_ASN1_VIDEOTEXSTRING, ASN1::IA5String => Lib::V_ASN1_IA5STRING,
      ASN1::UTCTime => Lib::V_ASN1_UTCTIME, ASN1::GeneralizedTime => Lib::V_ASN1_GENERALIZEDTIME,
      ASN1::GraphicString => Lib::V_ASN1_GRAPHICSTRING, ASN1::ISO64String => Lib::V_ASN1_ISO64STRING,
      ASN1::GeneralString => Lib::V_ASN1_GENERALSTRING, ASN1::UniversalString => Lib::V_ASN1_UNIVERSALSTRING,
      ASN1::BMPString => Lib::V_ASN1_BMPSTRING
    }.freeze
    ASN1_TAG_CLASSES = ASN1_CLASS_TAGS.invert.freeze

    class << self
      # asn1time_to_time.
      def asn1time_to_time(time)
        tm = Lib.buffer(64)
        raise error(ASN1::ASN1Error, "ASN1_TIME_to_tm") if Lib.ASN1_TIME_to_tm(time, tm).zero?

        sec, min, hour, mday, mon, year = tm.unpack("l6")
        begin
          Time.utc(year + 1900, mon + 1, mday, hour, min, sec)
        rescue ArgumentError
          raise ASN1::ASN1Error, "invalid time"
        end
      end

      # ossl_time_split: `time` as the seconds into its day and the days
      # since the epoch, as ASN1_TIME_adj takes them.
      def time_split(time)
        number = Kernel.Integer(time)
        if number.between?(-(1 << 62), (1 << 62) - 1)
          seconds = number.remainder(86_400)
          [seconds, int((number - seconds) / 86_400)]
        else
          [long(number % 86_400), int(number / 86_400)]
        end
      end

      # asn1str_to_str.
      def asn1str_to_str(str) = Lib.read(Lib.ASN1_STRING_get0_data(str), Lib.ASN1_STRING_length(str))

      # asn1integer_to_num: an ASN1_INTEGER or ASN1_ENUMERATED as a BN.
      def asn1integer_to_num(ai)
        raise error(TypeError, "ASN1_INTEGER is NULL!") if ai.nil? || ai.zero?

        number = bn_new(Lib.BN_value_one)
        bn = BIGNUM.fetch(number)
        converted = if Lib.ASN1_STRING_type(ai) == Lib::V_ASN1_ENUMERATED
                      Lib.ASN1_ENUMERATED_to_BN(ai, bn)
                    else
                      Lib.ASN1_INTEGER_to_BN(ai, bn)
                    end
        raise error(OpenSSLError) if converted.zero?

        number
      end

      # num_to_asn1integer: a BN or an Integer into `ai`, or a new
      # ASN1_INTEGER for nil.
      def num_to_asn1integer(object, ai = nil)
        raise error(TypeError, "Can't convert nil into Integer") if object.nil?

        bn = to_bn(object)
        ai = Lib.BN_to_ASN1_INTEGER(bn_of(bn), ai)
        raise error(OpenSSLError) if ai.zero?

        ai
      end

      # ossl_asn1obj_to_string_oid: the dotted form of an ASN1_OBJECT.
      def asn1obj_to_string_oid(object)
        text = Lib.buffer(128)
        length = Lib.OBJ_obj2txt(text, 128, object, 1)
        raise error(OpenSSLError, "OBJ_obj2txt") if length <= 0 || length == 0x7fff_ffff

        if length > 127
          text = Lib.buffer(length + 1)
          length = Lib.OBJ_obj2txt(text, length + 1, object, 1)
          raise error(OpenSSLError, "OBJ_obj2txt") if length <= 0
        end
        text.byteslice(0, length).force_encoding(Encoding::US_ASCII)
      end

      # ossl_asn1obj_to_string: the short name, or the dotted form.
      def asn1obj_to_string(object)
        nid = Lib.OBJ_obj2nid(object)
        nid == Lib::NID_undef ? asn1obj_to_string_oid(object) : Lib.string(Lib.OBJ_nid2sn(nid))
      end

      # ossl_asn1obj_to_string_long_name.
      def asn1obj_to_string_long_name(object)
        nid = Lib.OBJ_obj2nid(object)
        nid == Lib::NID_undef ? asn1obj_to_string_oid(object) : Lib.OBJ_nid2ln(nid)
      end

      # ossl_to_asn1obj: an ASN1_OBJECT from a name or dotted form, which
      # the caller frees.
      def to_asn1obj(object)
        text = cstring_value(object)
        a1obj = Lib.OBJ_txt2obj(text, 0)
        a1obj = Lib.OBJ_txt2obj(text, 1) if a1obj.zero?
        raise error(ASN1::ASN1Error, "invalid OBJECT ID #{object}") if a1obj.zero?

        a1obj
      end

      # ossl_asn1_default_tag: the UNIVERSAL tag `object`'s class encodes
      # with, or -1.
      def asn1_default_tag(object)
        klass = object.class
        until klass.nil?
          tag = ASN1_CLASS_TAGS[klass]
          return tag if tag

          klass = klass.superclass
        end
        -1
      end

      # ossl_asn1data_initialize.
      def asn1data_initialize(object, value, tag, tag_class)
        raise error(ASN1::ASN1Error, "invalid tag class") unless tag_class.is_a?(Symbol)

        object.instance_variable_set(:@tag, tag)
        object.instance_variable_set(:@value, value)
        object.instance_variable_set(:@tag_class, tag_class)
        object.instance_variable_set(:@indefinite_length, false)
        object
      end

      # ossl_asn1_initialize.
      def asn1_initialize(object, value, tag, tagging, tag_class, argc)
        default_tag = asn1_default_tag(object)
        if default_tag == -1 || argc > 1
          raise error(ASN1::ASN1Error, "must specify tag number") if tag.nil?
          raise error(ASN1::ASN1Error, "invalid tagging method") unless tagging.nil? || tagging.is_a?(Symbol)

          tag_class ||= tagging.nil? ? :UNIVERSAL : :CONTEXT_SPECIFIC
          raise error(ASN1::ASN1Error, "invalid tag class") unless tag_class.is_a?(Symbol)
        else
          tag = default_tag
          tagging = nil
          tag_class = :UNIVERSAL
        end
        object.instance_variable_set(:@tag, tag)
        object.instance_variable_set(:@value, value)
        object.instance_variable_set(:@tagging, tagging)
        object.instance_variable_set(:@tag_class, tag_class)
        object.instance_variable_set(:@indefinite_length, false)
        object.instance_variable_set(:@unused_bits, 0) if default_tag == Lib::V_ASN1_BIT_STRING
        object
      end

      # ossl_asn1_tag.
      def asn1_tag(object)
        tag = object.instance_variable_get(:@tag)
        raise error(ASN1::ASN1Error, "tag number not specified") if tag.nil?

        int(tag)
      end

      # ossl_asn1_tag_class.
      def asn1_tag_class(object)
        case object.instance_variable_get(:@tag_class)
        when nil, :UNIVERSAL then Lib::V_ASN1_UNIVERSAL
        when :APPLICATION then Lib::V_ASN1_APPLICATION
        when :CONTEXT_SPECIFIC then Lib::V_ASN1_CONTEXT_SPECIFIC
        when :PRIVATE then Lib::V_ASN1_PRIVATE
        else raise error(ASN1::ASN1Error, "invalid tag class")
        end
      end

      # ossl_asn1_class2sym.
      def asn1_class_symbol(tag_class)
        if tag_class & Lib::V_ASN1_PRIVATE == Lib::V_ASN1_PRIVATE then :PRIVATE
        elsif tag_class & Lib::V_ASN1_CONTEXT_SPECIFIC == Lib::V_ASN1_CONTEXT_SPECIFIC then :CONTEXT_SPECIFIC
        elsif tag_class & Lib::V_ASN1_APPLICATION == Lib::V_ASN1_APPLICATION then :APPLICATION
        else :UNIVERSAL
        end
      end

      # to_der_internal: `body` wrapped in the identifier and length
      # octets `object`'s tag, class and tagging give it.
      def asn1_to_der_internal(object, constructed, indefinite, body)
        encoding = constructed ? (indefinite ? 2 : 1) : 0
        tag_class = asn1_tag_class(object)
        tag_number = asn1_tag(object)
        default_tag = asn1_default_tag(object)
        body_length = body.bytesize
        if object.instance_variable_get(:@tagging) == :EXPLICIT
          outer_encoding = indefinite ? 2 : 1
          raise error(ASN1::ASN1Error, "explicit tagging of unknown tag") if default_tag == -1

          inner_length = Lib.ASN1_object_size(encoding, body_length, default_tag)
          total_length = Lib.ASN1_object_size(outer_encoding, inner_length, tag_number)
          out = Lib.buffer(total_length)
          cursor = [Native.address(out)].pack("J")
          Lib.ASN1_put_object(cursor, outer_encoding, inner_length, tag_number, tag_class)
          Lib.ASN1_put_object(cursor, encoding, body_length, default_tag, Lib::V_ASN1_UNIVERSAL)
          write_at_cursor(cursor, body)
          if indefinite
            Lib.ASN1_put_eoc(cursor)
            Lib.ASN1_put_eoc(cursor)
          end
        else
          total_length = Lib.ASN1_object_size(encoding, body_length, tag_number)
          out = Lib.buffer(total_length)
          cursor = [Native.address(out)].pack("J")
          Lib.ASN1_put_object(cursor, encoding, body_length, tag_number, tag_class)
          write_at_cursor(cursor, body)
          Lib.ASN1_put_eoc(cursor) if indefinite
        end
        out
      end

      # memcpy(p, body, n); p += n.
      def write_at_cursor(cursor, bytes)
        address = cursor.unpack1("J")
        Lib.write(address, bytes) unless bytes.empty?
        cursor[0, 8] = [address + bytes.bytesize].pack("J")
      end

      # ossl_asn1prim_to_der.
      def asn1_primitive_to_der(object)
        if asn1_default_tag(object) == -1
          value = string_value(object.instance_variable_get(:@value))
          return asn1_to_der_internal(object, false, false, value)
        end

        asn1 = asn1_type(object)
        begin
          length = Lib.i2d_ASN1_TYPE(asn1, nil)
          raise error(ASN1::ASN1Error, "i2d_ASN1_TYPE") if length.negative?

          der = Lib.buffer(length)
          raise error(ASN1::ASN1Error, "i2d_ASN1_TYPE") if Lib.i2d_ASN1_TYPE(asn1, [Native.address(der)].pack("J")).negative?
        ensure
          Lib.ASN1_TYPE_free(asn1)
        end
        header = [Native.address(der)].pack("J")
        body_length = Lib.buffer(8)
        tag, tag_class = Array.new(2) { Lib.buffer(4) }
        raise error(ASN1::ASN1Error, "ASN1_get_object") if Lib.ASN1_get_object(header, body_length, tag, tag_class, length) & 0x80 != 0

        body_length = body_length.unpack1("q")
        asn1_to_der_internal(object, false, false, der.byteslice(length - body_length, body_length))
      end

      # ossl_asn1cons_to_der.
      def asn1_constructive_to_der(object)
        indefinite = object.instance_variable_get(:@indefinite_length) ? true : false
        items = object.instance_variable_get(:@value)
        items = items.is_a?(Array) ? items : Array.try_convert(items) || convert_to_array(items)
        body = "".b
        items.each_with_index do |item, i|
          if indefinite && item.is_a?(ASN1::EndOfContent)
            raise error(ASN1::ASN1Error, "illegal EOC octets in value") if i != items.size - 1

            break
          end
          body << string_value(to_der_if_possible(item))
        end
        asn1_to_der_internal(object, true, indefinite, body)
      end

      # rb_convert_type(value, T_ARRAY, "Array", "to_a").
      def convert_to_array(value)
        raise TypeError, "can't convert #{conversion_name(value)} into Array" unless value.respond_to?(:to_a)

        array = value.to_a
        raise TypeError, cant_convert_gives(value, "Array", :to_a, array) unless array.is_a?(Array)

        array
      end

      # ossl_asn1_get_asn1type: an ASN1_TYPE holding `object`'s value,
      # which the caller frees.
      def asn1_type(object)
        tag = asn1_default_tag(object)
        value = object.instance_variable_get(:@value)
        pointer, free = case tag
                        when Lib::V_ASN1_BOOLEAN
                          raise error(TypeError, "Can't convert nil into Boolean") if value.nil?

                          [value ? 0xff : 0, nil]
                        when Lib::V_ASN1_INTEGER, Lib::V_ASN1_ENUMERATED
                          [num_to_asn1integer(value), :ASN1_INTEGER_free]
                        when Lib::V_ASN1_BIT_STRING
                          [asn1_bit_string(value, int(object.instance_variable_get(:@unused_bits))), :ASN1_BIT_STRING_free]
                        when Lib::V_ASN1_NULL
                          raise error(ASN1::ASN1Error, "nil expected") unless value.nil?

                          null = Lib.ASN1_NULL_new
                          raise error(ASN1::ASN1Error) if null.zero?

                          [null, :ASN1_NULL_free]
                        when Lib::V_ASN1_OCTET_STRING, Lib::V_ASN1_UTF8STRING, Lib::V_ASN1_NUMERICSTRING,
                             Lib::V_ASN1_PRINTABLESTRING, Lib::V_ASN1_T61STRING, Lib::V_ASN1_VIDEOTEXSTRING,
                             Lib::V_ASN1_IA5STRING, Lib::V_ASN1_GRAPHICSTRING, Lib::V_ASN1_ISO64STRING,
                             Lib::V_ASN1_GENERALSTRING, Lib::V_ASN1_UNIVERSALSTRING, Lib::V_ASN1_BMPSTRING
                          [asn1_string(string_value(value)), :ASN1_STRING_free]
                        when Lib::V_ASN1_OBJECT
                          [to_asn1obj(value), :ASN1_OBJECT_free]
                        when Lib::V_ASN1_UTCTIME
                          [asn1_time(value) { |seconds, days| Lib.ASN1_UTCTIME_adj(nil, seconds, days, 0) }, :ASN1_TIME_free]
                        when Lib::V_ASN1_GENERALIZEDTIME
                          [asn1_time(value) { |seconds, days| Lib.ASN1_GENERALIZEDTIME_adj(nil, seconds, days, 0) }, :ASN1_TIME_free]
                        when Lib::V_ASN1_SET, Lib::V_ASN1_SEQUENCE
                          [asn1_string(to_der(object)), :ASN1_STRING_free]
                        else
                          raise error(ASN1::ASN1Error, "unsupported ASN.1 type")
                        end
        type = Lib.ASN1_TYPE_new
        if type.zero?
          Lib.public_send(free, pointer) if free
          raise error(ASN1::ASN1Error, "ASN1_TYPE alloc failure")
        end
        Lib.ASN1_TYPE_set(type, tag, pointer)
        type
      end

      # obj_to_asn1str and obj_to_asn1derstr.
      def asn1_string(bytes)
        str = Lib.ASN1_STRING_new
        raise error(ASN1::ASN1Error) if str.zero?

        Lib.ASN1_STRING_set(str, bytes, int(bytes.bytesize))
        str
      end

      # obj_to_asn1bstr.
      def asn1_bit_string(value, unused_bits)
        raise error(ASN1::ASN1Error, "unused_bits for a bitstring value must be in the range 0 to 7") unless unused_bits.between?(0, 7)

        value = string_value(value)
        bstr = Lib.ASN1_BIT_STRING_new
        raise error(ASN1::ASN1Error, "ASN1_BIT_STRING_new") if bstr.zero?
        raise error(ASN1::ASN1Error, "ASN1_BIT_STRING_set1") if Lib.ASN1_BIT_STRING_set1(bstr, value, value.bytesize, unused_bits).zero?

        bstr
      end

      # obj_to_asn1utime and obj_to_asn1gtime.
      def asn1_time(value)
        seconds, days = time_split(value)
        time = yield(seconds, days)
        raise error(ASN1::ASN1Error) if time.zero?

        time
      end
    end

    # ossl_asn1_decode0 and its kin, over one DER String: `row`, when
    # given, receives each header as traverse yields it.
    class ASN1Decoder
      MAX_NESTING_DEPTH = 200

      def initialize(object, row)
        object = Ossl.to_der_if_possible(object)
        @der = Ossl.string_value(object).dup.freeze
        @base = Native.address(@der)
        @position = 0
        @row = row
      end

      def decode_one
        length = @der.bytesize
        value, read, offset = decode(length, 0, 0)
        check(length, read, offset)
        value
      end

      def decode_all
        length = @der.bytesize
        remaining = length
        read = 0
        offset = 0
        values = []
        while remaining.positive?
          value, part, offset = decode(remaining, offset, 0)
          values << value
          read += part
          remaining -= part
        end
        check(length, read, offset)
        values
      end

      private

      # int_ossl_decode_sanity_check.
      def check(length, read, offset)
        return if length.zero? || (read == length && offset == length)

        raise Ossl.error(ASN1::ASN1Error, "Type mismatch. Total bytes read: #{read} Bytes available: #{length} Offset: #{offset}")
      end

      # ossl_asn1_decode0: the value at the position, the bytes it took,
      # and the offset after it. Constructed values nest at most
      # MAX_NESTING_DEPTH deep.
      def decode(length, offset, depth)
        raise Ossl.error(ASN1::ASN1Error, "nesting depth #{depth} exceeds limit") if depth > MAX_NESTING_DEPTH

        cursor = [@base + @position].pack("J")
        len = Lib.buffer(8)
        tag, tag_class = Array.new(2) { Lib.buffer(4) }
        j = Lib.ASN1_get_object(cursor, len, tag, tag_class, length)
        len = len.unpack1("q")
        tag = tag.unpack1("l")
        tag_class = tag_class.unpack1("l")
        raise Ossl.error(ASN1::ASN1Error) if j & 0x80 != 0
        raise Ossl.error(ASN1::ASN1Error, "value is too short") if len > length

        symbol = Ossl.asn1_class_symbol(tag_class)
        header = cursor.unpack1("J") - (@base + @position)
        @row&.call([depth, offset, header, len, j & Lib::V_ASN1_CONSTRUCTED != 0, symbol, tag])
        if j & Lib::V_ASN1_CONSTRUCTED != 0
          @position += header
          offset += header
          value, read, offset = decode_constructive(length - header, len, offset, depth, j, tag, symbol)
          read += header
        else
          raise Ossl.error(ASN1::ASN1Error, "indefinite length for primitive value") if j & 0x01 != 0 && len.zero?

          value, read = decode_primitive(len, header, tag, symbol)
          offset += header + len
        end
        raise Ossl.error(ASN1::ASN1Error, "Type mismatch. Bytes read: #{read} Bytes available: #{header + len}") if len != 0 && read != header + len

        [value, read, offset]
      end

      # int_ossl_asn1_decode0_prim.
      def decode_primitive(length, header, tag, tag_class)
        start = @base + @position
        unused_bits = 0
        value = if tag_class == :UNIVERSAL && tag < ASN1::UNIVERSAL_TAG_NAME.size
                  case tag
                  when Lib::V_ASN1_EOC then decode_eoc(header + length)
                  when Lib::V_ASN1_BOOLEAN then decode_boolean(header + length)
                  when Lib::V_ASN1_INTEGER then decode_d2i(:d2i_ASN1_INTEGER, :ASN1_INTEGER_free, start, header + length) { |ai| Ossl.asn1integer_to_num(ai) }
                  when Lib::V_ASN1_BIT_STRING then decode_bit_string(start, header + length).tap { |_, bits| unused_bits = bits }.first
                  when Lib::V_ASN1_NULL then decode_d2i(:d2i_ASN1_NULL, :ASN1_NULL_free, start, header + length) { nil }
                  when Lib::V_ASN1_ENUMERATED then decode_d2i(:d2i_ASN1_ENUMERATED, :ASN1_ENUMERATED_free, start, header + length) { |ai| Ossl.asn1integer_to_num(ai) }
                  when Lib::V_ASN1_OBJECT then decode_d2i(:d2i_ASN1_OBJECT, :ASN1_OBJECT_free, start, header + length, "d2i_ASN1_OBJECT") { |obj| Ossl.asn1obj_to_string(obj) }
                  when Lib::V_ASN1_UTCTIME, Lib::V_ASN1_GENERALIZEDTIME then decode_d2i(:d2i_ASN1_TIME, :ASN1_TIME_free, start, header + length) { |time| Ossl.asn1time_to_time(time) }
                  else @der.byteslice(@position + header, length)
                  end
                else
                  @der.byteslice(@position + header, length)
                end
        @position += header + length
        klass = Ossl::ASN1_TAG_CLASSES[tag] if tag_class == :UNIVERSAL
        data = if klass
                 Ossl.asn1_initialize(Native.allocate(klass), value, tag, nil, tag_class, 4).tap do |object|
                   object.instance_variable_set(:@unused_bits, unused_bits) if tag == Lib::V_ASN1_BIT_STRING
                 end
               else
                 Ossl.asn1data_initialize(Native.allocate(ASN1::ASN1Data), value, tag, tag_class)
               end
        [data, header + length]
      end

      # int_ossl_asn1_decode0_cons.
      def decode_constructive(max_length, length, offset, depth, j, tag, tag_class)
        indefinite = j == 0x21
        items = []
        available = indefinite ? max_length : length
        read = 0
        while available.positive?
          value, inner, offset = decode(available, offset, depth + 1)
          read += inner
          available -= inner
          if indefinite
            break if Ossl.asn1_tag(value) == Lib::V_ASN1_EOC && value.instance_variable_get(:@tag_class) == :UNIVERSAL
            raise Ossl.error(ASN1::ASN1Error, "EOC missing in indefinite length encoding") if available.zero?
          end
          items << value
        end
        data = if tag_class == :UNIVERSAL
                 klass = tag == Lib::V_ASN1_SEQUENCE || tag == Lib::V_ASN1_SET ? Ossl::ASN1_TAG_CLASSES[tag] : ASN1::Constructive
                 Ossl.asn1_initialize(Native.allocate(klass), items, tag, nil, tag_class, 4)
               else
                 Ossl.asn1data_initialize(Native.allocate(ASN1::ASN1Data), items, tag, tag_class)
               end
        data.instance_variable_set(:@indefinite_length, indefinite)
        [data, read, offset]
      end

      # decode_eoc.
      def decode_eoc(length)
        raise Ossl.error(ASN1::ASN1Error) unless length == 2 && @der.byteslice(@position, 2) == "\0\0".b

        "".b
      end

      # decode_bool.
      def decode_boolean(length)
        raise Ossl.error(ASN1::ASN1Error, "invalid length for BOOLEAN") if length != 3

        bytes = @der.byteslice(@position, 3).bytes
        raise Ossl.error(ASN1::ASN1Error, "invalid BOOLEAN") if bytes[0] != 1 || bytes[1] != 1

        bytes[2] != 0
      end

      # decode_int, decode_enum, decode_null, decode_obj and decode_time: a
      # d2i function's value handed to the block, then freed.
      def decode_d2i(d2i, free, start, length, message = nil)
        value = Lib.public_send(d2i, nil, [start].pack("J"), length)
        raise Ossl.error(ASN1::ASN1Error, message) if value.zero?

        begin
          yield value
        ensure
          Lib.public_send(free, value)
        end
      end

      # decode_bstr: the bits and the count of bits unused in the last
      # byte.
      def decode_bit_string(start, length)
        bstr = Lib.d2i_ASN1_BIT_STRING(nil, [start].pack("J"), length)
        raise Ossl.error(ASN1::ASN1Error, "d2i_ASN1_BIT_STRING") if bstr.zero?

        begin
          size = Lib.buffer(8)
          unused = Lib.buffer(4)
          raise Ossl.error(ASN1::ASN1Error, "ASN1_BIT_STRING_get_length") if Lib.ASN1_BIT_STRING_get_length(bstr, size, unused).zero?

          [Lib.read(Lib.ASN1_STRING_get0_data(bstr), size.unpack1("J")), unused.unpack1("l")]
        ensure
          Lib.ASN1_BIT_STRING_free(bstr)
        end
      end
    end
  end
end
