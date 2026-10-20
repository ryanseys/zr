# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_x509store.c: OpenSSL::X509::Store and StoreContext, certificate
# verification with a Ruby verify callback.
module OpenSSL
  Lib.attach_all(
    X509_STORE_new: [[], :pointer],
    X509_STORE_free: [%i[pointer], :void],
    X509_STORE_set_verify_cb: [%i[pointer pointer], :void],
    X509_STORE_set_ex_data: [%i[pointer int pointer], :int],
    X509_STORE_get_ex_data: [%i[pointer int], :pointer],
    X509_STORE_set_purpose: [%i[pointer int], :int],
    X509_STORE_set_trust: [%i[pointer int], :int],
    X509_STORE_get0_param: [%i[pointer], :pointer],
    X509_VERIFY_PARAM_set_time: [%i[pointer long], :void],
    X509_VERIFY_PARAM_get_flags: [%i[pointer], :ulong],
    X509_VERIFY_PARAM_set_flags: [%i[pointer ulong], :int],
    X509_VERIFY_PARAM_clear_flags: [%i[pointer ulong], :int],
    X509_STORE_CTX_get0_param: [%i[pointer], :pointer],
    X509_STORE_add_lookup: [%i[pointer pointer], :pointer],
    X509_LOOKUP_file: [[], :pointer],
    X509_LOOKUP_hash_dir: [[], :pointer],
    X509_LOOKUP_ctrl: [%i[pointer int string long pointer], :int],
    X509_STORE_set_default_paths: [%i[pointer], :int],
    X509_STORE_add_cert: [%i[pointer pointer], :int],
    X509_STORE_add_crl: [%i[pointer pointer], :int],
    X509_STORE_CTX_new: [[], :pointer],
    X509_STORE_CTX_free: [%i[pointer], :void],
    X509_STORE_CTX_init: [%i[pointer pointer pointer pointer], :int],
    X509_STORE_CTX_get0_untrusted: [%i[pointer], :pointer],
    X509_STORE_CTX_get0_cert: [%i[pointer], :pointer],
    X509_STORE_CTX_get0_store: [%i[pointer], :pointer],
    X509_STORE_CTX_set_ex_data: [%i[pointer int pointer], :int],
    X509_STORE_CTX_get_ex_data: [%i[pointer int], :pointer],
    X509_STORE_CTX_set_error: [%i[pointer int], :void],
    X509_STORE_CTX_get_error: [%i[pointer], :int],
    X509_STORE_CTX_get_error_depth: [%i[pointer], :int],
    X509_STORE_CTX_get_current_cert: [%i[pointer], :pointer],
    X509_STORE_CTX_get0_current_crl: [%i[pointer], :pointer],
    X509_STORE_CTX_get0_chain: [%i[pointer], :pointer],
    X509_STORE_CTX_set_purpose: [%i[pointer int], :int],
    X509_STORE_CTX_set_trust: [%i[pointer int], :int],
    X509_STORE_CTX_set_time: [%i[pointer ulong long], :void],
    X509_verify_cert: [%i[pointer], :int],
    X509_verify_cert_error_string: [%i[long], :string],
    CRYPTO_get_ex_new_index: [%i[int long pointer pointer pointer pointer], :int]
  )

  module Lib
    CRYPTO_EX_INDEX_X509_STORE = 4 # crypto.h
    CRYPTO_EX_INDEX_X509_STORE_CTX = 5
    X509_FILETYPE_PEM = 1 # x509.h
    X509_L_FILE_LOAD = 1 # x509_vfy.h
    X509_L_ADD_DIR = 2
    X509_V_OK = 0
    X509_V_ERR_CERT_REJECTED = 28

    # X509_LOOKUP_load_file (x509_vfy.h).
    def self.X509_LOOKUP_load_file(lookup, name, type) = X509_LOOKUP_ctrl(lookup, X509_L_FILE_LOAD, name, type, nil)

    # X509_LOOKUP_add_dir (x509_vfy.h).
    def self.X509_LOOKUP_add_dir(lookup, name, type) = X509_LOOKUP_ctrl(lookup, X509_L_ADD_DIR, name, type, nil)
  end

  module X509
    class StoreError < OpenSSLError; end

    class Store; end

    class StoreContext; end
  end

  module Ossl
    X509_STORE = DataType.new("OpenSSL/X509/STORE", X509::Store, :X509_STORE_free, [RuntimeError, "STORE wasn't initialized!"], create: lambda {
      Lib.X509_STORE_new.tap { |store| raise Ossl.error(X509::StoreError, "X509_STORE_new") if store.zero? }
    })
    X509_STORE_CTX = DataType.new("OpenSSL/X509/STORE_CTX", X509::StoreContext, lambda { |ctx|
      Ossl.free_x509_stack(Lib.X509_STORE_CTX_get0_untrusted(ctx))
      cert = Lib.X509_STORE_CTX_get0_cert(ctx)
      Lib.X509_free(cert) unless cert.zero?
      Lib.X509_STORE_CTX_free(ctx)
    }, [RuntimeError, "STORE_CTX is out of scope!"], create: lambda {
      Lib.X509_STORE_CTX_new.tap { |ctx| raise Ossl.error(X509::StoreError, "X509_STORE_CTX_new") if ctx.zero? }
    })

    STCTX_VERIFY_CB_INDEX = Lib.CRYPTO_get_ex_new_index(Lib::CRYPTO_EX_INDEX_X509_STORE_CTX, 0, "stctx_ex_verify_cb_idx", nil, nil, nil)
    raise error(OpenSSLError, "X509_STORE_CTX_get_ex_new_index") if STCTX_VERIFY_CB_INDEX.negative?

    STORE_VERIFY_CB_INDEX = Lib.CRYPTO_get_ex_new_index(Lib::CRYPTO_EX_INDEX_X509_STORE, 0, "store_ex_verify_cb_idx", nil, nil, nil)
    raise error(OpenSSLError, "X509_STORE_get_ex_new_index") if STORE_VERIFY_CB_INDEX.negative?

    class << self
      # GetX509StorePtr.
      def x509store(object) = X509_STORE.fetch(object)

      # x509vpm_set_flags_i: the flags are added to the ones set, which
      # ruby says once they do not already cover.
      def vpm_set_flags(vpm, flags)
        value = ulong(flags)
        if (Lib.X509_VERIFY_PARAM_get_flags(vpm) | value) != value
          warn("`obj.flags = new_flags` does not clear existing flags; " \
               "use `obj.clear_flags` first if you want to replace them, " \
               "or `obj.flags |= new_flags` to indicate that appending flags is intentional")
        end
        raise error(X509::StoreError, "X509_VERIFY_PARAM_set_flags") if Lib.X509_VERIFY_PARAM_set_flags(vpm, value).zero?
      end

      # x509vpm_clear_flags_i: all the flags when `flags` is nil.
      def vpm_clear_flags(vpm, flags)
        value = flags.nil? ? (1 << 64) - 1 : ulong(flags)
        raise error(X509::StoreError, "X509_VERIFY_PARAM_clear_flags") if Lib.X509_VERIFY_PARAM_clear_flags(vpm, value).zero?
      end

      # ossl_verify_cb_call: `proc`'s verdict on the chain the library
      # built so far, as a StoreContext over `ctx` for the length of the
      # call. An exception in the callback counts as a rejection.
      def verify_cb_call(proc, ok, ctx)
        return ok if proc.nil?

        answer = false
        begin
          context = X509_STORE_CTX.borrow(Native.allocate(X509::StoreContext), ctx)
        rescue Exception
          warn("StoreContext initialization failure")
        else
          begin
            answer = proc.call(ok != 0, context)
          rescue Exception
            warn("exception in verify_callback is ignored")
          ensure
            X509_STORE_CTX.take(context)
          end
        end
        if answer == true
          Lib.X509_STORE_CTX_set_error(ctx, Lib::X509_V_OK)
          1
        else
          Lib.X509_STORE_CTX_set_error(ctx, Lib::X509_V_ERR_CERT_REJECTED) if Lib.X509_STORE_CTX_get_error(ctx) == Lib::X509_V_OK
          0
        end
      end

      # x509store_verify_cb: the StoreContext's callback, else its
      # Store's.
      def x509store_verify(ok, ctx)
        proc = dereference(Lib.X509_STORE_CTX_get_ex_data(ctx, STCTX_VERIFY_CB_INDEX))
        proc ||= dereference(Lib.X509_STORE_get_ex_data(Lib.X509_STORE_CTX_get0_store(ctx), STORE_VERIFY_CB_INDEX))
        return ok if proc.nil?

        verify_cb_call(proc, ok, ctx)
      end
    end

    X509STORE_VERIFY_CB = Lib.callback { |ok, ctx| x509store_verify(Lib::RETURNS[:int].(ok), ctx) }
  end

  module X509
    class Store
      def verify_callback = @verify_callback
      def error = @error
      def error_string = @error_string
      def chain = @chain

      def initialize(*args)
        Ossl.warn("OpenSSL::X509::Store.new does not take any arguments") unless args.empty?
        Ossl.want_uninitialized(self, Ossl::X509_STORE)
        Ossl::X509_STORE.create(self)
        store = Ossl.x509store(self)
        Lib.X509_STORE_set_verify_cb(store, Ossl::X509STORE_VERIFY_CB)
        self.verify_callback = nil
        @error = nil
        @error_string = nil
        @chain = nil
        self
      end

      # As rb_undef_method, a second load of this file undefines nothing.

      undef_method :initialize_copy if private_method_defined?(:initialize_copy)

      def verify_callback=(callback)
        store = Ossl.x509store(self)
        @verify_callback = callback
        Lib.X509_STORE_set_ex_data(store, Ossl::STORE_VERIFY_CB_INDEX, Ossl.reference(callback))
        callback
      end

      def flags = Lib.X509_VERIFY_PARAM_get_flags(Lib.X509_STORE_get0_param(Ossl.x509store(self)))

      def flags=(flags)
        Ossl.vpm_set_flags(Lib.X509_STORE_get0_param(Ossl.x509store(self)), flags)
        flags
      end

      def clear_flags(flags = nil)
        Ossl.vpm_clear_flags(Lib.X509_STORE_get0_param(Ossl.x509store(self)), flags)
        nil
      end

      def purpose=(purpose)
        value = Ossl.int(purpose)
        Lib.X509_STORE_set_purpose(Ossl.x509store(self), value)
        purpose
      end

      def trust=(trust)
        value = Ossl.int(trust)
        Lib.X509_STORE_set_trust(Ossl.x509store(self), value)
        trust
      end

      def time=(time)
        param = Lib.X509_STORE_get0_param(Ossl.x509store(self))
        Lib.X509_VERIFY_PARAM_set_time(param, Ossl.long(Kernel.Integer(time)))
        time
      end

      def add_file(file)
        store = Ossl.x509store(self)
        path = Ossl.cstring_value(file)
        lookup = Lib.X509_STORE_add_lookup(store, Lib.X509_LOOKUP_file)
        raise Ossl.error(StoreError, "X509_STORE_add_lookup") if lookup.zero?
        raise Ossl.error(StoreError, "X509_LOOKUP_load_file") if Lib.X509_LOOKUP_load_file(lookup, path, Lib::X509_FILETYPE_PEM) != 1

        self
      end

      def add_path(dir)
        store = Ossl.x509store(self)
        path = Ossl.cstring_value(dir)
        lookup = Lib.X509_STORE_add_lookup(store, Lib.X509_LOOKUP_hash_dir)
        raise Ossl.error(StoreError, "X509_STORE_add_lookup") if lookup.zero?
        raise Ossl.error(StoreError, "X509_LOOKUP_add_dir") if Lib.X509_LOOKUP_add_dir(lookup, path, Lib::X509_FILETYPE_PEM) != 1

        self
      end

      def set_default_paths
        raise Ossl.error(StoreError, "X509_STORE_set_default_paths") if Lib.X509_STORE_set_default_paths(Ossl.x509store(self)) != 1

        nil
      end

      def add_cert(cert)
        x509 = Ossl.x509(cert)
        raise Ossl.error(StoreError, "X509_STORE_add_cert") if Lib.X509_STORE_add_cert(Ossl.x509store(self), x509) != 1

        self
      end

      def add_crl(crl)
        x509crl = Ossl.x509crl(crl)
        raise Ossl.error(StoreError, "X509_STORE_add_crl") if Lib.X509_STORE_add_crl(Ossl.x509store(self), x509crl) != 1

        self
      end

      def verify(cert, chain = nil, &block)
        context = StoreContext.new(self, cert, chain)
        context.instance_variable_set(:@verify_callback, block || @verify_callback)
        result = context.verify
        @error = context.error
        @error_string = context.error_string
        @chain = context.chain
        result
      end
    end

    class StoreContext
      def initialize(store, cert = nil, chain = nil)
        Ossl.want_uninitialized(self, Ossl::X509_STORE_CTX)
        Ossl::X509_STORE_CTX.create(self)
        ctx = Ossl::X509_STORE_CTX.fetch(self)
        x509store = Ossl.x509store(store)
        x509 = cert.nil? ? nil : Ossl.dup_x509(cert)
        begin
          stack = chain.nil? ? nil : Ossl.x509_ary2sk(chain)
        rescue Exception
          Lib.X509_free(x509) if x509
          raise
        end
        if Lib.X509_STORE_CTX_init(ctx, x509store, x509, stack) != 1
          Lib.X509_free(x509) if x509
          Ossl.free_x509_stack(stack)
          raise Ossl.error(StoreError, "X509_STORE_CTX_init")
        end
        @verify_callback = store.instance_variable_get(:@verify_callback)
        @cert = cert
        self
      end

      # As rb_undef_method, a second load of this file undefines nothing.

      undef_method :initialize_copy if private_method_defined?(:initialize_copy)

      def verify
        ctx = Ossl::X509_STORE_CTX.fetch(self)
        Lib.X509_STORE_CTX_set_ex_data(ctx, Ossl::STCTX_VERIFY_CB_INDEX, Ossl.reference(@verify_callback))
        case Lib.X509_verify_cert(ctx)
        when 1 then true
        when 0
          Ossl.clear_error
          false
        else raise Ossl.error(StoreError, "X509_verify_cert")
        end
      end

      def chain
        chain = Lib.X509_STORE_CTX_get0_chain(Ossl::X509_STORE_CTX.fetch(self))
        chain.zero? ? nil : Ossl.x509_sk2ary(chain)
      end

      def error = Lib.X509_STORE_CTX_get_error(Ossl::X509_STORE_CTX.fetch(self))

      def error=(error)
        Lib.X509_STORE_CTX_set_error(Ossl::X509_STORE_CTX.fetch(self), Ossl.int(error))
        error
      end

      def error_string = Lib.X509_verify_cert_error_string(Lib.X509_STORE_CTX_get_error(Ossl::X509_STORE_CTX.fetch(self)))

      def error_depth = Lib.X509_STORE_CTX_get_error_depth(Ossl::X509_STORE_CTX.fetch(self))

      def current_cert
        x509 = Lib.X509_STORE_CTX_get_current_cert(Ossl::X509_STORE_CTX.fetch(self))
        x509.zero? ? nil : Ossl.x509_new(x509)
      end

      def current_crl
        crl = Lib.X509_STORE_CTX_get0_current_crl(Ossl::X509_STORE_CTX.fetch(self))
        crl.zero? ? nil : Ossl.x509crl_new(crl)
      end

      def flags = Lib.X509_VERIFY_PARAM_get_flags(Lib.X509_STORE_CTX_get0_param(Ossl::X509_STORE_CTX.fetch(self)))

      def flags=(flags)
        Ossl.vpm_set_flags(Lib.X509_STORE_CTX_get0_param(Ossl::X509_STORE_CTX.fetch(self)), flags)
        flags
      end

      def clear_flags(flags = nil)
        Ossl.vpm_clear_flags(Lib.X509_STORE_CTX_get0_param(Ossl::X509_STORE_CTX.fetch(self)), flags)
        nil
      end

      def purpose=(purpose)
        value = Ossl.int(purpose)
        Lib.X509_STORE_CTX_set_purpose(Ossl::X509_STORE_CTX.fetch(self), value)
        purpose
      end

      def trust=(trust)
        value = Ossl.int(trust)
        Lib.X509_STORE_CTX_set_trust(Ossl::X509_STORE_CTX.fetch(self), value)
        trust
      end

      def time=(time)
        value = Ossl.long(Kernel.Integer(time))
        Lib.X509_STORE_CTX_set_time(Ossl::X509_STORE_CTX.fetch(self), 0, value)
        time
      end
    end
  end
end
