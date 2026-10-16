# Ractor.make_shareable refuses an object that CRuby keeps as T_DATA of
# a type with no RUBY_TYPED_FROZEN_SHAREABLE, frozen or not, as the ports'
# C does; Date, OpenSSL::BN and Config, and plain Ruby objects, become
# shareable.
require "psych"; require "stringio"; require "strscan"; require "zlib"; require "digest"; require "date"; require "openssl"; require "socket"
require "bigdecimal"; require "ripper"; require "pathname"; require "etc"
objs = { "Psych::Parser" => Psych::Parser.new, "Psych::Emitter" => Psych::Emitter.new(nil), "StringIO" => StringIO.new, "StringScanner" => StringScanner.new(""),
"Zlib::Deflate" => Zlib::Deflate.new, "Zlib::Inflate" => Zlib::Inflate.new, "Digest::SHA256" => Digest::SHA256.new, "Date" => Date.today, "DateTime" => DateTime.now,
"OpenSSL::Digest" => OpenSSL::Digest.new("SHA256"), "OpenSSL::BN" => OpenSSL::BN.new(1), "OpenSSL::PKey::EC" => OpenSSL::PKey::EC.generate("prime256v1"), "OpenSSL::Cipher" => OpenSSL::Cipher.new("aes-128-cbc"),
"OpenSSL::X509::Name" => OpenSSL::X509::Name.new, "OpenSSL::X509::Store" => OpenSSL::X509::Store.new, "OpenSSL::SSL::SSLContext" => OpenSSL::SSL::SSLContext.new, "OpenSSL::HMAC" => OpenSSL::HMAC.new("k", "SHA256"),
"BigDecimal" => BigDecimal("1"), "Addrinfo" => Addrinfo.tcp("127.0.0.1", 80), "Socket::Option" => Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 1), "Ripper" => Ripper.new(""), "Pathname" => Pathname("x"), "Etc::Passwd" => Etc.getpwuid }
objs.each { |n, o| r = begin; Ractor.make_shareable(o); :ok; rescue => e; e.class; end; puts "#{n}: #{r}" }
require "zlib"
frozen = StringIO.new.freeze
p [frozen.frozen?, Ractor.shareable?(frozen)]
sub = Class.new(Psych::Parser)
p (Ractor.make_shareable(sub.new) rescue $!.class)
p (Ractor.make_shareable(Zlib::GzipWriter.new(StringIO.new)) rescue $!.class)
p (Ractor.make_shareable([1, "two", StringScanner.new("x")]) rescue [$!.class, $!.message[0, 40]])
p Ractor.shareable?(Ractor.make_shareable(OpenSSL::Config.new))
