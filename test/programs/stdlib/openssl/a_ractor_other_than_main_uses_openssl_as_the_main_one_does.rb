# OpenSSL's C functions and types are ractor-safe in ruby, so a Ractor
# other than main digests, ciphers, reads certificates and talks TLS.
require "openssl"
require "socket"
Warning[:experimental] = false

key = OpenSSL::PKey::EC.generate("prime256v1")
cert = OpenSSL::X509::Certificate.new
cert.version = 2
cert.serial = 1
cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=localhost")
cert.public_key = key
cert.not_before = Time.now - 60
cert.not_after = Time.now + 3600
cert.sign(key, "SHA256")
pem = cert.to_pem.freeze

p(Ractor.new(pem) do |text|
  c = OpenSSL::X509::Certificate.new(text)
  store = OpenSSL::X509::Store.new.tap { |s| s.add_cert(c) }
  cipher = OpenSSL::Cipher.new("aes-128-cbc").encrypt
  cipher.key = "k" * 16
  cipher.iv = "i" * 16
  sealed = cipher.update("ractor") + cipher.final
  plain = OpenSSL::Cipher.new("aes-128-cbc").decrypt.tap { |d| d.key = "k" * 16; d.iv = "i" * 16 }
  [c.subject.to_s, store.verify(c), OpenSSL::Digest::SHA256.hexdigest("abc")[0, 16],
   OpenSSL::HMAC.hexdigest("SHA256", "key", "data")[0, 16], plain.update(sealed) + plain.final,
   (OpenSSL::BN.new(2) ** 70).to_i]
end.value)

server = TCPServer.new("127.0.0.1", 0)
port = server.addr[1]
context = OpenSSL::SSL::SSLContext.new
context.cert = cert
context.key = key
tls = OpenSSL::SSL::SSLServer.new(server, context)
serving = Thread.new do
  conn = tls.accept
  conn.puts "hello #{conn.gets.chomp}"
  conn.close
end
p(Ractor.new(port, pem) do |pt, text|
  ctx = OpenSSL::SSL::SSLContext.new
  ctx.cert_store = OpenSSL::X509::Store.new.tap { |s| s.add_cert(OpenSSL::X509::Certificate.new(text)) }
  ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
  sock = OpenSSL::SSL::SSLSocket.new(TCPSocket.new("127.0.0.1", pt), ctx)
  sock.hostname = "localhost"
  sock.sync_close = true
  sock.connect
  sock.puts "ractor"
  answer = sock.gets.chomp
  sock.close
  [answer, sock.closed?]
end.value)
serving.join
