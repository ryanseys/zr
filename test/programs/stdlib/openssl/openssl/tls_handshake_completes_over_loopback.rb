# SSL over the host's libssl: a server and a client in one process over
# 127.0.0.1, with a certificate made here. The client verifies the peer
# and its host name, both sides pick ALPN "h2", and lines echo both ways;
# a second connection resumes the first session, and a client that trusts
# nothing fails verification.

require "openssl"
require "socket"

key = OpenSSL::PKey::EC.generate("prime256v1")
cert = OpenSSL::X509::Certificate.new
cert.version = 2
cert.serial = 1
cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=localhost")
cert.public_key = key
cert.not_before = Time.now - 3600
cert.not_after = Time.now + 3600
factory = OpenSSL::X509::ExtensionFactory.new(cert, cert)
cert.add_extension(factory.create_extension("subjectAltName", "DNS:localhost, IP:127.0.0.1"))
cert.add_extension(factory.create_extension("basicConstraints", "CA:TRUE", true))
cert.sign(key, "SHA256")

server_ctx = OpenSSL::SSL::SSLContext.new
server_ctx.cert = cert
server_ctx.key = key
server_ctx.min_version = OpenSSL::SSL::TLS1_2_VERSION
server_ctx.alpn_protocols = %w[h2 http/1.1]
server_ctx.alpn_select_cb = ->(protocols) { protocols.include?("h2") ? "h2" : protocols.first }
server_ctx.session_id_context = "zr"
server_names = []
server_ctx.servername_cb = proc { |_ssl, name| server_names << name; nil }

tcp = TCPServer.new("127.0.0.1", 0)
server = OpenSSL::SSL::SSLServer.new(tcp, server_ctx)
port = tcp.addr[1]

acceptor = Thread.new do
  3.times.map do
    ssl = server.accept
    while (line = ssl.gets)
      ssl.puts(line.upcase)
    end
    ssl.close
    :served
  rescue OpenSSL::SSL::SSLError => e
    "server: #{e.class}"
  end
end

def connect(port, ctx, session = nil)
  sock = TCPSocket.new("127.0.0.1", port)
  ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
  ssl.hostname = "localhost"
  ssl.session = session if session
  ssl.sync_close = true
  ssl.connect
  ssl
end

store = OpenSSL::X509::Store.new
store.add_cert(cert)
client_ctx = OpenSSL::SSL::SSLContext.new
client_ctx.cert_store = store
client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
client_ctx.verify_hostname = true
client_ctx.alpn_protocols = %w[h2 http/1.1]
new_sessions = 0
client_ctx.session_cache_mode = OpenSSL::SSL::SSLContext::SESSION_CACHE_CLIENT
client_ctx.session_new_cb = proc { new_sessions += 1 }

ssl = connect(port, client_ctx)
p ssl.alpn_protocol, ssl.verify_result == OpenSSL::X509::V_OK, ssl.peer_cert.subject.to_s
p ssl.peer_cert_chain.size, ssl.cipher.first.start_with?("TLS_"), ssl.ssl_version.start_with?("TLS")
ssl.puts "hello"
ssl.write "world\n"
p ssl.gets, ssl.readpartial(100)
ssl.puts "bye"
p ssl.read(4)
ssl.post_connection_check("localhost")
begin
  ssl.post_connection_check("example.com")
rescue OpenSSL::SSL::SSLError => e
  puts "SSLError #{e.message}"
end
session = ssl.session
ssl.close
p ssl.closed?

ssl = connect(port, client_ctx, session)
ssl.puts "again"
p ssl.gets
ssl.close

untrusting = OpenSSL::SSL::SSLContext.new
untrusting.cert_store = OpenSSL::X509::Store.new
untrusting.verify_mode = OpenSSL::SSL::VERIFY_PEER
begin
  connect(port, untrusting)
rescue OpenSSL::SSL::SSLError => e
  puts "SSLError #{e.message.include?("certificate verify failed")}"
end

p acceptor.value.map { |v| v.is_a?(String) ? v.split(":").first : v }
p server_names.uniq, new_sessions.positive?
server.close

