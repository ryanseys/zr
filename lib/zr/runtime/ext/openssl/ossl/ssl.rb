# frozen_string_literal: true

# ossl_ssl.c: OpenSSL::SSL, SSLContext over SSL_CTX and SSLSocket over
# SSL on the socket's descriptor, with the library's callbacks calling the
# context's procs.
module OpenSSL
  Lib.attach_all(
    TLS_method: [[], :pointer],
    SSL_CTX_new: [%i[pointer], :pointer],
    SSL_CTX_free: [%i[pointer], :void],
    SSL_CTX_ctrl: [%i[pointer int long pointer], :long],
    SSL_CTX_callback_ctrl: [%i[pointer int pointer], :long],
    SSL_CTX_set_ex_data: [%i[pointer int pointer], :int],
    SSL_CTX_get_ex_data: [%i[pointer int], :pointer],
    SSL_CTX_set_tmp_dh_callback: [%i[pointer pointer], :void],
    SSL_CTX_set_post_handshake_auth: [%i[pointer int], :void],
    SSL_CTX_set_cert_store: [%i[pointer pointer], :void],
    X509_STORE_up_ref: [%i[pointer], :int],
    SSL_CTX_use_certificate: [%i[pointer pointer], :int],
    SSL_CTX_use_PrivateKey: [%i[pointer pointer], :int],
    SSL_CTX_check_private_key: [%i[pointer], :int],
    SSL_CTX_add_client_CA: [%i[pointer pointer], :int],
    SSL_CTX_load_verify_file: [%i[pointer string], :int],
    SSL_CTX_load_verify_dir: [%i[pointer string], :int],
    SSL_CTX_set_verify: [%i[pointer int pointer], :void],
    SSL_CTX_set_client_cert_cb: [%i[pointer pointer], :void],
    SSL_CTX_set_timeout: [%i[pointer long], :long],
    SSL_CTX_set_verify_depth: [%i[pointer int], :void],
    SSL_CTX_set_next_protos_advertised_cb: [%i[pointer pointer pointer], :void],
    SSL_CTX_set_next_proto_select_cb: [%i[pointer pointer pointer], :void],
    SSL_CTX_set_alpn_protos: [%i[pointer buffer uint], :int],
    SSL_CTX_set_alpn_select_cb: [%i[pointer pointer pointer], :void],
    SSL_CTX_set_session_id_context: [%i[pointer buffer uint], :int],
    SSL_CTX_sess_set_get_cb: [%i[pointer pointer], :void],
    SSL_CTX_sess_set_new_cb: [%i[pointer pointer], :void],
    SSL_CTX_sess_set_remove_cb: [%i[pointer pointer], :void],
    SSL_CTX_set_keylog_callback: [%i[pointer pointer], :void],
    SSL_CTX_get_ciphers: [%i[pointer], :pointer],
    SSL_CIPHER_get_name: [%i[pointer], :string],
    SSL_CIPHER_get_version: [%i[pointer], :string],
    SSL_CIPHER_get_bits: [%i[pointer buffer], :int],
    SSL_CTX_set_cipher_list: [%i[pointer string], :int],
    SSL_CTX_set_ciphersuites: [%i[pointer string], :int],
    SSL_CTX_set0_tmp_dh_pkey: [%i[pointer pointer], :int],
    SSL_CTX_get_security_level: [%i[pointer], :int],
    SSL_CTX_set_security_level: [%i[pointer int], :void],
    SSL_CTX_add_session: [%i[pointer pointer], :int],
    SSL_CTX_remove_session: [%i[pointer pointer], :int],
    SSL_CTX_flush_sessions: [%i[pointer long], :void],
    SSL_CTX_get_options: [%i[pointer], :uint64],
    SSL_CTX_set_options: [%i[pointer uint64], :uint64],
    SSL_CTX_clear_options: [%i[pointer uint64], :uint64],
    SSL_new: [%i[pointer], :pointer],
    SSL_free: [%i[pointer], :void],
    SSL_ctrl: [%i[pointer int long pointer], :long],
    SSL_set_ex_data: [%i[pointer int pointer], :int],
    SSL_get_ex_data: [%i[pointer int], :pointer],
    SSL_get_ex_data_X509_STORE_CTX_idx: [[], :int],
    SSL_set_info_callback: [%i[pointer pointer], :void],
    SSL_set_fd: [%i[pointer int], :int],
    SSL_get_rbio: [%i[pointer], :pointer],
    SSL_get_error: [%i[pointer int], :int],
    SSL_shutdown: [%i[pointer], :int],
    SSL_is_server: [%i[pointer], :int],
    SSL_get_servername: [%i[pointer int], :string],
    SSL_set_SSL_CTX: [%i[pointer pointer], :pointer],
    SSL_state_string: [%i[pointer], :string],
    SSL_state_string_long: [%i[pointer], :string],
    SSL_get_certificate: [%i[pointer], :pointer],
    SSL_get1_peer_certificate: [%i[pointer], :pointer],
    SSL_get_peer_cert_chain: [%i[pointer], :pointer],
    SSL_get_version: [%i[pointer], :string],
    SSL_get_current_cipher: [%i[pointer], :pointer],
    SSL_pending: [%i[pointer], :int],
    SSL_session_reused: [%i[pointer], :int],
    SSL_set_session: [%i[pointer pointer], :int],
    SSL_get_verify_result: [%i[pointer], :long],
    SSL_get_finished: [%i[pointer buffer size_t], :size_t],
    SSL_get_peer_finished: [%i[pointer buffer size_t], :size_t],
    SSL_get_client_CA_list: [%i[pointer], :pointer],
    SSL_get0_next_proto_negotiated: [%i[pointer buffer buffer], :void],
    SSL_get0_alpn_selected: [%i[pointer buffer buffer], :void],
    SSL_export_keying_material: [%i[pointer buffer size_t buffer size_t buffer size_t int], :int],
    SSL_get0_group_name: [%i[pointer], :string]
  )
  Lib.attach(:SSL_connect, %i[pointer], :int, errno: true, as: :SSL_connect_errno)
  Lib.attach(:SSL_accept, %i[pointer], :int, errno: true, as: :SSL_accept_errno)
  Lib.attach(:SSL_read, %i[pointer buffer int], :int, errno: true, as: :SSL_read_errno)
  Lib.attach(:SSL_write, %i[pointer buffer int], :int, errno: true, as: :SSL_write_errno)

  module Lib
    CRYPTO_EX_INDEX_SSL = 0 # crypto.h
    CRYPTO_EX_INDEX_SSL_CTX = 1
    SSL_CTRL_EXTRA_CHAIN_CERT = 14 # ssl.h
    SSL_CTRL_SESS_NUMBER = 20
    SSL_CTRL_SESS_CONNECT = 21
    SSL_CTRL_SESS_CONNECT_GOOD = 22
    SSL_CTRL_SESS_CONNECT_RENEGOTIATE = 23
    SSL_CTRL_SESS_ACCEPT = 24
    SSL_CTRL_SESS_ACCEPT_GOOD = 25
    SSL_CTRL_SESS_ACCEPT_RENEGOTIATE = 26
    SSL_CTRL_SESS_HIT = 27
    SSL_CTRL_SESS_CB_HIT = 28
    SSL_CTRL_SESS_MISSES = 29
    SSL_CTRL_SESS_TIMEOUTS = 30
    SSL_CTRL_SESS_CACHE_FULL = 31
    SSL_CTRL_MODE = 33
    SSL_CTRL_SET_SESS_CACHE_SIZE = 42
    SSL_CTRL_GET_SESS_CACHE_SIZE = 43
    SSL_CTRL_SET_SESS_CACHE_MODE = 44
    SSL_CTRL_GET_SESS_CACHE_MODE = 45
    SSL_CTRL_SET_TLSEXT_SERVERNAME_CB = 53
    SSL_CTRL_SET_TLSEXT_HOSTNAME = 55
    SSL_CTRL_CHAIN = 88
    SSL_CTRL_SET_GROUPS_LIST = 92
    SSL_CTRL_SET_SIGALGS_LIST = 98
    SSL_CTRL_SET_CLIENT_SIGALGS_LIST = 102
    SSL_CTRL_GET_PEER_TMP_KEY = 109
    SSL_CTRL_SET_DH_AUTO = 118
    SSL_CTRL_SET_MIN_PROTO_VERSION = 123
    SSL_CTRL_SET_MAX_PROTO_VERSION = 124
    SSL_CTRL_GET_SIGNATURE_NAME = 140
    SSL_CTRL_GET_PEER_SIGNATURE_NAME = 141
    SSL_MODE_ENABLE_PARTIAL_WRITE = 0x01
    SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER = 0x02
    SSL_MODE_RELEASE_BUFFERS = 0x10
    SSL_MODE_SEND_FALLBACK_SCSV = 0x80
    SSL_ERROR_NONE = 0
    SSL_ERROR_WANT_READ = 2
    SSL_ERROR_WANT_WRITE = 3
    SSL_ERROR_SYSCALL = 5
    SSL_ERROR_ZERO_RETURN = 6
    SSL_R_CERTIFICATE_VERIFY_FAILED = 134 # sslerr.h
    ERR_LIB_SSL = 20 # err.h
    SSL_TLSEXT_ERR_OK = 0 # tls1.h
    SSL_TLSEXT_ERR_ALERT_FATAL = 2
    TLSEXT_NAMETYPE_host_name = 0
    SSL_CB_HANDSHAKE_START = 0x10 # ssl.h
    X509_V_ERR_HOSTNAME_MISMATCH = 62 # x509_vfy.h

    # ERR_GET_LIB (err.h).
    def self.ERR_GET_LIB(code) = code & ERR_SYSTEM_FLAG == 0 ? (code >> 23) & 0xff : 2

    %i[SSL_CTX_set_mode SSL_CTX_set_dh_auto].zip([SSL_CTRL_MODE, SSL_CTRL_SET_DH_AUTO]).each do |name, ctrl|
      define_singleton_method(name) { |ctx, value| SSL_CTX_ctrl(ctx, ctrl, value, nil) }
    end

    # SSL_CTX_set_min_proto_version and SSL_CTX_set_max_proto_version
    # (ssl.h).
    def self.SSL_CTX_set_min_proto_version(ctx, version) = SSL_CTX_ctrl(ctx, SSL_CTRL_SET_MIN_PROTO_VERSION, version, nil)

    def self.SSL_CTX_set_max_proto_version(ctx, version) = SSL_CTX_ctrl(ctx, SSL_CTRL_SET_MAX_PROTO_VERSION, version, nil)

    # SSL_CTX_set_tlsext_servername_callback (tls1.h).
    def self.SSL_CTX_set_tlsext_servername_callback(ctx, cb) = SSL_CTX_callback_ctrl(ctx, SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, cb)

    # SSL_set_tlsext_host_name (tls1.h).
    def self.SSL_set_tlsext_host_name(ssl, name) = SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, name && Native.cstring(name))
  end

  module SSL
    class SSLErrorWaitReadable < SSLError
      include IO::WaitReadable
    end

    class SSLErrorWaitWritable < SSLError
      include IO::WaitWritable
    end

    class SSLContext; end
  end

  module Ossl
    SSL_EX_PTR_INDEX = Lib.CRYPTO_get_ex_new_index(Lib::CRYPTO_EX_INDEX_SSL, 0, "ossl_ssl_ex_ptr_idx", nil, nil, nil)
    raise error(RuntimeError, "SSL_get_ex_new_index") if SSL_EX_PTR_INDEX.negative?

    SSLCTX_EX_PTR_INDEX = Lib.CRYPTO_get_ex_new_index(Lib::CRYPTO_EX_INDEX_SSL_CTX, 0, "ossl_sslctx_ex_ptr_idx", nil, nil, nil)
    raise error(RuntimeError, "SSL_CTX_get_ex_new_index") if SSLCTX_EX_PTR_INDEX.negative?

    SSL_CTX = DataType.new("OpenSSL/SSL/CTX", SSL::SSLContext, :SSL_CTX_free, alloc: lambda { |context|
      ctx = Lib.SSL_CTX_new(Lib.TLS_method)
      raise Ossl.error(SSL::SSLError, "SSL_CTX_new") if ctx.zero?

      Lib.SSL_CTX_set_mode(ctx, Lib::SSL_MODE_ENABLE_PARTIAL_WRITE | Lib::SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER | Lib::SSL_MODE_RELEASE_BUFFERS)
      Lib.SSL_CTX_set_dh_auto(ctx, 1)
      Lib.SSL_CTX_set_ex_data(ctx, SSLCTX_EX_PTR_INDEX, Ossl.reference(context))
      ctx
    })
    SSL_CONNECTION = DataType.new("OpenSSL/SSL", OpenSSL::SSL::SSLSocket, :SSL_free, [RuntimeError, "SSL is not initialized"])

    # parse_proto_version's table.
    PROTOCOL_VERSIONS = [
      ["SSL2", 0x0200], ["SSL3", 0x0300], ["TLS1", 0x0301],
      ["TLS1_1", 0x0302], ["TLS1_2", 0x0303], ["TLS1_3", 0x0304]
    ].freeze

    class << self
      # GetSSL.
      def ssl(object) = SSL_CONNECTION.fetch(object)

      # The SSLSocket an SSL belongs to.
      def ssl_socket(ssl) = dereference(Lib.SSL_get_ex_data(ssl, SSL_EX_PTR_INDEX))

      def context_of(socket) = socket.instance_variable_get(:@context)

      # What a callback raised, which the SSL call it ran under raises once
      # the library returns.
      def callback_failed(socket, exception) = Native.hidden_set(socket, :callback_state, exception)

      # ossl_ssl_verify_callback.
      def ssl_verify(ok, ctx)
        ssl = Lib.X509_STORE_CTX_get_ex_data(ctx, Lib.SSL_get_ex_data_X509_STORE_CTX_idx)
        socket = ssl_socket(ssl)
        context = context_of(socket)
        callback = context.instance_variable_get(:@verify_callback)
        if ok != 0 && context.instance_variable_get(:@verify_hostname) && Lib.SSL_is_server(ssl).zero? && Lib.X509_STORE_CTX_get_error_depth(ctx).zero?
          begin
            identity = verify_certificate_identity(socket, ctx)
          rescue Exception => e # rubocop:disable Lint/RescueException
            callback_failed(socket, e)
            return 0
          end
          unless identity == true
            ok = 0
            Lib.X509_STORE_CTX_set_error(ctx, Lib::X509_V_ERR_HOSTNAME_MISMATCH)
          end
        end
        verify_cb_call(callback, ok, ctx)
      end

      # call_verify_certificate_identity.
      def verify_certificate_identity(socket, ctx)
        hostname = socket.instance_variable_get(:@hostname)
        unless hostname
          warn("verify_hostname requires hostname to be set") if $VERBOSE
          return true
        end
        certificate = x509_new(Lib.X509_STORE_CTX_get_current_cert(ctx))
        OpenSSL::SSL.verify_certificate_identity(certificate, hostname)
      end

      # ossl_client_cert_cb: the certificate and key the context's
      # client_cert_cb gives, each with a reference of its own.
      def client_cert(ssl, x509_out, pkey_out)
        socket = ssl_socket(ssl)
        pair = begin
          callback = context_of(socket).instance_variable_get(:@client_cert_cb)
          if callback.nil?
            nil
          else
            answer = callback.call(socket)
            check_array(answer)
            certificate, key = answer
            x509(certificate)
            private_pkey(key)
            [certificate, key]
          end
        rescue Exception # rubocop:disable Lint/RescueException
          nil
        end
        return 0 if pair.nil?

        Lib.write(x509_out, [dup_x509(pair[0])].pack("J"))
        Lib.write(pkey_out, [dup_pkey(pair[1])].pack("J"))
        1
      end

      # ossl_tmp_dh_callback: the DH the context's tmp_dh_callback gives.
      def tmp_dh(ssl, is_export, keylength)
        socket = ssl_socket(ssl)
        callback = context_of(socket).instance_variable_get(:@tmp_dh_callback)
        return 0 if callback.nil?

        dh = Lib.EVP_PKEY_get0_DH(pkey(callback.call(socket, is_export, keylength)))
        clear_error if dh.zero?
        dh
      rescue Exception => e # rubocop:disable Lint/RescueException
        callback_failed(socket, e)
        0
      end

      # ossl_sslctx_session_get_cb.
      def session_get(ssl, buffer, length, copy)
        socket = ssl_socket(ssl)
        session = begin
          callback = socket.__send__(:session_get_cb)
          callback&.call([socket, Lib.read(buffer, length)])
        rescue Exception => e # rubocop:disable Lint/RescueException
          callback_failed(socket, e)
          return 0
        end
        return 0 unless session.instance_of?(OpenSSL::SSL::Session)

        address = SSL_SESSION.fetch(session)
        Lib.write(copy, [1].pack("l"))
        address
      end

      # ossl_sslctx_session_new_cb.
      def session_new(ssl, session)
        socket = ssl_socket(ssl)
        session = ssl_session_new(session)
        begin
          socket.__send__(:session_new_cb)&.call([socket, session])
        rescue Exception => e # rubocop:disable Lint/RescueException
          callback_failed(socket, e)
        end
        0
      end

      # ossl_sslctx_keylog_cb.
      def keylog(ssl, line)
        socket = ssl_socket(ssl)
        callback = context_of(socket).instance_variable_get(:@keylog_cb)
        callback&.call(socket, Lib.string(line))
        0
      rescue Exception => e # rubocop:disable Lint/RescueException
        callback_failed(socket, e)
        0
      end

      # ossl_sslctx_session_remove_cb: nothing once the context itself is
      # gone, as while the collector frees it.
      def session_remove(ctx, session)
        context = dereference(Lib.SSL_CTX_get_ex_data(ctx, SSLCTX_EX_PTR_INDEX))
        return 0 if context.nil?

        session = ssl_session_new(session)
        begin
          context.instance_variable_get(:@session_remove_cb)&.call([context, session])
        rescue Exception # rubocop:disable Lint/RescueException
          nil
        end
        0
      end

      # ssl_servername_cb.
      def servername(ssl, _alert, _arg)
        name = Lib.SSL_get_servername(ssl, Lib::TLSEXT_NAMETYPE_host_name)
        return Lib::SSL_TLSEXT_ERR_OK if name.nil?

        socket = ssl_socket(ssl)
        begin
          callback = context_of(socket).instance_variable_get(:@servername_cb)
          answer = callback.call([socket, name])
          if answer.is_a?(OpenSSL::SSL::SSLContext)
            sslctx_setup(answer)
            raise error(OpenSSL::SSL::SSLError, "SSL_set_SSL_CTX") if Lib.SSL_set_SSL_CTX(ssl, SSL_CTX.get(answer)).zero?

            socket.instance_variable_set(:@context, answer)
          elsif !answer.nil?
            raise error(ArgumentError, "servername_cb must return an OpenSSL::SSL::SSLContext object or nil")
          end
          Lib::SSL_TLSEXT_ERR_OK
        rescue Exception => e # rubocop:disable Lint/RescueException
          callback_failed(socket, e)
          Lib::SSL_TLSEXT_ERR_ALERT_FATAL
        end
      end

      # ssl_info_cb: a server's renegotiation_cb at the start of each
      # handshake. What it raises leaves through the SSL call, as the C
      # extension lets it.
      def ssl_info(ssl, where, _value)
        return 0 unless !Lib.SSL_is_server(ssl).zero? && where & Lib::SSL_CB_HANDSHAKE_START != 0

        socket = ssl_socket(ssl)
        context_of(socket).instance_variable_get(:@renegotiation_cb)&.call(socket)
        0
      end

      # ssl_encode_npn_protocols: each protocol, its length byte first.
      def encode_npn_protocols(protocols)
        encoded = "".b
        protocols.each do |protocol|
          length = protocol.bytesize
          raise error(OpenSSL::SSL::SSLError, "Advertised protocol must have length 1..255") unless length.between?(1, 255)

          encoded << length.chr << protocol.b
        end
        encoded
      end

      # ssl_npn_advertise_cb.
      def npn_advertise(_ssl, out, outlen, arg)
        protocols = Native.hidden_get(dereference(arg), :npn_protocols_encoded)
        Lib.write(out, [Native.address(protocols)].pack("J"))
        Lib.write(outlen, [protocols.bytesize].pack("L"))
        Lib::SSL_TLSEXT_ERR_OK
      end

      # ssl_npn_select_cb_common: the protocol the callback picks from
      # those the peer offers, which stays alive on the socket while the
      # library reads it.
      def select_protocol(ssl, ivar, out, outlen, input, input_length, arg)
        socket = ssl_socket(ssl)
        begin
          callback = dereference(arg).instance_variable_get(ivar)
          offered = Lib.read(input, input_length)
          protocols = []
          position = 0
          while position < offered.bytesize
            length = offered.getbyte(position)
            protocols << offered.byteslice(position + 1, length)
            position += 1 + length
          end
          selected = string_value(callback.call(protocols))
          raise error(OpenSSL::SSL::SSLError, "Selected protocol name must have length 1..255") unless selected.bytesize.between?(1, 255)
        rescue Exception => e # rubocop:disable Lint/RescueException
          callback_failed(socket, e)
          return Lib::SSL_TLSEXT_ERR_ALERT_FATAL
        end
        Native.hidden_set(socket, :selected_protocol, selected)
        Lib.write(out, [Native.address(selected)].pack("J"))
        Lib.write(outlen, [selected.bytesize].pack("C"))
        Lib::SSL_TLSEXT_ERR_OK
      end

      # ossl_sslctx_setup: the context's attributes applied to its SSL_CTX,
      # once; the context is frozen from here.
      def sslctx_setup(context)
        return nil if context.frozen?

        ctx = SSL_CTX.get(context)
        ivar = ->(name) { context.instance_variable_get(name) }
        unless ivar.(:@tmp_dh_callback).nil?
          Lib.SSL_CTX_set_tmp_dh_callback(ctx, TMP_DH_CB)
          Lib.SSL_CTX_set_dh_auto(ctx, 0)
        end
        Lib.SSL_CTX_set_post_handshake_auth(ctx, 1)
        store = ivar.(:@cert_store)
        unless store.nil?
          x509store = x509store(store)
          Lib.SSL_CTX_set_cert_store(ctx, x509store)
          Lib.X509_STORE_up_ref(x509store)
        end
        extra = ivar.(:@extra_chain_cert)
        extra&.each do |certificate|
          x509 = dup_x509(certificate)
          if Lib.SSL_CTX_ctrl(ctx, Lib::SSL_CTRL_EXTRA_CHAIN_CERT, 0, x509).zero?
            Lib.X509_free(x509)
            raise error(OpenSSL::SSL::SSLError, "SSL_CTX_add_extra_chain_cert")
          end
        end
        certificate = ivar.(:@cert)
        cert = certificate.nil? ? nil : x509(certificate)
        key_object = ivar.(:@key)
        key = key_object.nil? ? nil : private_pkey(key_object)
        if cert && key
          raise error(OpenSSL::SSL::SSLError, "SSL_CTX_use_certificate") if Lib.SSL_CTX_use_certificate(ctx, cert).zero?
          raise error(OpenSSL::SSL::SSLError, "SSL_CTX_use_PrivateKey") if Lib.SSL_CTX_use_PrivateKey(ctx, key).zero?
          raise error(OpenSSL::SSL::SSLError, "SSL_CTX_check_private_key") if Lib.SSL_CTX_check_private_key(ctx).zero?
        end
        client_ca = ivar.(:@client_ca)
        unless client_ca.nil?
          (client_ca.is_a?(Array) ? client_ca : [client_ca]).each do |ca|
            raise error(OpenSSL::SSL::SSLError, "SSL_CTX_add_client_CA") if Lib.SSL_CTX_add_client_CA(ctx, x509(ca)).zero?
          end
        end
        ca_file = ivar.(:@ca_file)
        ca_file = cstring_value(ca_file) unless ca_file.nil?
        ca_path = ivar.(:@ca_path)
        ca_path = cstring_value(ca_path) unless ca_path.nil?
        raise error(OpenSSL::SSL::SSLError, "SSL_CTX_load_verify_file") if ca_file && Lib.SSL_CTX_load_verify_file(ctx, ca_file).zero?
        raise error(OpenSSL::SSL::SSLError, "SSL_CTX_load_verify_dir") if ca_path && Lib.SSL_CTX_load_verify_dir(ctx, ca_path).zero?

        verify_mode = ivar.(:@verify_mode)
        Lib.SSL_CTX_set_verify(ctx, verify_mode.nil? ? 0 : int(verify_mode), SSL_VERIFY_CB)
        Lib.SSL_CTX_set_client_cert_cb(ctx, CLIENT_CERT_CB) if ivar.(:@client_cert_cb)
        timeout = ivar.(:@timeout)
        Lib.SSL_CTX_set_timeout(ctx, long(timeout)) unless timeout.nil?
        depth = ivar.(:@verify_depth)
        Lib.SSL_CTX_set_verify_depth(ctx, int(depth)) unless depth.nil?
        protocols = ivar.(:@npn_protocols)
        unless protocols.nil?
          Native.hidden_set(context, :npn_protocols_encoded, encode_npn_protocols(protocols))
          Lib.SSL_CTX_set_next_protos_advertised_cb(ctx, NPN_ADVERTISE_CB, reference(context))
        end
        Lib.SSL_CTX_set_next_proto_select_cb(ctx, NPN_SELECT_CB, reference(context)) if ivar.(:@npn_select_cb)
        protocols = ivar.(:@alpn_protocols)
        unless protocols.nil?
          encoded = encode_npn_protocols(protocols)
          raise error(OpenSSL::SSL::SSLError, "SSL_CTX_set_alpn_protos") unless Lib.SSL_CTX_set_alpn_protos(ctx, encoded, encoded.bytesize).zero?
        end
        Lib.SSL_CTX_set_alpn_select_cb(ctx, ALPN_SELECT_CB, reference(context)) if ivar.(:@alpn_select_cb)
        OBJECT_FREEZE.bind_call(context)
        session_id = ivar.(:@session_id_context)
        unless session_id.nil?
          session_id = string_value(session_id)
          raise error(OpenSSL::SSL::SSLError, "SSL_CTX_set_session_id_context") if Lib.SSL_CTX_set_session_id_context(ctx, session_id, session_id.bytesize).zero?
        end
        Lib.SSL_CTX_sess_set_get_cb(ctx, SESSION_GET_CB) if ivar.(:@session_get_cb)
        Lib.SSL_CTX_sess_set_new_cb(ctx, SESSION_NEW_CB) if ivar.(:@session_new_cb)
        Lib.SSL_CTX_sess_set_remove_cb(ctx, SESSION_REMOVE_CB) if ivar.(:@session_remove_cb)
        Lib.SSL_CTX_set_tlsext_servername_callback(ctx, SERVERNAME_CB) unless ivar.(:@servername_cb).nil?
        Lib.SSL_CTX_set_keylog_callback(ctx, KEYLOG_CB) if ivar.(:@keylog_cb)
        true
      end

      # parse_proto_version.
      def proto_version(value)
        return 0 if value.nil?
        return int(value) if value.is_a?(Integer)

        value = value.to_s if value.is_a?(Symbol)
        text = string_value(value)
        PROTOCOL_VERSIONS.each { |name, version| return version if name.start_with?(text) }
        raise ArgumentError, "unrecognized version #{text.inspect}"
      end

      # ossl_ssl_cipher_to_ary.
      def cipher_to_ary(cipher)
        algorithm_bits = Lib.buffer(4)
        bits = Lib.SSL_CIPHER_get_bits(cipher, algorithm_bits)
        [Lib.SSL_CIPHER_get_name(cipher), Lib.SSL_CIPHER_get_version(cipher), bits, algorithm_bits.unpack1("l")]
      end

      # build_cipher_string.
      def cipher_string(value)
        return string_value(value) unless value.is_a?(Array)

        value.map { |element| Kernel.String(element.is_a?(Array) ? element[0] : element) }.join(":")
      end

      # ssl_started.
      def ssl_started?(ssl) = !Lib.SSL_get_rbio(ssl).zero?

      # ossl_ssl_setup.
      def ssl_setup(socket)
        ssl = ssl(socket)
        return true if ssl_started?(ssl)

        io = socket.instance_variable_get(:@io)
        raise IOError, "uninitialized stream" unless io.is_a?(IO)
        raise IOError, "closed stream" if io.closed?

        raise error(OpenSSL::SSL::SSLError, "SSL_set_fd") if Lib.SSL_set_fd(ssl, io.fileno).zero?

        true
      end

      # A callback's exception, raised once the SSL call returns.
      def raise_callback_state(socket, keep: false)
        state = Native.hidden_get(socket, :callback_state)
        return if state.nil?

        Native.hidden_set(socket, :callback_state, nil) unless keep
        clear_error
        raise state
      end

      # peeraddr_ip_str.
      def peer_ip(io)
        io.remote_address.inspect_sockaddr
      rescue SystemCallError
        "(null)"
      end

      # ossl_start_ssl: one SSL_connect or SSL_accept: the socket once the
      # handshake is done, or what it waits for; SSLSocket#connect and
      # #accept wait and call again.
      def start_ssl(socket, function, name)
        Native.hidden_set(socket, :callback_state, nil)
        ssl = ssl(socket)
        io = socket.instance_variable_get(:@io)
        loop do
          answer, errno = Lib.public_send(function, ssl)
          raise_callback_state(socket, keep: true)
          code = Lib.SSL_get_error(ssl, answer)
          case code
          when Lib::SSL_ERROR_NONE then return socket
          when Lib::SSL_ERROR_WANT_WRITE then return :wait_writable
          when Lib::SSL_ERROR_WANT_READ then return :wait_readable
          when Lib::SSL_ERROR_SYSCALL
            unless errno.zero?
              clear_error
              # See ssl_write.
              next if RUBY_PLATFORM.include?("darwin") && errno == Errno::EPROTOTYPE::Errno

              raise SystemCallError.new(name, errno)
            end
          end
          append = ""
          last = Lib.ERR_peek_last_error
          if Lib.ERR_GET_LIB(last) == Lib::ERR_LIB_SSL && Lib.ERR_GET_REASON(last) == Lib::SSL_R_CERTIFICATE_VERIFY_FAILED
            reason = Lib.ERR_reason_error_string(last) || "(null)"
            verify = Lib.X509_verify_cert_error_string(Lib.SSL_get_verify_result(ssl)) || "(null)"
            clear_error
            append = ": #{reason} (#{verify})"
          end
          raise error(OpenSSL::SSL::SSLError,
                      "#{name}#{" SYSCALL" if code == Lib::SSL_ERROR_SYSCALL} returned=#{code} errno=#{errno} " \
                      "peeraddr=#{peer_ip(io)} state=#{Lib.SSL_state_string_long(ssl)}#{append}")
        end
      end

      # ossl_ssl_read: one SSL_read of at most `length` bytes into
      # `buffer`: the buffer, nil at the end of the stream, or what it
      # waits for.
      def ssl_read(socket, length, buffer)
        ssl = ssl(socket)
        raise OpenSSL::SSL::SSLError, "SSL session is not started yet" unless ssl_started?(ssl)

        length = int(length)
        buffer = string_value(buffer)
        check_frozen(buffer)
        return buffer.clear if length.zero?

        out = Lib.buffer(length)
        count, errno = Lib.SSL_read_errno(ssl, out, length)
        raise_callback_state(socket)
        case Lib.SSL_get_error(ssl, count)
        when Lib::SSL_ERROR_NONE then buffer.replace(out.byteslice(0, count).force_encoding(buffer.encoding))
        when Lib::SSL_ERROR_ZERO_RETURN then nil
        when Lib::SSL_ERROR_WANT_WRITE then :wait_writable
        when Lib::SSL_ERROR_WANT_READ then :wait_readable
        when Lib::SSL_ERROR_SYSCALL
          unless errno.zero?
            clear_error
            raise SystemCallError.new("SSL_read", errno)
          end
          # The peer closed the connection with no shutdown of TLS, which
          # counts as the end of the stream.
          return nil if Lib.ERR_peek_error.zero?

          raise error(OpenSSL::SSL::SSLError, "SSL_read")
        else
          raise error(OpenSSL::SSL::SSLError, "SSL_read")
        end
      end

      # ossl_ssl_write: one SSL_write of `data`: the bytes written, or what
      # it waits for.
      def ssl_write(socket, data)
        ssl = ssl(socket)
        raise OpenSSL::SSL::SSLError, "SSL session is not started yet" unless ssl_started?(ssl)

        data = string_value(data)
        length = int(data.bytesize)
        return 0 if length.zero?

        loop do
          written, errno = Lib.SSL_write_errno(ssl, data, length)
          raise_callback_state(socket)
          case Lib.SSL_get_error(ssl, written)
          when Lib::SSL_ERROR_NONE then return written
          when Lib::SSL_ERROR_WANT_WRITE then return :wait_writable
          when Lib::SSL_ERROR_WANT_READ then return :wait_readable
          when Lib::SSL_ERROR_SYSCALL
            unless errno.zero?
              clear_error
              # send(2) on macOS can fail with EPROTOTYPE while the socket
              # is torn down; the next try gives the real errno (#14713).
              next if RUBY_PLATFORM.include?("darwin") && errno == Errno::EPROTOTYPE::Errno

              raise SystemCallError.new("SSL_write", errno)
            end
          end
          raise error(OpenSSL::SSL::SSLError, "SSL_write")
        end
      end

      # A finished message: its length first, then its bytes.
      def finished_message(ssl, function)
        length = Lib.public_send(function, ssl, Lib.buffer(1), 0)
        return nil if length.zero?

        out = Lib.buffer(length)
        Lib.public_send(function, ssl, out, length)
        out
      end

      # SSL_get0_next_proto_negotiated and SSL_get0_alpn_selected.
      def negotiated_protocol(ssl, function)
        data = Lib.buffer(8)
        length = Lib.buffer(4)
        Lib.public_send(function, ssl, data, length)
        length = length.unpack1("L")
        length.zero? ? nil : Lib.read(Lib.pointer_at(data), length)
      end

      # A signature algorithm's name through SSL_ctrl, or nil.
      def ssl_ctrl_name(ssl, ctrl)
        name = Lib.buffer(8)
        return nil if Lib.SSL_ctrl(ssl, ctrl, 0, name).zero?

        Lib.string(Lib.pointer_at(name))
      end
    end

    OBJECT_FREEZE = Object.instance_method(:freeze)

    SSL_VERIFY_CB = Lib.callback { |ok, ctx| ssl_verify(Lib::RETURNS[:int].(ok), ctx) }
    CLIENT_CERT_CB = Lib.callback { |ssl, x509, pkey| client_cert(ssl, x509, pkey) }
    TMP_DH_CB = Lib.callback { |ssl, is_export, keylength| tmp_dh(ssl, Lib::RETURNS[:int].(is_export), Lib::RETURNS[:int].(keylength)) }
    SESSION_GET_CB = Lib.callback { |ssl, buffer, length, copy| session_get(ssl, buffer, Lib::RETURNS[:int].(length), copy) }
    SESSION_NEW_CB = Lib.callback { |ssl, session| session_new(ssl, session) }
    SESSION_REMOVE_CB = Lib.callback { |ctx, session| session_remove(ctx, session) }
    KEYLOG_CB = Lib.callback { |ssl, line| keylog(ssl, line) }
    SERVERNAME_CB = Lib.callback { |ssl, alert, arg| servername(ssl, alert, arg) }
    INFO_CB = Lib.callback { |ssl, where, value| ssl_info(ssl, Lib::RETURNS[:int].(where), value) }
    NPN_ADVERTISE_CB = Lib.callback { |ssl, out, outlen, arg| npn_advertise(ssl, out, outlen, arg) }
    NPN_SELECT_CB = Lib.callback do |ssl, out, outlen, input, input_length, arg|
      select_protocol(ssl, :@npn_select_cb, out, outlen, input, Lib::RETURNS[:uint].(input_length), arg)
    end
    ALPN_SELECT_CB = Lib.callback do |ssl, out, outlen, input, input_length, arg|
      select_protocol(ssl, :@alpn_select_cb, out, outlen, input, Lib::RETURNS[:uint].(input_length), arg)
    end
  end

  module SSL
    class SSLContext
      %i[cert key client_ca ca_file ca_path timeout verify_mode verify_depth verify_callback verify_hostname
         cert_store extra_chain_cert client_cert_cb tmp_dh_callback session_id_context session_get_cb
         session_new_cb session_remove_cb renegotiation_cb npn_protocols npn_select_cb alpn_protocols
         alpn_select_cb keylog_cb].each do |name|
        variable = :"@#{name}"
        define_method(name) { instance_variable_get(variable) }
        define_method(:"#{name}=") { |value| instance_variable_set(variable, value) }
      end
      alias ssl_timeout timeout
      alias ssl_timeout= timeout=

      # As rb_undef_method, a second load of this file undefines nothing.

      undef_method :initialize_copy if private_method_defined?(:initialize_copy)

      def min_version=(version)
        Ossl.check_frozen(self)
        ctx = Ossl::SSL_CTX.get(self)
        raise Ossl.error(SSLError, "SSL_CTX_set_min_proto_version") if Lib.SSL_CTX_set_min_proto_version(ctx, Ossl.proto_version(version)).zero?

        version
      end

      def max_version=(version)
        Ossl.check_frozen(self)
        ctx = Ossl::SSL_CTX.get(self)
        raise Ossl.error(SSLError, "SSL_CTX_set_max_proto_version") if Lib.SSL_CTX_set_max_proto_version(ctx, Ossl.proto_version(version)).zero?

        version
      end

      def ciphers
        stack = Lib.SSL_CTX_get_ciphers(Ossl::SSL_CTX.get(self))
        Ossl.stack_items(stack).map { |cipher| Ossl.cipher_to_ary(cipher) }
      end

      def ciphers=(value)
        Ossl.check_frozen(self)
        return value if value.nil?

        text = Ossl.cipher_string(value)
        raise Ossl.error(SSLError, "SSL_CTX_set_cipher_list") if Lib.SSL_CTX_set_cipher_list(Ossl::SSL_CTX.get(self), Ossl.cstring_value(text)).zero?

        value
      end

      def ciphersuites=(value)
        Ossl.check_frozen(self)
        return value if value.nil?

        text = Ossl.cipher_string(value)
        raise Ossl.error(SSLError, "SSL_CTX_set_ciphersuites") if Lib.SSL_CTX_set_ciphersuites(Ossl::SSL_CTX.get(self), Ossl.cstring_value(text)).zero?

        value
      end

      def sigalgs=(value)
        Ossl.check_frozen(self)
        ctx = Ossl::SSL_CTX.get(self)
        raise Ossl.error(SSLError, "SSL_CTX_set1_sigalgs_list") if Lib.SSL_CTX_ctrl(ctx, Lib::SSL_CTRL_SET_SIGALGS_LIST, 0, Native.cstring(Ossl.cstring_value(value))).zero?

        value
      end

      def client_sigalgs=(value)
        Ossl.check_frozen(self)
        ctx = Ossl::SSL_CTX.get(self)
        raise Ossl.error(SSLError, "SSL_CTX_set1_client_sigalgs_list") if Lib.SSL_CTX_ctrl(ctx, Lib::SSL_CTRL_SET_CLIENT_SIGALGS_LIST, 0, Native.cstring(Ossl.cstring_value(value))).zero?

        value
      end

      def tmp_dh=(dh)
        Ossl.check_frozen(self)
        ctx = Ossl::SSL_CTX.get(self)
        pkey = Ossl.pkey(dh)
        type = Lib.EVP_PKEY_get_base_id(pkey)
        raise SSLError, "invalid pkey type #{Lib.string(Lib.OBJ_nid2sn(type))} (expected DH)" if type != Lib::EVP_PKEY_DH
        raise Ossl.error(SSLError, "SSL_CTX_set0_tmp_dh_pkey") if Lib.SSL_CTX_set0_tmp_dh_pkey(ctx, pkey).zero?

        Lib.EVP_PKEY_up_ref(pkey)
        Lib.SSL_CTX_set_dh_auto(ctx, 0)
        dh
      end

      def groups=(groups)
        Ossl.check_frozen(self)
        ctx = Ossl::SSL_CTX.get(self)
        text = Ossl.cstring_value(groups)
        raise Ossl.error(SSLError, "SSL_CTX_set1_groups_list") if Lib.SSL_CTX_ctrl(ctx, Lib::SSL_CTRL_SET_GROUPS_LIST, 0, Native.cstring(text)).zero?

        groups
      end
      alias ecdh_curves= groups=

      def security_level = Lib.SSL_CTX_get_security_level(Ossl::SSL_CTX.get(self))

      def security_level=(level)
        Ossl.check_frozen(self)
        Lib.SSL_CTX_set_security_level(Ossl::SSL_CTX.get(self), Ossl.int(level))
        level
      end

      def enable_fallback_scsv
        Lib.SSL_CTX_set_mode(Ossl::SSL_CTX.get(self), Lib::SSL_MODE_SEND_FALLBACK_SCSV)
        nil
      end

      def add_certificate(cert, key, *rest)
        raise ArgumentError, "wrong number of arguments (given #{rest.size + 2}, expected 2..3)" if rest.size > 1

        ctx = Ossl::SSL_CTX.get(self)
        Ossl.check_frozen(self)
        x509 = Ossl.x509(cert)
        pkey = Ossl.private_pkey(key)
        public_key = Lib.X509_get_pubkey(x509)
        Lib.EVP_PKEY_free(public_key) unless public_key.zero?
        raise ArgumentError, "certificate does not contain public key" if public_key.zero?
        raise ArgumentError, "public key mismatch" if Lib.EVP_PKEY_eq(public_key, pkey) != 1

        chain = rest.empty? ? nil : Ossl.x509_ary2sk(rest.first)
        failure = if Lib.SSL_CTX_use_certificate(ctx, x509).zero? then "SSL_CTX_use_certificate"
                  elsif Lib.SSL_CTX_use_PrivateKey(ctx, pkey).zero? then "SSL_CTX_use_PrivateKey"
                  elsif chain && Lib.SSL_CTX_ctrl(ctx, Lib::SSL_CTRL_CHAIN, 0, chain).zero? then "SSL_CTX_set0_chain"
                  end
        if failure
          Ossl.free_x509_stack(chain)
          raise Ossl.error(SSLError, failure)
        end
        self
      end

      def setup = Ossl.sslctx_setup(self)
      alias freeze setup

      def session_add(session) = Lib.SSL_CTX_add_session(Ossl::SSL_CTX.get(self), Ossl::SSL_SESSION.fetch(session)) == 1

      def session_remove(session) = Lib.SSL_CTX_remove_session(Ossl::SSL_CTX.get(self), Ossl::SSL_SESSION.fetch(session)) == 1

      def session_cache_mode = Lib.SSL_CTX_ctrl(Ossl::SSL_CTX.get(self), Lib::SSL_CTRL_GET_SESS_CACHE_MODE, 0, nil)

      def session_cache_mode=(mode)
        Lib.SSL_CTX_ctrl(Ossl::SSL_CTX.get(self), Lib::SSL_CTRL_SET_SESS_CACHE_MODE, Ossl.long(mode), nil)
        mode
      end

      def session_cache_size = Lib.SSL_CTX_ctrl(Ossl::SSL_CTX.get(self), Lib::SSL_CTRL_GET_SESS_CACHE_SIZE, 0, nil)

      def session_cache_size=(size)
        Lib.SSL_CTX_ctrl(Ossl::SSL_CTX.get(self), Lib::SSL_CTRL_SET_SESS_CACHE_SIZE, Ossl.long(size), nil)
        size
      end

      def session_cache_stats
        ctx = Ossl::SSL_CTX.get(self)
        {
          cache_num: Lib::SSL_CTRL_SESS_NUMBER, connect: Lib::SSL_CTRL_SESS_CONNECT,
          connect_good: Lib::SSL_CTRL_SESS_CONNECT_GOOD, connect_renegotiate: Lib::SSL_CTRL_SESS_CONNECT_RENEGOTIATE,
          accept: Lib::SSL_CTRL_SESS_ACCEPT, accept_good: Lib::SSL_CTRL_SESS_ACCEPT_GOOD,
          accept_renegotiate: Lib::SSL_CTRL_SESS_ACCEPT_RENEGOTIATE, cache_hits: Lib::SSL_CTRL_SESS_HIT,
          cb_hits: Lib::SSL_CTRL_SESS_CB_HIT, cache_misses: Lib::SSL_CTRL_SESS_MISSES,
          cache_full: Lib::SSL_CTRL_SESS_CACHE_FULL, timeouts: Lib::SSL_CTRL_SESS_TIMEOUTS
        }.transform_values { |ctrl| Lib.SSL_CTX_ctrl(ctx, ctrl, 0, nil) }
      end

      def flush_sessions(time = nil)
        ctx = Ossl::SSL_CTX.get(self)
        seconds = if time.nil? then Time.now.to_i
                  elsif time.instance_of?(Time) then Ossl.long(time.to_i)
                  else raise Ossl.error(ArgumentError, "arg must be Time or nil")
                  end
        Lib.SSL_CTX_flush_sessions(ctx, seconds)
        self
      end

      def options = Lib.SSL_CTX_get_options(Ossl::SSL_CTX.get(self))

      def options=(options)
        Ossl.check_frozen(self)
        ctx = Ossl::SSL_CTX.get(self)
        Lib.SSL_CTX_clear_options(ctx, Lib.SSL_CTX_get_options(ctx))
        Lib.SSL_CTX_set_options(ctx, options.nil? ? OP_ALL : Ossl.ulong(options))
        options
      end
    end

    class SSLSocket
      def initialize(io, *rest, **options)
        Ossl.want_uninitialized(self, Ossl::SSL_CONNECTION)
        raise ArgumentError, "wrong number of arguments (given #{rest.size + 1}, expected 1..2)" if rest.size > 1

        unknown = options.keys - [:sync_close]
        raise ArgumentError, "unknown keyword#{"s" if unknown.size > 1}: #{unknown.map(&:inspect).join(", ")}" unless unknown.empty?

        context = rest.empty? ? SSLContext.new : rest.first
        @sync_close = options[:sync_close] if options.key?(:sync_close)
        ctx = Ossl::SSL_CTX.get(context)
        @context = context
        Ossl.sslctx_setup(context)
        io.nonblock = true if io.respond_to?(:nonblock=)
        raise TypeError, "wrong argument type #{Ossl.type_name(io)} (expected File)" unless io.is_a?(IO)

        @io = io
        ssl = Lib.SSL_new(ctx)
        raise Ossl.error(SSLError) if ssl.zero?

        Ossl::SSL_CONNECTION.set(self, ssl)
        Lib.SSL_set_ex_data(ssl, Ossl::SSL_EX_PTR_INDEX, Ossl.reference(self))
        Lib.SSL_set_info_callback(ssl, Ossl::INFO_CB)
        super()
      end

      # As rb_undef_method, a second load of this file undefines nothing.

      undef_method :initialize_copy if private_method_defined?(:initialize_copy)

      # The handshake, read and write calls: one call each, which
      # openssl/ssl.rb's connect, accept, sysread and syswrite wait for
      # and repeat.
      private def ssl_connect
        Ossl.ssl_setup(self)
        Ossl.start_ssl(self, :SSL_connect_errno, "SSL_connect")
      end

      private def ssl_accept
        Ossl.ssl_setup(self)
        Ossl.start_ssl(self, :SSL_accept_errno, "SSL_accept")
      end

      # rb_str_buf_new: an empty binary String for a read of `length`.
      private def string_new_capacity(length)
        Ossl.long(length)
        +"".b
      end

      private def ssl_read(length, buffer) = Ossl.ssl_read(self, length, buffer)

      private def ssl_write(data) = Ossl.ssl_write(self, data)

      def cert
        certificate = Lib.SSL_get_certificate(Ossl.ssl(self))
        certificate.zero? ? nil : Ossl.x509_new(certificate)
      end

      def peer_cert
        certificate = Lib.SSL_get1_peer_certificate(Ossl.ssl(self))
        return nil if certificate.zero?

        Ossl.take_certificate(certificate)
      end

      def peer_cert_chain
        chain = Lib.SSL_get_peer_cert_chain(Ossl.ssl(self))
        chain.zero? ? nil : Ossl.x509_sk2ary(chain)
      end

      def ssl_version = Lib.SSL_get_version(Ossl.ssl(self))

      def cipher
        cipher = Lib.SSL_get_current_cipher(Ossl.ssl(self))
        cipher.zero? ? nil : Ossl.cipher_to_ary(cipher)
      end

      def state
        ssl = Ossl.ssl(self)
        state = Lib.SSL_state_string(ssl)
        state << ": " << Lib.SSL_state_string_long(ssl) if $VERBOSE
        state
      end

      def pending = Lib.SSL_pending(Ossl.ssl(self))

      def session_reused? = !Lib.SSL_session_reused(Ossl.ssl(self)).zero?

      def session=(session)
        ssl = Ossl.ssl(self)
        raise Ossl.error(SSLError, "SSL_set_session") if Lib.SSL_set_session(ssl, Ossl::SSL_SESSION.fetch(session)) != 1

        session
      end

      def verify_result = Lib.SSL_get_verify_result(Ossl.ssl(self))

      def client_ca
        list = Lib.SSL_get_client_CA_list(Ossl.ssl(self))
        list.zero? ? nil : Ossl.stack_items(list).map { |name| Ossl.x509name_new(name) }
      end

      def hostname=(hostname)
        ssl = Ossl.ssl(self)
        name = hostname.nil? ? nil : Ossl.cstring_value(hostname)
        raise Ossl.error(SSLError) if Lib.SSL_set_tlsext_host_name(ssl, name).zero?

        @hostname = hostname
      end

      def finished_message = Ossl.finished_message(Ossl.ssl(self), :SSL_get_finished)

      def peer_finished_message = Ossl.finished_message(Ossl.ssl(self), :SSL_get_peer_finished)

      def tmp_key
        key = Lib.buffer(8)
        return nil if Lib.SSL_ctrl(Ossl.ssl(self), Lib::SSL_CTRL_GET_PEER_TMP_KEY, 0, key).zero?

        Ossl.pkey_wrap(Lib.pointer_at(key))
      end

      def alpn_protocol = Ossl.negotiated_protocol(Ossl.ssl(self), :SSL_get0_alpn_selected)

      def export_keying_material(label, length, context = nil)
        label = Ossl.string_value(label)
        ssl = Ossl.ssl(self)
        length = Ossl.long(length)
        out = Lib.buffer(length)
        context = Ossl.string_value(context) unless context.nil?
        answer = Lib.SSL_export_keying_material(ssl, out, length, label, label.bytesize, context, context&.bytesize || 0, context.nil? ? 0 : 1)
        raise Ossl.error(SSLError, "SSL_export_keying_material") if answer.zero? || answer == -1

        out
      end

      def npn_protocol = Ossl.negotiated_protocol(Ossl.ssl(self), :SSL_get0_next_proto_negotiated)

      if Lib.OpenSSL_version_num >= 0x30500000
        def sigalg = Ossl.ssl_ctrl_name(Ossl.ssl(self), Lib::SSL_CTRL_GET_SIGNATURE_NAME)

        def peer_sigalg = Ossl.ssl_ctrl_name(Ossl.ssl(self), Lib::SSL_CTRL_GET_PEER_SIGNATURE_NAME)
      end

      if Lib.respond_to?(:SSL_get0_group_name)
        def group = Lib.SSL_get0_group_name(Ossl.ssl(self))
      end

      private

      def stop
        ssl = Ossl.ssl(self)
        return nil unless Ossl.ssl_started?(ssl)

        answer = Lib.SSL_shutdown(ssl)
        Ossl.clear_error unless answer.zero? || answer == 1
        nil
      end
    end
  end
end
