# frozen_string_literal: true

require "spec_helper"

describe "Socket: reading and writing" do
  it "carries its exception hierarchy" do
    skip "runs only on macos" unless ["macos"].include?(Zr::Spec.platform)

    result = zr(<<~'RUBY')

      # `SocketError` and `Socket::ResolutionError` are C classes in CRuby
      # (`ext/socket/init.c`). A feature-gated native class here cannot register a
      # constructible exception, so they live in the gem's Ruby half -- the shape
      # `strscan` and `zlib` already use. Without them a resolution failure reached
      # for a class nothing had registered, which crashed the process rather than
      # raising.
      require "socket"

      p SocketError.superclass
      p Socket::ResolutionError.superclass
      p Socket::ResolutionError.ancestors.include?(StandardError)

      # CRuby's own class for a `getaddrinfo` failure since 3.4, and it inherits
      # `SocketError`, so the older `rescue SocketError` still catches it.
      begin
        Socket.getaddrinfo("nope.invalid.example", nil)
      rescue SocketError => e
        p e.class
        p e.message
        p e.error_code.is_a?(Integer)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      StandardError
      SocketError
      true
      Socket::ResolutionError
      "getaddrinfo: nodename nor servname provided, or not known"
      true
    OUT
  end

  it "generic socket class binds listens accepts and transfers" do
    result = zr(<<~'RUBY')
      # The generic Socket class is implemented over libc: new/bind/listen/accept
      # on a loopback pair, resolving the bound port through Socket.pack/
      # unpack_sockaddr_in and reading it back via #local_address (an Addrinfo).

      require "socket"
      srv = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      srv.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
      srv.bind(Socket.pack_sockaddr_in(0, "127.0.0.1"))
      srv.listen(1)
      port, ip = Socket.unpack_sockaddr_in(srv.getsockname)
      p ip
      p port > 0
      cli = Socket.new(:INET, :STREAM)
      cli.connect(Socket.sockaddr_in(port, "127.0.0.1"))
      conn, addr = srv.accept
      p conn.class
      p addr.class
      cli.write("ping")
      p conn.recv(4)
      conn.close
      cli.close
      srv.close
    RUBY

    _(result).must_answer <<~'OUT'
      "127.0.0.1"
      true
      Socket
      Addrinfo
      "ping"
    OUT
  end

  it "io select to io" do
    result = zr(<<~'RUBY')
      require "socket"

      class Wrapper
        def initialize(io)
          @io = io
        end
        def to_io
          @io
        end
      end

      r, w = IO.pipe
      wr = Wrapper.new(r)

      p IO.select([wr], nil, nil, 0).nil?

      w.write("hi")
      w.flush
      got = IO.select([wr], nil, nil, 1)
      p got.nil?
      p got[0].length
      p got[0][0].equal?(wr)
      p r.read_nonblock(2)

      ww = Wrapper.new(w)
      ready = IO.select(nil, [ww], nil, 1)
      p ready.nil?
      p ready[1][0].equal?(ww)

      w.write("x")
      w.flush
      mixed = IO.select([wr, r], nil, nil, 1)
      p mixed[0].length

      r.close
      w.close

      class NotAnIo
      end
      begin
        IO.select([NotAnIo.new], nil, nil, 0)
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      1
      true
      "hi"
      false
      true
      2
      TypeError: no implicit conversion of NotAnIo into IO
    OUT
  end

  it "the Addrinfo constructors fix the family, socktype and protocol the accessors read back" do
    result = zr(<<~'RUBY')
      # Addrinfo -- a resolved socket address value. The tcp/udp/ip/unix constructors
      # fix the family, socktype, and protocol; the accessors and #inspect read them
      # back. Oracle-verified against ruby 4.0.6 (Darwin family numbers: AF_INET 2,
      # AF_INET6 30, AF_UNIX 1).
      require "socket"

      t = Addrinfo.tcp("127.0.0.1", 80)
      p t.afamily == Socket::AF_INET
      p t.pfamily == Socket::PF_INET
      p t.socktype == Socket::SOCK_STREAM
      p t.protocol == Socket::IPPROTO_TCP
      p t.ip?
      p t.ipv4?
      p t.ipv6?
      p t.unix?
      p t.ip_address
      p t.ip_port
      p t.inspect

      u = Addrinfo.udp("127.0.0.1", 53)
      p u.socktype == Socket::SOCK_DGRAM
      p u.protocol == Socket::IPPROTO_UDP
      p u.inspect

      six = Addrinfo.tcp("::1", 443)
      p six.afamily == Socket::AF_INET6
      p six.ipv6?
      p six.ip_address
      p six.inspect

      bare = Addrinfo.ip("192.168.1.1")
      p bare.ip_port
      p bare.inspect

      ux = Addrinfo.unix("/tmp/app.sock")
      p ux.afamily == Socket::AF_UNIX
      p ux.unix?
      p ux.unix_path
      p ux.inspect

      # to_sockaddr round-trips through Socket.unpack_sockaddr_in.
      packed = Addrinfo.tcp("127.0.0.1", 8080).to_sockaddr
      p Socket.unpack_sockaddr_in(packed)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      false
      false
      "127.0.0.1"
      80
      "#<Addrinfo: 127.0.0.1:80 TCP>"
      true
      true
      "#<Addrinfo: 127.0.0.1:53 UDP>"
      true
      true
      "::1"
      "#<Addrinfo: [::1]:443 TCP>"
      0
      "#<Addrinfo: 192.168.1.1>"
      true
      true
      "/tmp/app.sock"
      "#<Addrinfo: /tmp/app.sock SOCK_STREAM>"
      [8080, "127.0.0.1"]
    OUT
  end

  it "local_address answers an Addrinfo, and getsockopt answers a Socket::Option" do
    result = zr(<<~'RUBY')
      # `BasicSocket#getsockopt` answers a `Socket::Option` object, which is not
      # implemented -- line 29 raises NotImplementedError.
      # Addrinfo and Socket::Option.
      require "socket"

      a = Addrinfo.tcp("127.0.0.1", 80)
      p a.class
      p a.ip_address
      p a.ip_port
      p a.afamily == Socket::AF_INET   # the AF_* values differ by platform
      p a.ipv4?
      p a.ipv6?
      p a.inspect

      b = Addrinfo.udp("::1", 53)
      p b.afamily == Socket::AF_INET6
      p b.ipv6?
      p b.inspect

      u = Addrinfo.unix("/tmp/spinel_ai.sock")
      p u.afamily == Socket::AF_UNIX
      p u.unix?

      srv = TCPServer.new("127.0.0.1", 0)
      la = srv.local_address
      p la.class
      p la.ip_address
      p la.ip_port == srv.addr[1]

      srv.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1)
      o = srv.getsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE)
      p o.class
      p o.int != 0
      p o.bool
      p o.level == Socket::SOL_SOCKET
      p o.optname == Socket::SO_KEEPALIVE
      srv.close
    RUBY

    _(result).must_answer <<~'OUT'
      Addrinfo
      "127.0.0.1"
      80
      true
      true
      false
      "#<Addrinfo: 127.0.0.1:80 TCP>"
      true
      true
      "#<Addrinfo: [::1]:53 UDP>"
      true
      true
      Addrinfo
      "127.0.0.1"
      true
      Socket::Option
      true
      true
      true
      true
    OUT
  end

  it "do_not_reverse_lookup, sockaddr_un and the ECONNREFUSED message each answer" do
    result = zr(<<~'RUBY')
      # Three socket-surface rows: `BasicSocket.do_not_reverse_lookup` (the
      # class-level accessor), `Socket.sockaddr_un`/`unpack_sockaddr_un`, and
      # the ECONNREFUSED message shape ('Connection refused - connect(2) for
      # "127.0.0.1" port N'; zr leaks the io layer's own text). (Found by the
      # 2026-08-24 probe sweep.)
      require "socket"
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message.sub(/port \d+/, 'port N')}"
      end
      show { BasicSocket.do_not_reverse_lookup }
      show { Socket.unpack_sockaddr_un(Socket.sockaddr_un("/tmp/u.sock")) }
      show do
        ghost = TCPServer.new("127.0.0.1", 0)
        port = ghost.addr[1]
        ghost.close
        TCPSocket.new("127.0.0.1", port)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "/tmp/u.sock"
      Errno::ECONNREFUSED: Connection refused - connect(2) for "127.0.0.1" port N
    OUT
  end

  it "the socket classes are constants after the require, and Socket::Constants holds the same names" do
    result = zr(<<~'RUBY')
      # The socket classes are constants once `require "socket"` runs, and a class
      # the compiler recognizes but has not implemented reports the missing METHOD
      # rather than a missing constant.
      require "socket"
      p TCPServer
      p TCPSocket
      p UDPSocket
      p BasicSocket
      p Socket
      p TCPServer.name
      p TCPServer.to_s

      r2 = (IPSocket.getaddress("127.0.0.1") rescue $!.class); p r2
      # a NAME resolves too, but to whichever family this host prefers
      p ["127.0.0.1", "::1"].include?(IPSocket.getaddress("localhost"))
      r3 = (TCPServer.bogus_xyz rescue $!.class); p r3
      r6 = (TCPServer.bogus_xyz rescue $!.message); p r6

      srv = TCPServer.new("127.0.0.1", 0)
      p srv.class
      srv.close

      # a genuinely undefined constant still reports the constant
      r4 = (Bogus123Xyz.new rescue $!.class); p r4
      r5 = (Bogus123Xyz.new rescue $!.message); p r5

      # `Socket::Constants` is a namespace of its own, holding the same names.
      # `sock_define_const` (ext/socket/constants.c) defines each one TWICE -- once
      # here, once on `Socket` -- so neither table is derived from the other, and the
      # module is included NOWHERE: a lookup through `Socket` never reaches it.
      # zr seeded only `Socket`, so `Socket::Constants` raised NameError; celluloid-io
      # aliases it (`Constants = ::Socket::Constants`) and never got past that line.
      p Socket::Constants.class
      p Socket::Constants.name
      p Socket.include?(Socket::Constants)
      p Socket::Constants.ancestors
      p Socket.const_defined?(:Constants)
      p Socket::Constants.const_defined?(:AF_UNIX)
      p Socket::Constants::AF_INET == Socket::AF_INET
      p Socket::Constants::SOCK_STREAM == Socket::SOCK_STREAM
      Aliased = ::Socket::Constants
      p Aliased::AF_INET6 == Socket::AF_INET6
    RUBY

    _(result).must_answer <<~'OUT'
      TCPServer
      TCPSocket
      UDPSocket
      BasicSocket
      Socket
      "TCPServer"
      "TCPServer"
      "127.0.0.1"
      true
      NoMethodError
      "undefined method 'bogus_xyz' for class TCPServer"
      TCPServer
      NameError
      "uninitialized constant Bogus123Xyz"
      Module
      "Socket::Constants"
      false
      [Socket::Constants]
      true
      true
      true
      true
      true
    OUT
  end

  it "the socket classes sit in ruby's chain, and a handle answers is_a? from it" do
    result = zr(<<~'RUBY')
      # The socket classes sit in CRuby's chain, and a handle answers #is_a? from it.
      require "socket"
      # first(5) stops before IO's own mixins: Spinel's IO does not carry
      # File::Constants / Enumerable yet, which is a separate gap.
      p TCPServer.ancestors.first(5)
      p TCPSocket.superclass
      p UDPSocket.superclass
      p UNIXServer.superclass
      p Socket.superclass
      p File.superclass
      p IO.superclass

      srv = TCPServer.new("127.0.0.1", 0)
      p srv.is_a?(TCPServer)
      p srv.is_a?(TCPSocket)
      p srv.is_a?(IPSocket)
      p srv.is_a?(BasicSocket)
      p srv.is_a?(IO)
      p srv.is_a?(Object)
      p srv.is_a?(File)
      p srv.is_a?(String)
      p srv.kind_of?(IO)
      p srv.instance_of?(TCPServer)
      p srv.instance_of?(IO)
      srv.close

      dir = "spinel_hier_test_dir"
      Dir.mkdir(dir) unless Dir.exist?(dir)
      path = File.join(dir, "s.txt")
      File.write(path, "x\n")
      f = File.open(path)
      p f.is_a?(File)
      p f.is_a?(IO)
      p f.is_a?(Object)
      p f.is_a?(BasicSocket)
      p f.instance_of?(File)
      p f.instance_of?(IO)
      f.close
      File.delete(path)
      Dir.rmdir(dir)
    RUBY

    _(result).must_answer <<~'OUT'
      [TCPServer, TCPSocket, IPSocket, BasicSocket, IO]
      IPSocket
      IPSocket
      UNIXSocket
      BasicSocket
      IO
      Object
      true
      true
      true
      true
      true
      true
      false
      false
      true
      true
      false
      true
      true
      true
      false
      true
      false
    OUT
  end

  it "const_defined?(:AF_INET6) folds the IPv6 fallback out on a platform that has it" do
    result = zr(<<~'RUBY')
      # `unless Socket.const_defined?(:AF_INET6)` drops an IPv6 fallback definition on
      # a platform that already defines it (the rubygems/ipaddr shape). zr folds the
      # guard at compile time against the seeded Socket constants.
      require "socket"

      unless Socket.const_defined?(:AF_INET6)
        raise "fallback should be dead code on an IPv6 platform"
      end

      puts Socket.const_defined?(:AF_INET6)
      puts Socket::AF_INET6 == Socket::AF_INET6
      puts Socket::SOCK_STREAM.class
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      Integer
    OUT
  end

  it "the SOL_, SO_, IPPROTO_ and SOCK_ constants are Integers a setsockopt call takes" do
    result = zr(<<~'RUBY')
      require "socket"
      p(Socket::SOL_SOCKET.is_a?(Integer))
      p(Socket::SO_KEEPALIVE.is_a?(Integer))
      p(Socket::IPPROTO_TCP.is_a?(Integer))
      p(Socket::TCP_NODELAY.is_a?(Integer))
      p(Socket::SO_RCVTIMEO.is_a?(Integer))
      p(Socket::SO_SNDTIMEO.is_a?(Integer))
      p(Socket::IPPROTO_IPV6.is_a?(Integer))
      p(Socket::MSG_PEEK.is_a?(Integer))
      p(Socket::SOCK_RAW.is_a?(Integer))
      p(Socket::AF_UNSPEC == 0)

      srv = TCPServer.new("127.0.0.1", 0)
      port = srv.addr[1]
      cli = TCPSocket.new("127.0.0.1", port)
      cli.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1)
      p cli.getsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE).int != 0
      cli.close
      srv.close
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "eof? on a socket does not seek, so the rest of the stream is still readable" do
    result = zr(<<~'RUBY')
      # `eof?` on a SOCKET must not seek: after a partial read, ruby answers
      # false and the rest of the stream is readable. zr's eof? probe seeks
      # and raises Errno::ESPIPE -- the same root as
      # `a_pipe_read_to_eof_does_not_seek.rb`, found via Net::HTTP keep-alive
      # (the second request in one `Net::HTTP.start` dies on this). (Found by
      # the 2026-08-24 probe sweep.)
      require "socket"
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      t = Thread.new do
        c = server.accept
        c.write("abcd")
        c.close
      end
      client = TCPSocket.new("127.0.0.1", port)
      p client.read(2)
      p client.eof?
      p client.read
      client.close
      t.join
      server.close
    RUBY

    _(result).must_answer <<~'OUT'
      "ab"
      false
      "cd"
    OUT
  end

  it "a socket is unbuffered and answers addr, where a File is buffered and does not" do
    result = zr(<<~'RUBY')
      # A socket comes up with `sync` false here. ruby leaves a socket UNBUFFERED
      # (`sync == true`) and only buffers file handles, which is the distinction this
      # test is drawing.
      # The socket methods belong to the socket classes, not to every IO handle,
      # and a socket is sync = true where a file is buffered.
      require "socket"
      srv = TCPServer.new("127.0.0.1", 0)
      port = srv.addr[1]
      t = Thread.new { c = srv.accept; c.write("hi\n"); sleep 0.05; c.close }
      s = TCPSocket.new("127.0.0.1", port)
      p s.sync
      p s.gets
      p s.addr.class
      p s.peeraddr[0]
      s.close
      t.join
      srv.close

      dir = "spinel_sockkind_test_dir"
      Dir.mkdir(dir) unless Dir.exist?(dir)
      path = File.join(dir, "sample.txt")
      File.write(path, "hello\n")
      f = File.open(path)
      p f.sync
      r = (f.addr rescue $!.class); p r
      r1 = (f.addr rescue $!.message); p r1
      r2 = (f.peeraddr rescue $!.class); p r2
      r3 = (f.accept rescue $!.class); p r3
      f.close
      File.delete(path)
      Dir.rmdir(dir)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "hi\n"
      Array
      "AF_INET"
      false
      NoMethodError
      "undefined method 'addr' for an instance of File"
      NoMethodError
      NoMethodError
    OUT
  end

  it "UDP over IPv6 binds and carries, and the Socket class methods answer" do
    result = zr(<<~'RUBY')
      # UDP over IPv6, and the Socket class methods.
      require "socket"

      u = UDPSocket.new(Socket::AF_INET6)
      u.bind("::1", 0)
      p u.addr[0]
      port = u.addr[1]
      s = UDPSocket.new(Socket::AF_INET6)
      s.send("v6", 0, "::1", port)
      msg, from = u.recvfrom(16)
      p msg
      p from[0]
      s.close
      u.close

      w = UDPSocket.new           # still IPv4 by default
      w.bind("127.0.0.1", 0)
      p w.addr[0]
      w.close

      r = Socket.getaddrinfo("127.0.0.1", 80)
      p r.class
      p r[0][0]
      p r[0][1]
      p r[0][2]

      a, b = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
      p a.class
      p a.is_a?(BasicSocket)
      a.write("hey\n")
      a.flush
      p b.gets
      a.close
      b.close

      sk = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      p sk.class
      sk.close

      p Socket.gethostname.is_a?(String)
    RUBY

    _(result).must_answer <<~'OUT'
      "AF_INET6"
      "v6"
      "AF_INET6"
      "AF_INET"
      Array
      "AF_INET"
      80
      "127.0.0.1"
      Socket
      true
      "hey\n"
      Socket
      true
    OUT
  end

  it "the IO::WaitReadable family and the exception: false markers drive a non-blocking retry" do
    result = zr(<<~'RUBY')
      # `IO::WaitReadable` does not exist, so the nonblocking-retry rescue arm cannot
      # resolve -- the same missing marker module as `exception_module_hierarchy`.
      # The non-blocking readiness family: the IO::*Wait* exceptions, the
      # `exception: false` markers, and the retry loop they exist for. Everything here
      # is deterministic -- no cross-thread timing.
      require "socket"

      srv = TCPServer.new("127.0.0.1", 0)
      begin
        srv.accept_nonblock
      rescue IO::WaitReadable => e
        p ["WaitReadable", e.class]
        p e.is_a?(Errno::EAGAIN)
        p e.is_a?(SystemCallError)
      end
      p srv.accept_nonblock(exception: false)
      srv.close

      r, w = IO.pipe
      p r.read_nonblock(4, exception: false)
      begin
        r.read_nonblock(4)
      rescue IO::WaitReadable => e
        p e.class
      end
      w.write("hi")
      w.flush
      p r.read_nonblock(4)
      p w.write_nonblock("more")

      # the retry idiom, with the data already in flight so the loop terminates
      w.write("second")
      w.flush
      buf = nil
      20.times do
        begin
          buf = r.read_nonblock(16)
          break
        rescue IO::WaitReadable
          IO.select([r], nil, nil, 0.05)
        end
      end
      p buf

      # a blocking read still works after a non-blocking one on the same handle
      w.write("line\n")
      w.flush
      p r.gets
      r.close
      w.close

      # a nil handle names NilClass
      r2, w2 = IO.pipe
      p r2.wait_priority(0).nil?
      r2.close
      w2.close
    RUBY

    _(result).must_answer <<~'OUT'
      ["WaitReadable", IO::EAGAINWaitReadable]
      true
      true
      :wait_readable
      :wait_readable
      IO::EAGAINWaitReadable
      "hi"
      4
      "moresecond"
      "line\n"
      true
    OUT
  end

  it "readpartial returns as soon as any bytes arrive, so a read-then-write server holds" do
    result = zr(<<~'RUBY')
      # IO#readpartial returns as soon as ANY bytes are available. It used to be one
      # fread of the full length, which is a different operation: fread keeps calling
      # read(2) until it has the whole request or hits EOF. On a socket that waits for
      # the peer to send that much or close, so the read-then-write shape every HTTP
      # server has deadlocks -- and where libc returns short instead of blocking, the
      # response was written to a connection the peer had already closed.
      require "socket"

      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]

      t = Thread.new do
        c = server.accept
        req = c.readpartial(4096)          # far more than the peer will send
        c.write("HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok")
        c.close
        req.bytesize
      end

      s = TCPSocket.new("127.0.0.1", port)
      s.write("GET / HTTP/1.0\r\n\r\n")
      body = s.read
      s.close
      puts t.value
      puts body.to_s.bytesize
      puts body.to_s.include?("ok")
      server.close

      # stdio's buffer comes first: a #gets before a #readpartial must not lose the
      # bytes stdio has already pulled off the socket.
      srv2 = TCPServer.new("127.0.0.1", 0)
      p2 = srv2.addr[1]
      t2 = Thread.new do
        c = srv2.accept
        line = c.gets                      # pulls the whole payload into the buffer
        rest = c.readpartial(64)           # must come from the buffer, not read(2)
        c.close
        "#{line.strip}|#{rest}"
      end
      c2 = TCPSocket.new("127.0.0.1", p2)
      c2.write("first\r\nsecond")
      c2.close
      puts t2.value
      srv2.close
    RUBY

    _(result).must_answer <<~'OUT'
      18
      40
      true
      first|second
    OUT
  end

  it "the socket classes are not constants before the socket library is required" do
    result = zr(<<~'RUBY')
      r = (TCPServer.new("127.0.0.1", 0) rescue $!.class)
      p r
      r2 = (TCPSocket.new("127.0.0.1", 1) rescue $!.class)
      p r2
    RUBY

    _(result).must_answer "NameError\nNameError\n"
  end

  it "a TCP pair carries bytes both ways through gets, puts, print and read" do
    result = zr(<<~'RUBY')
      require "socket"
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      p port > 0
      p server.class
      c = TCPSocket.new("127.0.0.1", port)
      s = server.accept
      p s.class, c.class
      s.write "hello\n"
      p c.gets
      c.puts "back"
      p s.gets
      s.print "no-newline"
      s.close
      p c.read
      c.close
      server.close
      p :done
    RUBY

    _(result).must_answer <<~'OUT'
      true
      TCPServer
      TCPSocket
      TCPSocket
      "hello\n"
      "back\n"
      "no-newline"
      :done
    OUT
  end

  it "a TCP server in a thread reads a request and writes a response the client reads" do
    result = zr(<<~'RUBY')
      require "socket"
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      t = Thread.new do
        client = server.accept
        req = client.gets
        client.write "HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok"
        client.close
        req
      end
      sock = TCPSocket.new("127.0.0.1", port)
      sock.write "GET / HTTP/1.0\r\n\r\n"
      p sock.gets
      body = sock.read
      p body.include?("ok")
      sock.close
      p t.value
      server.close
    RUBY

    _(result).must_answer <<~'OUT'
      "HTTP/1.0 200 OK\r\n"
      true
      "GET / HTTP/1.0\r\n"
    OUT
  end

  it "a datagram socket binds a port, and recvfrom answers the payload with the sender's address" do
    result = zr(<<~'RUBY')
      # UDPSocket over loopback. A datagram socket binds a local port, another
      # connects to it and writes; recvfrom answers the payload plus the sender's
      # [family, port, host, ip] array. (Data is written with IO#write rather than
      # UDPSocket#send, which zr's `send` intrinsic shadows for untyped receivers --
      # see tests/gaps/socket_send.rb.) Ports are kernel-assigned, so only their shape
      # is asserted.
      require "socket"

      recv = UDPSocket.new
      recv.bind("127.0.0.1", 0)
      addr = recv.addr
      p addr[0]
      p addr[1] > 0
      p addr[2]

      port = recv.addr[1]
      send = UDPSocket.new
      send.connect("127.0.0.1", port)
      send.write("datagram")

      msg, from = recv.recvfrom(16)
      p msg
      p from[0]
      p from[3]
      p from[1] > 0

      recv.close
      send.close
      p :done
    RUBY

    _(result).must_answer <<~'OUT'
      "AF_INET"
      true
      "127.0.0.1"
      "datagram"
      "AF_INET"
      "127.0.0.1"
      true
      :done
    OUT
  end

  it "a connected UDP socket, a UNIX-domain pair and the socket options answer together" do
    result = zr(<<~'RUBY')
      # `BasicSocket#getsockopt` answers a `Socket::Option` object, which is not
      # implemented -- line 52 raises NotImplementedError.
      # UDPSocket, the UNIX-domain pair, and the socket-option family.
      require "socket"

      # --- UDP ---
      u = UDPSocket.new
      p u.class
      p u.is_a?(IPSocket)
      u.bind("127.0.0.1", 0)
      port = u.addr[1]
      s = UDPSocket.new
      s.send("ping", 0, "127.0.0.1", port)
      msg, from = u.recvfrom(16)
      p msg
      p from[0]
      p from[2]
      s.close
      u.close

      # a connected UDP socket needs no address on send
      a = UDPSocket.new
      a.bind("127.0.0.1", 0)
      aport = a.addr[1]
      b = UDPSocket.new
      b.connect("127.0.0.1", aport)
      b.send("pong", 0)
      p a.recv(16)
      b.close
      a.close

      # --- UNIX domain ---
      path = "spinel_ux_suite.sock"
      File.delete(path) if File.exist?(path)
      srv = UNIXServer.new(path)
      p srv.class
      p srv.is_a?(BasicSocket)
      t = Thread.new { c = srv.accept; c.write("hi\n"); sleep 0.05; c.close }
      us = UNIXSocket.new(path)
      p us.class
      p us.gets
      us.close
      t.join
      srv.close
      File.delete(path)

      # --- options and constants ---
      p Socket::SOL_SOCKET.class
      # print no raw AF_/SOCK_ values: they differ by platform
      p Socket::AF_INET.is_a?(Integer)
      p Socket::SOCK_DGRAM != Socket::SOCK_STREAM
      srv2 = TCPServer.new("127.0.0.1", 0)
      p srv2.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1)
      p srv2.getsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE).int != 0
      srv2.close
      r = (Socket::BOGUS_XYZ rescue $!.class); p r
    RUBY

    _(result).must_answer <<~'OUT'
      UDPSocket
      true
      "ping"
      "AF_INET"
      "127.0.0.1"
      "pong"
      UNIXServer
      true
      UNIXSocket
      "hi\n"
      Integer
      true
      true
      0
      true
      NameError
    OUT
  end

  it "UNIXServer binds a path, accept mints a connected socket, and addr reports AF_UNIX" do
    result = zr(<<~'RUBY')
      # UNIXServer / UNIXSocket over a filesystem socket. The server binds+listens on
      # a path, a client connects, and #accept mints a connected UNIXSocket; bytes flow
      # both ways over the IO surface, and #addr/#path report the AF_UNIX endpoints.
      # The path embeds the pid so parallel runs don't collide; it's never printed
      # (only compared), so the golden stays deterministic.
      require "socket"

      path = "/tmp/zr_unix_test_#{Process.pid}.sock"
      File.unlink(path) if File.exist?(path)

      server = UNIXServer.new(path)
      p server.addr[0]
      p server.addr[1] == path

      client = UNIXSocket.new(path)
      conn = server.accept

      client.write("unix-hello")
      p conn.recv(10)

      conn.write("reply!")
      p client.read(6)

      p conn.peeraddr[0]
      p client.path == path

      client.close
      conn.close
      server.close
      File.unlink(path)
      p :done
    RUBY

    _(result).must_answer <<~'OUT'
      "AF_UNIX"
      true
      "unix-hello"
      "reply!"
      "AF_UNIX"
      false
      :done
    OUT
  end
end
