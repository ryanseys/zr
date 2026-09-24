# frozen_string_literal: true

# ossl_pkey_ec.c: OpenSSL::PKey::EC, and its Group and Point.
module OpenSSL
  Lib.attach_all(
    EVP_PKEY_get0_EC_KEY: [%i[pointer], :pointer],
    EC_KEY_new: [[], :pointer],
    EC_KEY_free: [%i[pointer], :void],
    EC_KEY_set_group: [%i[pointer pointer], :int],
    EC_KEY_new_by_curve_name: [%i[int], :pointer],
    EC_KEY_set_asn1_flag: [%i[pointer int], :void],
    EC_KEY_set_conv_form: [%i[pointer int], :void],
    EC_KEY_generate_key: [%i[pointer], :int],
    EC_KEY_get0_group: [%i[pointer], :pointer],
    EC_KEY_get0_private_key: [%i[pointer], :pointer],
    EC_KEY_get0_public_key: [%i[pointer], :pointer],
    EC_GROUP_free: [%i[pointer], :void],
    EC_GROUP_dup: [%i[pointer], :pointer],
    EC_GROUP_new_by_curve_name: [%i[int], :pointer],
    EC_GROUP_new_curve_GFp: [%i[pointer pointer pointer pointer], :pointer],
    EC_GROUP_new_curve_GF2m: [%i[pointer pointer pointer pointer], :pointer],
    EC_GROUP_set_asn1_flag: [%i[pointer int], :void],
    EC_GROUP_get_asn1_flag: [%i[pointer], :int],
    EC_GROUP_set_point_conversion_form: [%i[pointer int], :void],
    EC_GROUP_get_point_conversion_form: [%i[pointer], :int],
    EC_GROUP_cmp: [%i[pointer pointer pointer], :int],
    EC_GROUP_get0_generator: [%i[pointer], :pointer],
    EC_GROUP_set_generator: [%i[pointer pointer pointer pointer], :int],
    EC_GROUP_get_order: [%i[pointer pointer pointer], :int],
    EC_GROUP_get_cofactor: [%i[pointer pointer pointer], :int],
    EC_GROUP_get_curve_name: [%i[pointer], :int],
    EC_GROUP_get_seed_len: [%i[pointer], :size_t],
    EC_GROUP_get0_seed: [%i[pointer], :pointer],
    EC_GROUP_set_seed: [%i[pointer buffer size_t], :size_t],
    EC_GROUP_get_degree: [%i[pointer], :int],
    EC_get_builtin_curves: [%i[buffer size_t], :size_t],
    ECPKParameters_print: [%i[pointer pointer int], :int],
    PEM_read_bio_ECPKParameters: [%i[pointer pointer pointer pointer], :pointer],
    PEM_write_bio_ECPKParameters: [%i[pointer pointer], :int],
    ASN1_i2d_bio: [%i[pointer pointer pointer], :int],
    EC_POINT_new: [%i[pointer], :pointer],
    EC_POINT_free: [%i[pointer], :void],
    EC_POINT_clear_free: [%i[pointer], :void],
    EC_POINT_dup: [%i[pointer pointer], :pointer],
    EC_POINT_bn2point: [%i[pointer pointer pointer pointer], :pointer],
    EC_POINT_oct2point: [%i[pointer pointer buffer size_t pointer], :int],
    EC_POINT_point2oct: [%i[pointer pointer int buffer size_t pointer], :size_t],
    EC_POINT_cmp: [%i[pointer pointer pointer pointer], :int],
    EC_POINT_is_at_infinity: [%i[pointer pointer], :int],
    EC_POINT_is_on_curve: [%i[pointer pointer pointer], :int],
    EC_POINT_invert: [%i[pointer pointer pointer], :int],
    EC_POINT_set_to_infinity: [%i[pointer pointer], :int],
    EC_POINT_add: [%i[pointer pointer pointer pointer pointer], :int],
    EC_POINT_mul: [%i[pointer pointer pointer pointer pointer pointer], :int]
  )

  module Lib
    OPENSSL_EC_NAMED_CURVE = 0x001 # ec.h
    POINT_CONVERSION_COMPRESSED = 2
    POINT_CONVERSION_UNCOMPRESSED = 4
    POINT_CONVERSION_HYBRID = 6

    # d2i_ECPKParameters_bio (ec.h).
    def self.d2i_ECPKParameters_bio(bio, out) = ASN1_d2i_bio(nil, function_address(:d2i_ECPKParameters), bio, out)

    # i2d_ECPKParameters_bio (ec.h).
    def self.i2d_ECPKParameters_bio(bio, group) = ASN1_i2d_bio(function_address(:i2d_ECPKParameters), bio, group)
  end

  module PKey
    class EC < PKey
      class Group
        class Error < OpenSSLError; end
      end

      class Point
        class Error < OpenSSLError; end
      end
    end
  end

  module Ossl
    EC_GROUP = DataType.new("OpenSSL/ec_group", PKey::EC::Group, :EC_GROUP_free, [PKey::EC::Group::Error, "EC_GROUP is not initialized"])
    EC_POINT = DataType.new("OpenSSL/EC_POINT", PKey::EC::Point, :EC_POINT_clear_free, [PKey::EC::Point::Error, "EC_POINT is not initialized"])

    POINT_CONVERSION_FORMS = {
      uncompressed: Lib::POINT_CONVERSION_UNCOMPRESSED,
      compressed: Lib::POINT_CONVERSION_COMPRESSED,
      hybrid: Lib::POINT_CONVERSION_HYBRID
    }.freeze

    class << self
      def ec(object) = legacy_key(object, Lib::EVP_PKEY_EC, "EC_KEY", :EVP_PKEY_get0_EC_KEY)

      # EC keys name their own type in the Get macro's message.
      def ec_pkey(object) = typed_pkey(object, Lib::EVP_PKEY_EC, "EC PKEY")

      # ec_key_new_from_group: an EC_KEY over a Group, or over the named
      # curve `arg` names.
      def ec_key_new_from_group(arg)
        if arg.is_a?(PKey::EC::Group)
          group = EC_GROUP.fetch(arg)
          ec = Lib.EC_KEY_new
          raise error(PKey::PKeyError) if ec.zero?

          if Lib.EC_KEY_set_group(ec, group).zero?
            Lib.EC_KEY_free(ec)
            raise error(PKey::PKeyError)
          end
        else
          nid = Lib.OBJ_sn2nid(cstring_value(arg))
          raise error(PKey::PKeyError, "invalid curve name") if nid == Lib::NID_undef

          ec = Lib.EC_KEY_new_by_curve_name(nid)
          raise error(PKey::PKeyError) if ec.zero?

          Lib.EC_KEY_set_asn1_flag(ec, Lib::OPENSSL_EC_NAMED_CURVE)
          Lib.EC_KEY_set_conv_form(ec, Lib::POINT_CONVERSION_UNCOMPRESSED)
        end
        ec
      end

      # ec_group_new: a Group holding a copy of `group`.
      def ec_group_new(group)
        copy = Lib.EC_GROUP_dup(group)
        raise error(PKey::EC::Group::Error, "EC_GROUP_dup") if copy.zero?

        EC_GROUP.wrap(PKey::EC::Group, copy)
      end

      # ec_point_new: a Point holding a copy of `point`, on a copy of
      # `group`.
      def ec_point_new(point, group)
        copy = Lib.EC_POINT_dup(point, group)
        raise error(PKey::EC::Point::Error, "EC_POINT_dup") if copy.zero?

        object = EC_POINT.wrap(PKey::EC::Point, copy)
        object.instance_variable_set(:@group, ec_group_new(group))
        object
      end

      # GetECPointGroup.
      def ec_point_group(point) = EC_GROUP.fetch(point.instance_variable_get(:@group))

      # parse_point_conversion_form_symbol.
      def point_conversion_form(symbol)
        POINT_CONVERSION_FORMS.fetch(symbol) do
          raise error(ArgumentError, "unsupported point conversion form #{symbol.inspect} (expected :compressed, :uncompressed, or :hybrid)")
        end
      end

      # ossl_ec_group_eql.
      def ec_group_eql(a, b)
        case Lib.EC_GROUP_cmp(EC_GROUP.fetch(a), EC_GROUP.fetch(b), bn_ctx)
        when 0 then true
        when 1 then false
        else raise error(PKey::EC::Group::Error, "EC_GROUP_cmp")
        end
      end

      # ossl_ec_group_to_string.
      def ec_group_to_string(object, der)
        group = EC_GROUP.fetch(object)
        bio = Lib.BIO_new(Lib.BIO_s_mem)
        raise error(PKey::EC::Group::Error, "BIO_new(BIO_s_mem())") if bio.zero?

        written = der ? Lib.i2d_ECPKParameters_bio(bio, group) : Lib.PEM_write_bio_ECPKParameters(bio, group)
        if written != 1
          Lib.BIO_free(bio)
          raise error(PKey::PKeyError)
        end
        membio2str(bio)
      end

      # A BN whose BIGNUM a group function fills.
      def ec_group_bn(object, function, name)
        group = EC_GROUP.fetch(object)
        number = bn_new(Lib.BN_value_one)
        raise error(PKey::EC::Group::Error, name) if Lib.public_send(function, group, BIGNUM.fetch(number), bn_ctx) != 1

        number
      end

      # A Point on `point`'s group, as ossl_ec_point_initialize makes one
      # from a group alone.
      def ec_point_on_group(group_object) = ec_point_initialize(Native.allocate(PKey::EC::Point), [group_object])

      # ossl_ec_group_initialize with one argument: a copy of a Group, the
      # parameters in PEM or DER, or a named curve.
      def ec_group_from(arg)
        if arg.is_a?(PKey::EC::Group)
          group = Lib.EC_GROUP_dup(EC_GROUP.fetch(arg))
          raise error(PKey::EC::Group::Error, "EC_GROUP_dup") if group.zero?

          return group
        end
        bio, text = obj2bio(arg)
        group = Lib.PEM_read_bio_ECPKParameters(bio, nil, nil, nil)
        if group.zero?
          bio_reset(bio)
          group = Lib.d2i_ECPKParameters_bio(bio, nil)
        end
        Lib.BIO_free(bio)
        return group unless group.zero?

        name = cstring_value(text)
        nid = Lib.OBJ_sn2nid(name)
        clear_error
        raise error(PKey::EC::Group::Error, "unknown curve name (#{text})") if nid == Lib::NID_undef

        group = Lib.EC_GROUP_new_by_curve_name(nid)
        raise error(PKey::EC::Group::Error, "unable to create curve (#{text})") if group.zero?

        Lib.EC_GROUP_set_asn1_flag(group, Lib::OPENSSL_EC_NAMED_CURVE)
        Lib.EC_GROUP_set_point_conversion_form(group, Lib::POINT_CONVERSION_UNCOMPRESSED)
        group
      end

      # ossl_ec_group_initialize with four arguments: a curve over GF(p)
      # or GF(2^m).
      def ec_group_curve(field, p, a, b)
        raise error(ArgumentError, "unknown argument, must be :GFp or :GF2m") unless field.is_a?(Symbol)

        p = to_bn(p)
        a = to_bn(a)
        b = to_bn(b)
        function = { GFp: :EC_GROUP_new_curve_GFp, GF2m: :EC_GROUP_new_curve_GF2m }[field]
        function = nil if function && !Lib.respond_to?(function)
        raise error(ArgumentError, "unknown symbol, must be :GFp or :GF2m") if function.nil?

        group = Lib.public_send(function, bn_of(p), bn_of(a), bn_of(b), bn_ctx)
        raise error(PKey::EC::Group::Error, "EC_GROUP_new_by_GF*") if group.zero?

        group
      end

      # ossl_ec_point_initialize.
      def ec_point_initialize(object, args)
        raise PKey::EC::Point::Error, "EC_POINT already initialized" if EC_POINT.get(object)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

        group_object, arg2 = args
        if group_object.is_a?(PKey::EC::Point)
          raise ArgumentError, "invalid second argument" if args.size != 1

          return ec_point_initialize_copy(object, group_object)
        end
        group = EC_GROUP.fetch(group_object)
        point = if args.size == 1
                  Lib.EC_POINT_new(group).tap { |new_point| raise error(PKey::EC::Point::Error, "EC_POINT_new") if new_point.zero? }
                elsif arg2.is_a?(BN)
                  Lib.EC_POINT_bn2point(group, bn_of(arg2), nil, bn_ctx).tap { |new_point| raise error(PKey::EC::Point::Error, "EC_POINT_bn2point") if new_point.zero? }
                else
                  octets = string_value(arg2)
                  new_point = Lib.EC_POINT_new(group)
                  raise error(PKey::EC::Point::Error, "EC_POINT_new") if new_point.zero?

                  if Lib.EC_POINT_oct2point(group, new_point, octets, octets.bytesize, bn_ctx).zero?
                    Lib.EC_POINT_free(new_point)
                    raise error(PKey::EC::Point::Error, "EC_POINT_oct2point")
                  end
                  new_point
                end
        EC_POINT.set(object, point)
        object.instance_variable_set(:@group, group_object)
        object
      end

      # ossl_ec_point_initialize_copy.
      def ec_point_initialize_copy(object, other)
        EC_POINT.unshare(object, other)
        raise error(PKey::EC::Point::Error, "EC::Point already initialized") if EC_POINT.get(object)

        point = EC_POINT.fetch(other)
        group_object = other.instance_variable_get(:@group).dup
        copy = Lib.EC_POINT_dup(point, EC_GROUP.fetch(group_object))
        raise error(PKey::EC::Point::Error, "EC_POINT_dup") if copy.zero?

        EC_POINT.set(object, copy)
        object.instance_variable_set(:@group, group_object)
        object
      end
    end
  end

  module PKey
    class EC
      def self.builtin_curves
        count = Lib.EC_get_builtin_curves(nil, 0)
        # EC_builtin_curve: int nid, const char *comment.
        table = Lib.buffer(count * 16)
        raise Ossl.error(RuntimeError, "EC_get_builtin_curves") if Lib.EC_get_builtin_curves(table, count).zero?

        Array.new(count) do |i|
          nid, comment = table.unpack("l x4 J", offset: i * 16)
          [Lib.string(Lib.OBJ_nid2sn(nid)), comment.zero? ? nil : Lib.string(comment)]
        end
      end

      def self.generate(arg)
        object = Native.allocate(self)
        ec = Ossl.ec_key_new_from_group(arg)
        Ossl.assign_legacy(object, Lib::EVP_PKEY_EC, ec, :EC_KEY_free, "EVP_PKEY_assign_EC_KEY")
        raise Ossl.error(PKeyError, "EC_KEY_generate_key") if Lib.EC_KEY_generate_key(ec).zero?

        object
      end

      def initialize(*args, &block)
        raise TypeError, "pkey already initialized" if Ossl::PKEY.get(self)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

        arg, pass = args
        raise ArgumentError, "OpenSSL::PKey::EC.new cannot be called without arguments; pkeys are immutable with OpenSSL 3.0" if arg.nil?

        if arg.is_a?(Group)
          Ossl.assign_legacy(self, Lib::EVP_PKEY_EC, Ossl.ec_key_new_from_group(arg), :EC_KEY_free, "EVP_PKEY_assign_EC_KEY")
          return self
        end
        pass = Ossl.pem_password_value(pass)
        arg = Ossl.to_der_if_possible(arg)
        bio, arg = Ossl.obj2bio(arg)
        pkey = Ossl.with_password(pass, block) { |id| Ossl.pkey_read_generic(bio, id) }
        Lib.BIO_free(bio)
        if pkey.nil?
          Ossl.clear_error
          Ossl.assign_legacy(self, Lib::EVP_PKEY_EC, Ossl.ec_key_new_from_group(arg), :EC_KEY_free, "EVP_PKEY_assign_EC_KEY")
          return self
        end
        type = Lib.EVP_PKEY_get_base_id(pkey)
        if type != Lib::EVP_PKEY_EC
          Lib.EVP_PKEY_free(pkey)
          raise PKeyError, "incorrect pkey type: #{Lib.string(Lib.OBJ_nid2sn(type))}"
        end
        Ossl::PKEY.set(self, pkey)
        self
      end

      def group
        group = Lib.EC_KEY_get0_group(Ossl.ec(self))
        group.zero? ? nil : Ossl.ec_group_new(group)
      end

      def group=(_group)
        raise PKeyError, "pkeys are immutable on OpenSSL 3.0"
      end

      def private_key
        bn = Lib.EC_KEY_get0_private_key(Ossl.ec(self))
        Ossl.bn_or_nil(bn)
      end

      def private_key=(_private_key)
        raise PKeyError, "pkeys are immutable on OpenSSL 3.0"
      end

      def public_key
        ec = Ossl.ec(self)
        point = Lib.EC_KEY_get0_public_key(ec)
        point.zero? ? nil : Ossl.ec_point_new(point, Lib.EC_KEY_get0_group(ec))
      end

      def public_key=(_public_key)
        raise PKeyError, "pkeys are immutable on OpenSSL 3.0"
      end

      def private? = !Lib.EC_KEY_get0_private_key(Ossl.ec(self)).zero?
      alias private_key? private?

      def public? = !Lib.EC_KEY_get0_public_key(Ossl.ec(self)).zero?
      alias public_key? public?

      def generate_key! = raise(PKeyError, "pkeys are immutable on OpenSSL 3.0")
      alias generate_key generate_key!

      def check_key
        pkey = Ossl.pkey(self)
        ec = Ossl.ec(self)
        ctx = Lib.EVP_PKEY_CTX_new(pkey, nil)
        raise Ossl.error(PKeyError, "EVP_PKEY_CTX_new") if ctx.zero?

        Ossl.with_pkey_ctx(ctx) do
          if Lib.EC_KEY_get0_private_key(ec).zero?
            raise Ossl.error(PKeyError, "EVP_PKEY_public_check") if Lib.EVP_PKEY_public_check(ctx) != 1
          elsif Lib.EVP_PKEY_check(ctx) != 1
            raise Ossl.error(PKeyError, "EVP_PKEY_check")
          end
        end
        true
      end

      def export(*args)
        ec = Ossl.ec(self)
        raise Ossl.error(PKeyError, "can't export - no public key set") if Lib.EC_KEY_get0_public_key(ec).zero?
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

        if Lib.EC_KEY_get0_private_key(ec).zero?
          Ossl.pkey_export_spki(self, false)
        else
          Ossl.pkey_export_traditional(self, false, *args)
        end
      end
      alias to_pem export

      def to_der
        ec = Ossl.ec(self)
        raise Ossl.error(PKeyError, "can't export - no public key set") if Lib.EC_KEY_get0_public_key(ec).zero?

        Lib.EC_KEY_get0_private_key(ec).zero? ? Ossl.pkey_export_spki(self, true) : Ossl.pkey_export_traditional(self, true)
      end

      class Group
        def initialize(*args)
          raise Ossl.error(RuntimeError, "EC_GROUP is already initialized") if Ossl::EC_GROUP.get(self)

          group = case args.size
                  when 1 then Ossl.ec_group_from(args.first)
                  when 4 then Ossl.ec_group_curve(*args)
                  else raise Ossl.error(ArgumentError, "wrong number of arguments (given #{args.size}, expected 1 or 4)")
                  end
          Ossl::EC_GROUP.set(self, group)
          self
        end

        def initialize_copy(other)
          Ossl::EC_GROUP.unshare(self, other)
          raise Ossl.error(Error, "EC::Group already initialized") if Ossl::EC_GROUP.get(self)

          group = Lib.EC_GROUP_dup(Ossl::EC_GROUP.fetch(other))
          raise Ossl.error(Error, "EC_GROUP_dup") if group.zero?

          Ossl::EC_GROUP.set(self, group)
          self
        end

        def eql?(other) = Ossl.ec_group_eql(self, other)
        alias == eql?

        def generator
          group = Ossl::EC_GROUP.fetch(self)
          generator = Lib.EC_GROUP_get0_generator(group)
          generator.zero? ? nil : Ossl.ec_point_new(generator, group)
        end

        def set_generator(generator, order, cofactor)
          group = Ossl::EC_GROUP.fetch(self)
          point = Ossl::EC_POINT.fetch(generator)
          order = Ossl.to_bn(order)
          cofactor = Ossl.to_bn(cofactor)
          raise Ossl.error(Error, "EC_GROUP_set_generator") if Lib.EC_GROUP_set_generator(group, point, Ossl.bn_of(order), Ossl.bn_of(cofactor)) != 1

          self
        end

        def order = Ossl.ec_group_bn(self, :EC_GROUP_get_order, "EC_GROUP_get_order")

        def cofactor = Ossl.ec_group_bn(self, :EC_GROUP_get_cofactor, "EC_GROUP_get_cofactor")

        def curve_name
          nid = Lib.EC_GROUP_get_curve_name(Ossl::EC_GROUP.fetch(self))
          nid == Lib::NID_undef ? nil : Lib.string(Lib.OBJ_nid2sn(nid))
        end

        def asn1_flag = Lib.EC_GROUP_get_asn1_flag(Ossl::EC_GROUP.fetch(self))

        def asn1_flag=(flag)
          Lib.EC_GROUP_set_asn1_flag(Ossl::EC_GROUP.fetch(self), Ossl.int(flag))
        end

        def point_conversion_form
          form = Lib.EC_GROUP_get_point_conversion_form(Ossl::EC_GROUP.fetch(self))
          Ossl::POINT_CONVERSION_FORMS.key(form) ||
            raise(Ossl.error(Error, "unsupported point conversion form: #{form}, this module should be updated"))
        end

        def point_conversion_form=(form)
          group = Ossl::EC_GROUP.fetch(self)
          Lib.EC_GROUP_set_point_conversion_form(group, Ossl.point_conversion_form(form))
        end

        def seed
          group = Ossl::EC_GROUP.fetch(self)
          length = Lib.EC_GROUP_get_seed_len(group)
          length.zero? ? nil : Lib.read(Lib.EC_GROUP_get0_seed(group), length)
        end

        def seed=(seed)
          group = Ossl::EC_GROUP.fetch(self)
          seed = Ossl.string_value(seed)
          raise Ossl.error(Error, "EC_GROUP_set_seed") if Lib.EC_GROUP_set_seed(group, seed, seed.bytesize) != seed.bytesize
        end

        def degree = Lib.EC_GROUP_get_degree(Ossl::EC_GROUP.fetch(self))

        def to_pem = Ossl.ec_group_to_string(self, false)

        def to_der = Ossl.ec_group_to_string(self, true)

        def to_text
          group = Ossl::EC_GROUP.fetch(self)
          bio = Lib.BIO_new(Lib.BIO_s_mem)
          raise Ossl.error(Error, "BIO_new(BIO_s_mem())") if bio.zero?

          if Lib.ECPKParameters_print(bio, group, 0).zero?
            Lib.BIO_free(bio)
            raise Ossl.error(Error)
          end
          Ossl.membio2str(bio)
        end
      end

      class Point
        def group = @group

        def initialize(*args) = Ossl.ec_point_initialize(self, args)

        def initialize_copy(other) = Ossl.ec_point_initialize_copy(self, other)

        def eql?(other)
          group_object = @group
          return false unless Ossl.ec_group_eql(group_object, other.instance_variable_get(:@group))

          point1 = Ossl::EC_POINT.fetch(self)
          point2 = Ossl::EC_POINT.fetch(other)
          case Lib.EC_POINT_cmp(Ossl::EC_GROUP.fetch(group_object), point1, point2, Ossl.bn_ctx)
          when 0 then true
          when 1 then false
          else raise Ossl.error(Error, "EC_POINT_cmp")
          end
        end
        alias == eql?

        def infinity?
          point = Ossl::EC_POINT.fetch(self)
          case Lib.EC_POINT_is_at_infinity(Ossl.ec_point_group(self), point)
          when 1 then true
          when 0 then false
          else raise Ossl.error(Error, "EC_POINT_is_at_infinity")
          end
        end

        def on_curve?
          point = Ossl::EC_POINT.fetch(self)
          case Lib.EC_POINT_is_on_curve(Ossl.ec_point_group(self), point, Ossl.bn_ctx)
          when 1 then true
          when 0 then false
          else raise Ossl.error(Error, "EC_POINT_is_on_curve")
          end
        end

        def make_affine!
          Ossl::EC_POINT.fetch(self)
          Ossl.ec_point_group(self)
          Ossl.warn("OpenSSL::PKey::EC::Point#make_affine! is deprecated")
          self
        end

        def invert!
          point = Ossl::EC_POINT.fetch(self)
          raise Ossl.error(Error, "EC_POINT_invert") if Lib.EC_POINT_invert(Ossl.ec_point_group(self), point, Ossl.bn_ctx) != 1

          self
        end

        def set_to_infinity!
          point = Ossl::EC_POINT.fetch(self)
          raise Ossl.error(Error, "EC_POINT_set_to_infinity") if Lib.EC_POINT_set_to_infinity(Ossl.ec_point_group(self), point) != 1

          self
        end

        def to_octet_string(conversion_form)
          point = Ossl::EC_POINT.fetch(self)
          group = Ossl.ec_point_group(self)
          form = Ossl.point_conversion_form(conversion_form)
          length = Lib.EC_POINT_point2oct(group, point, form, nil, 0, Ossl.bn_ctx)
          raise Ossl.error(Error, "EC_POINT_point2oct") if length.zero?

          out = Lib.buffer(length)
          raise Ossl.error(Error, "EC_POINT_point2oct") if Lib.EC_POINT_point2oct(group, point, form, out, length, Ossl.bn_ctx).zero?

          out
        end

        def add(other)
          group_object = @group
          point_self = Ossl::EC_POINT.fetch(self)
          point_other = Ossl::EC_POINT.fetch(other)
          group = Ossl::EC_GROUP.fetch(group_object)
          result = Ossl.ec_point_on_group(group_object)
          raise Ossl.error(Error, "EC_POINT_add") if Lib.EC_POINT_add(group, Ossl::EC_POINT.fetch(result), point_self, point_other, Ossl.bn_ctx) != 1

          result
        end

        def mul(bn1, *rest)
          raise ArgumentError, "wrong number of arguments (given #{rest.size + 1}, expected 1..3)" if rest.size > 2

          group_object = @group
          point_self = Ossl::EC_POINT.fetch(self)
          group = Ossl::EC_GROUP.fetch(group_object)
          result = Ossl.ec_point_on_group(group_object)
          raise NotImplementedError, "OpenSSL::PKey::EC::Point#mul with arrays is no longer supported" if bn1.is_a?(Array) || rest.size > 1

          bn = Ossl.to_bn(bn1)
          bn_g = rest.first.nil? ? nil : Ossl.to_bn(rest.first)
          if Lib.EC_POINT_mul(group, Ossl::EC_POINT.fetch(result), bn_g && Ossl.bn_of(bn_g), point_self, Ossl.bn_of(bn), Ossl.bn_ctx) != 1
            raise Ossl.error(Error)
          end
          result
        end
      end
    end
  end
end
