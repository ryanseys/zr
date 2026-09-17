# frozen_string_literal: true

# ossl_x509attr.c: OpenSSL::X509::Attribute over X509_ATTRIBUTE.
module OpenSSL
  Lib.attach_all(
    X509_ATTRIBUTE_new: [[], :pointer],
    X509_ATTRIBUTE_free: [%i[pointer], :void],
    X509_ATTRIBUTE_dup: [%i[pointer], :pointer],
    d2i_X509_ATTRIBUTE: [%i[buffer buffer long], :pointer],
    i2d_X509_ATTRIBUTE: [%i[pointer buffer], :int],
    X509_ATTRIBUTE_set1_object: [%i[pointer pointer], :int],
    X509_ATTRIBUTE_get0_object: [%i[pointer], :pointer],
    X509_ATTRIBUTE_count: [%i[pointer], :int],
    X509_ATTRIBUTE_create_by_OBJ: [%i[pointer pointer int pointer int], :pointer],
    X509_ATTRIBUTE_set1_data: [%i[pointer int pointer int], :int],
    X509_ATTRIBUTE_get0_type: [%i[pointer int], :pointer],
    d2i_ASN1_SET_ANY: [%i[pointer buffer long], :pointer],
    i2d_ASN1_SET_ANY: [%i[pointer buffer], :int],
    ASN1_TYPE_get: [%i[pointer], :int]
  )

  module X509
    class AttributeError < OpenSSLError; end

    class Attribute; end
  end

  module Ossl
    X509_ATTR = DataType.new("OpenSSL/X509/ATTRIBUTE", X509::Attribute, :X509_ATTRIBUTE_free, [RuntimeError, "ATTR wasn't initialized!"], alloc: lambda {
      Lib.X509_ATTRIBUTE_new.tap { |attr| raise Ossl.error(X509::AttributeError) if attr.zero? }
    })

    # ossl_x509attr_new.
    def self.x509attr_new(attr)
      copy = Lib.X509_ATTRIBUTE_dup(attr)
      raise error(X509::AttributeError, "X509_ATTRIBUTE_dup") if copy.zero?

      X509_ATTR.wrap(X509::Attribute, copy)
    end

    # sk_ASN1_TYPE_pop_free(stack, ASN1_TYPE_free).
    def self.free_asn1_type_stack(stack) = Lib.OPENSSL_sk_pop_free(stack, Lib.function_address(:ASN1_TYPE_free))
  end

  module X509
    class Attribute
      def initialize(*args)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

        Ossl::X509_ATTR.fetch(self)
        oid, value = args
        if args.size == 1
          der = Ossl.string_value(Ossl.to_der_if_possible(oid))
          holder = [Ossl::X509_ATTR.take(self)].pack("J")
          decoded = Lib.d2i_X509_ATTRIBUTE(holder, [Native.address(der)].pack("J"), der.bytesize)
          Ossl::X509_ATTR.set(self, Lib.pointer_at(holder))
          raise Ossl.error(AttributeError) if decoded.zero?

          return self
        end
        self.oid = oid
        self.value = value
        self
      end

      def initialize_copy(other)
        Ossl.check_frozen(self)
        Ossl::X509_ATTR.unshare(self, other)
        Ossl::X509_ATTR.fetch(self)
        copy = Lib.X509_ATTRIBUTE_dup(Ossl::X509_ATTR.fetch(other))
        raise Ossl.error(AttributeError, "X509_ATTRIBUTE_dup") if copy.zero?

        Ossl::X509_ATTR.set(self, copy)
        self
      end

      def oid=(oid)
        attr = Ossl::X509_ATTR.fetch(self)
        object = Lib.OBJ_txt2obj(Ossl.cstring_value(oid), 0)
        raise Ossl.error(AttributeError) if object.zero?

        begin
          raise Ossl.error(AttributeError, "X509_ATTRIBUTE_set1_object") if Lib.X509_ATTRIBUTE_set1_object(attr, object).zero?
        ensure
          Lib.ASN1_OBJECT_free(object)
        end
        oid
      end

      def oid = Ossl.asn1obj_to_string(Lib.X509_ATTRIBUTE_get0_object(Ossl::X509_ATTR.fetch(self)))

      def value=(value)
        attr = Ossl::X509_ATTR.fetch(self)
        Ossl.check_kind(value, ASN1::ASN1Data)
        der = Ossl.to_der(value)
        stack = Ossl.d2i(:d2i_ASN1_SET_ANY, der)
        raise Ossl.error(AttributeError, "attribute value must be ASN1::Set") if stack.zero?

        begin
          unless Lib.X509_ATTRIBUTE_count(attr).zero?
            fresh = Lib.X509_ATTRIBUTE_create_by_OBJ(nil, Lib.X509_ATTRIBUTE_get0_object(attr), 0, nil, -1)
            raise Ossl.error(AttributeError, "X509_ATTRIBUTE_create_by_OBJ") if fresh.zero?

            Ossl::X509_ATTR.set(self, fresh)
            attr = fresh
          end
          Ossl.stack_items(stack).each do |type|
            # ASN1_TYPE: int type, then the value's pointer.
            data = Lib.read_pointer(type + 8)
            raise Ossl.error(AttributeError, "X509_ATTRIBUTE_set1_data") if Lib.X509_ATTRIBUTE_set1_data(attr, Lib.ASN1_TYPE_get(type), data, -1).zero?
          end
        ensure
          Ossl.free_asn1_type_stack(stack)
        end
        value
      end

      def value
        attr = Ossl::X509_ATTR.fetch(self)
        stack = Lib.OPENSSL_sk_new_null
        raise Ossl.error(AttributeError, "sk_new") if stack.zero?

        begin
          Lib.X509_ATTRIBUTE_count(attr).times { |i| Lib.OPENSSL_sk_push(stack, Lib.X509_ATTRIBUTE_get0_type(attr, i)) }
          der = Ossl.i2d(:i2d_ASN1_SET_ANY, stack, AttributeError)
        ensure
          Lib.OPENSSL_sk_free(stack)
        end
        ASN1.decode(der)
      end

      def to_der = Ossl.i2d(:i2d_X509_ATTRIBUTE, Ossl::X509_ATTR.fetch(self), AttributeError)
    end
  end
end
