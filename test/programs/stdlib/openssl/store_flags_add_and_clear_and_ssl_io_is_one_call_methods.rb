# A Store's and a StoreContext's verification flags: `flags=` adds to
# the flags that are set, and warns when the new flags do not cover
# them; `clear_flags` takes some away, or all of them. An SSLSocket's
# handshake, read and write are private methods that make one call
# each, which openssl/ssl.rb's public methods repeat.
require "openssl"
require "socket"

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

crl = OpenSSL::X509::V_FLAG_CRL_CHECK
partial = OpenSSL::X509::V_FLAG_PARTIAL_CHAIN

store = OpenSSL::X509::Store.new
show("new store") { store.flags }
show("set") { store.flags = crl }
show("flags") { store.flags == crl }
show("add") { store.flags = partial }
show("both") { store.flags == (crl | partial) }
show("clear one") { store.clear_flags(crl) }
show("one left") { store.flags == partial }
show("clear all") { store.clear_flags }
show("none") { store.flags }
show("or-assign") { store.flags |= crl }
show("covering") { store.flags = crl | partial }
show("bad flags") { store.flags = "x" }
show("clear bad") { store.clear_flags("x") }

context = OpenSSL::X509::StoreContext.new(store)
show("context flags") { context.flags }
show("context clear") { context.clear_flags(partial) }
show("context left") { context.flags }
show("context add") { context.flags = partial }
show("context both") { context.flags }

methods = %i[ssl_connect ssl_accept ssl_read ssl_write string_new_capacity]
show("private") { methods.map { |name| OpenSSL::SSL::SSLSocket.private_method_defined?(name) } }
show("public") { %i[connect accept sysread syswrite].map { |name| OpenSSL::SSL::SSLSocket.public_method_defined?(name) } }

left, right = UNIXSocket.pair
socket = OpenSSL::SSL::SSLSocket.new(left)
show("read before start") { socket.sysread(1) }
show("write before start") { socket.syswrite("x") }
show("capacity") { socket.send(:string_new_capacity, 5).then { |s| [s, s.encoding] } }
show("capacity type") { socket.send(:string_new_capacity, "5") }
show("nonblock connect") { socket.connect_nonblock(exception: false) }
show("nonblock connect raises") { socket.connect_nonblock }
right.close
