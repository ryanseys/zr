# frozen_string_literal: true

require "spec_helper"

describe "Socket programs" do
  it "addrinfo family predicates" do
    result = ze0(<<~'RUBY')
      # Addrinfo's family predicates compared their (heap) afname against a bare C
      # literal through sp_str_eq, which confirms a strcmp hit by comparing byte
      # lengths -- and taking a bare literal's length reads its out-of-bounds s[-1]
      # marker. Whatever byte precedes the literal in rodata decides: land on a
      # marker value and the predicate answers false for two equal names. The rodata
      # layout is the optimizer's choice, so the answer changed between -O0 and -O1.
      require "socket"

      v4 = Addrinfo.tcp("127.0.0.1", 80)
      puts "#{v4.ipv4?} #{v4.ipv6?} #{v4.unix?} #{v4.ip?}"

      v6 = Addrinfo.udp("::1", 53)
      puts "#{v6.ipv4?} #{v6.ipv6?} #{v6.unix?} #{v6.ip?}"

      un = Addrinfo.unix("/tmp/spinel_afp.sock")
      puts "#{un.ipv4?} #{un.ipv6?} #{un.unix?} #{un.ip?}"

      # through a handle's own address, not just the constructors
      srv = TCPServer.new("127.0.0.1", 0)
      la = srv.local_address
      puts "#{la.ipv4?} #{la.ipv6?} #{la.unix?} #{la.ip?}"
      srv.close
    RUBY

    _(result).must_answer <<~'OUT'
      true false false true
      false true false true
      false false true false
      true false false true
    OUT
  end

  it "builtin cls id distinct" do
    result = ze0(<<~'RUBY')
      # Three SP_BUILTIN_* cls_ids named two kinds each, because they are declared in
      # two headers that cannot see one another: Addrinfo shared STRBUF's -40 and so
      # answered String, Socket::Option shared OpenStruct's -41, and Enumerator
      # shared FOREIGN_PTR's -25 -- the one the collector deliberately does NOT
      # trace, so a boxed Enumerator was collected out from under itself (#4158).
      require "socket"

      ai = Addrinfo.tcp("127.0.0.1", 8080)
      p [ai][0].class

      s = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      p [s.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE)][0].class
      s.close

      held = [[1, 2, 3].each]
      GC.start
      p held[0].class
      p held[0].next
      p held[0].next
    RUBY

    _(result).must_answer <<~'OUT'
      Addrinfo
      Socket::Option
      Enumerator
      1
      2
    OUT
  end

  it "c half answers each method as ruby does" do
    result = ze0(<<~'RUBY')
      # ext/socket's C half is ruby over the kernel's calls. Each row is one
      # method of it, whose answer -- an inspect, an error's class and words,
      # the bytes of an address -- is the one socket.so gives.
      require "socket"
      def t(label)
        r = yield
        puts "#{label}: #{r.inspect}"
      rescue Exception => e
        puts "#{label}: #{e.class}: #{e.message}"
      end
      t("ai tcp") { Addrinfo.tcp("127.0.0.1", 80) }
      t("ai list") { Addrinfo.getaddrinfo("127.0.0.1", 80) }
      t("ai new arr") { Addrinfo.new(["AF_INET", 80, "localhost", "127.0.0.1"]) }
      t("ai new arr2") { Addrinfo.new(["AF_INET", 80, nil, "127.0.0.1"], :INET, :STREAM) }
      t("ai pf") { Addrinfo.new(Socket.sockaddr_in(80, "::1"), :INET) }
      t("ai short") { Addrinfo.new("ab") }
      t("ai short2") { Addrinfo.new("\x10\x02") }
      t("ai v4mapped") { Addrinfo.ip("::ffff:1.2.3.4").ipv6_to_ipv4 }
      t("ai marshal") { Marshal.load(Marshal.dump(Addrinfo.tcp("127.0.0.1", 80))) }
      t("ai marshal dump") { Addrinfo.tcp("127.0.0.1", 80).marshal_dump }
      t("ai unix rel") { Addrinfo.unix("rel path") }
      t("ai unknown proto") { Addrinfo.new(Socket.sockaddr_in(0, "127.0.0.1"), :INET, :STREAM, 99) }
      t("ai preds") { a = Addrinfo.ip("10.1.2.3"); [a.ipv4_private?, a.ipv4_loopback?, a.ipv6_linklocal?, Addrinfo.ip("fe80::1").ipv6_linklocal?, Addrinfo.ip("ff02::1").ipv6_mc_linklocal?] }
      t("ai ip_unpack") { Addrinfo.udp("::1", 53).ip_unpack }
      t("ai uninit") { Addrinfo.allocate.inspect }
      t("ai unix_path") { Addrinfo.unix("/tmp/x").unix_path }
      t("ai ivars") { Addrinfo.tcp("127.0.0.1", 80).instance_variables }
      t("ai getnameinfo") { Addrinfo.tcp("127.0.0.1", 80).getnameinfo(Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV) }
      t("ai family_addrinfo") { Addrinfo.tcp("127.0.0.1", 80).family_addrinfo("127.0.0.1", 81) }
      t("sock getaddrinfo bad") { Socket.getaddrinfo("no such host.invalid", 80) }
      t("resolution error code") { begin; Socket.getaddrinfo("no such host.invalid", 80); rescue SocketError => e; [e.class, e.respond_to?(:error_code) && e.error_code]; end }
      t("newline") { Socket.getaddrinfo("localhost\n", 80) }
      t("pack un") { Socket.sockaddr_un("/tmp/x").bytesize }
      t("unpack un") { Socket.unpack_sockaddr_un(Socket.sockaddr_un("/tmp/x")) }
      t("unpack in wrong") { Socket.unpack_sockaddr_in(Socket.sockaddr_un("/tmp/x")) }
      t("getnameinfo arr") { Socket.getnameinfo(["AF_INET", 80, "127.0.0.1"], Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV) }
      t("getnameinfo str") { Socket.getnameinfo(Socket.sockaddr_in(80, "127.0.0.1"), Socket::NI_NUMERICHOST) }
      t("getnameinfo bad") { Socket.getnameinfo(1) }
      t("servbyname") { [Socket.getservbyname("http"), Socket.getservbyname("domain", "udp"), Socket.getservbyname("0x10")] }
      t("servbyname bad") { Socket.getservbyname("nope-nope") }
      t("servbyport") { Socket.getservbyport(80) }
      t("servbyport bad") { Socket.getservbyport(70000) }
      t("option inspect") { [Socket::Option.linger(true, 5), Socket::Option.new(:INET, :SOCKET, :RCVTIMEO, [1, 5].pack("q<l<x4")), Socket::Option.new(:INET6, :IPV6, :JOIN_GROUP, [0xff02,0,0,0,0,0,0,1].pack("n8") + [1].pack("L")), Socket::Option.new(:INET, :IP, :ADD_MEMBERSHIP, [224,0,0,1,0,0,0,0].pack("C8")), Socket::Option.new(:INET, :SOCKET, :ERROR, [61].pack("i")), Socket::Option.new(:UNIX, 0, 1, "abc"), Socket::Option.new(:INET, :TCP, 999, "x"), Socket::Option.new(1234, 5, 6, "x")] }
      t("option vals") { o = Socket::Option.linger(3, 5); [o.linger, Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, true).bool, Socket::Option.byte(:INET, :SOCKET, :KEEPALIVE, 300).byte, o.unpack("ii"), o.family, o.level, o.optname] }
      t("option int size") { Socket::Option.linger(1, 2).int }
      t("option bad name") { Socket::Option.int(:INET, :SOCKET, :NOPE, 1) }
      t("option ivars") { Socket::Option.int(:INET, :SOCKET, :REUSEADDR, 1).instance_variables }
      t("anc") { [Socket::AncillaryData.int(:UNIX, :SOCKET, :RIGHTS, 3), Socket::AncillaryData.new(:INET, :IP, :RECVDSTADDR, [127,0,0,1].pack("C4")), Socket::AncillaryData.ip_pktinfo(Addrinfo.ip("127.0.0.1"), 1), Socket::AncillaryData.ipv6_pktinfo(Addrinfo.ip("::1"), 1)] }
      t("anc vals") { a = Socket::AncillaryData.ip_pktinfo(Addrinfo.ip("127.0.0.1"), 1); [a.ip_pktinfo, Socket::AncillaryData.ipv6_pktinfo(Addrinfo.ip("::1"), 1).ipv6_pktinfo, a.cmsg_is?(:IP, :PKTINFO)] }
      t("ifaddrs") { Socket.getifaddrs.select { |i| i.name == "lo0" }.first(2) }
      t("ip_address_list") { Socket.ip_address_list.select(&:ipv4_loopback?) }
      t("hostname") { Socket.gethostname == `hostname`.chomp }
      s = TCPServer.new("127.0.0.1", 0)
      port = s.addr[1]
      t("server addr") { s.addr.first(1) + [s.addr[2]] }
      t("server inspect") { s.inspect.sub(/\d+>\z/, "PORT>").sub(/fd \d+/, "fd N") }
      t("nonblock?") { s.nonblock? rescue :none }
      t("sync binmode") { [s.sync, s.binmode?, s.external_encoding] }
      c = TCPSocket.new("127.0.0.1", port)
      a = s.accept
      t("accepted class") { [a.class, a.remote_address.ip_address, c.peeraddr(:numeric)[3]] }
      c.write("hello\n")
      t("gets") { a.gets }
      a.send("xyz", 0)
      t("recv") { c.recv(10) }
      t("getsockopt") { c.getsockopt(:SOCKET, :TYPE) }
      t("setsockopt") { c.setsockopt(:TCP, :NODELAY, true); c.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY).bool }
      t("recv_nonblock") { c.recv_nonblock(10, exception: false) }
      t("recv_nonblock raise") { c.recv_nonblock(10) }
      a.close_write
      t("read eof") { c.read }
      t("shutdown bad") { c.shutdown(:NOPE) }
      c.close; a.close; s.close
      t("refused") { begin; TCPSocket.new("127.0.0.1", port); rescue SystemCallError => e; e.message.sub(/port \d+/, "port N"); end }
      t("closed addr") { s.addr }
      u1 = UDPSocket.new; u1.bind("127.0.0.1", 0)
      u2 = UDPSocket.new
      u2.send("dgram", 0, "127.0.0.1", u1.addr[1])
      t("udp recvfrom") { m, from = u1.recvfrom(10); [m, from[0], from[3]] }
      u2.connect("127.0.0.1", u1.addr[1]); u2.send("two", 0)
      t("udp recvfrom_nonblock") { u1.recvfrom_nonblock(10)[0] }
      u1.close; u2.close
      path = "/tmp/ze0-sock-#{$$}"
      shown = ->(text) { text.gsub(path, "PATH") }
      File.delete(path) if File.exist?(path)
      us = UNIXServer.new(path)
      uc = UNIXSocket.new(path)
      ua = us.accept
      t("unix addrs") { shown.call([us.path, uc.peeraddr, ua.addr, us.inspect].inspect) }
      r, w = IO.pipe
      uc.send_io(r)
      t("recv_io") { io = ua.recv_io; [io.class, io.fileno > 2] }
      w.write("through"); w.close
      uc.sendmsg("msg", 0, nil, Socket::AncillaryData.int(:UNIX, :SOCKET, :RIGHTS, 1))
      t("recvmsg") { m = ua.recvmsg(10, 0, nil); [m[0], m[1].class, m[3].class] rescue $! }
      t("pair") { Socket.pair(:UNIX, :STREAM).map(&:class) }
      t("unixpair block") { UNIXSocket.pair { |x, y| x.write("a"); y.read(1) } }
      uc.close; ua.close; us.close; File.delete(path)
      t("unix connect fail") { begin; UNIXSocket.new(path); rescue SystemCallError => e; shown.call(e.message); end }
      t("Socket.new") { so = Socket.new(:INET, :STREAM); so.bind(Addrinfo.tcp("127.0.0.1", 0)); so.listen(5); r = [so.local_address.ipv4?, so.getsockname.bytesize]; so.close; r }
      t("Socket.tcp") { srv = TCPServer.new("127.0.0.1", 0); th = Thread.new { srv.accept.tap { |x| x.write("hi"); x.close } }; r = Socket.tcp("127.0.0.1", srv.addr[1]) { |so| so.read }; th.join; srv.close; r }
      t("for_fd bad") { BasicSocket.for_fd(0) }
      t("dnrl") { [BasicSocket.do_not_reverse_lookup, TCPSocket.do_not_reverse_lookup] }
      t("new basic") { BasicSocket.new(1) }

    RUBY

    _(result).must_answer <<~'OUT'
      ai tcp: #<Addrinfo: 127.0.0.1:80 TCP>
      ai list: [#<Addrinfo: 127.0.0.1:80 TCP>, #<Addrinfo: 127.0.0.1:80 UDP>, #<Addrinfo: 127.0.0.1:80 SOCK_RAW>]
      ai new arr: #<Addrinfo: 127.0.0.1:80 (localhost)>
      ai new arr2: #<Addrinfo: 127.0.0.1:80 TCP>
      ai pf: #<Addrinfo: [::1]:80 PF_INET>
      ai short: #<Addrinfo: unknown address family 98>
      ai short2: #<Addrinfo: ?.?.?.?:? (2 bytes for 16 bytes sockaddr_in)>
      ai v4mapped: #<Addrinfo: 1.2.3.4>
      ai marshal: #<Addrinfo: 127.0.0.1:80 TCP>
      ai marshal dump: ["AF_INET", ["127.0.0.1", "80"], "PF_INET", "SOCK_STREAM", "IPPROTO_TCP", nil, nil]
      ai unix rel: #<Addrinfo: UNIX:72:65:6c:20:70:61:74:68 SOCK_STREAM>
      ai unknown proto: #<Addrinfo: 127.0.0.1 SOCK_STREAM UNKNOWN_PROTOCOL(99)>
      ai preds: [true, false, false, true, true]
      ai ip_unpack: ["::1", 53]
      ai uninit: TypeError: uninitialized socket address
      ai unix_path: "/tmp/x"
      ai ivars: []
      ai getnameinfo: ["127.0.0.1", "80"]
      ai family_addrinfo: #<Addrinfo: 127.0.0.1:81 TCP>
      sock getaddrinfo bad: Socket::ResolutionError: getaddrinfo: nodename nor servname provided, or not known
      resolution error code: [Socket::ResolutionError, 8]
      newline: SocketError: newline at the end of hostname
      pack un: 106
      unpack un: "/tmp/x"
      unpack in wrong: ArgumentError: not an AF_INET/AF_INET6 sockaddr
      getnameinfo arr: ["127.0.0.1", "80"]
      getnameinfo str: ["127.0.0.1", "http"]
      getnameinfo bad: TypeError: expecting String or Array
      servbyname: [80, 53, 16]
      servbyname bad: SocketError: no such service nope-nope/tcp
      servbyport: "http"
      servbyport bad: RangeError: integer 70000 too big to convert into `int16_t'
      option inspect: [#<Socket::Option: UNSPEC SOCKET LINGER on 5sec>, #<Socket::Option: INET SOCKET RCVTIMEO 1.000005sec>, #<Socket::Option: INET6 IPV6 JOIN_GROUP ff02::1 lo0>, #<Socket::Option: INET IP ADD_MEMBERSHIP 224.0.0.1 0.0.0.0>, #<Socket::Option: INET SOCKET ERROR Connection refused (61)>, #<Socket::Option: UNIX level:0 PEERCRED "abc">, #<Socket::Option: INET TCP optname:999 "x">, #<Socket::Option: family:1234 level:5 optname:6 "x">]
      option vals: [[3, 5], true, 44, [3, 5], 0, 65535, 128]
      option int size: TypeError: size differ.  expected as sizeof(int)=4 but 8
      option bad name: SocketError: unknown socket level option name: NOPE
      option ivars: []
      anc: [#<Socket::AncillaryData: UNIX SOCKET RIGHTS 3>, #<Socket::AncillaryData: INET IP RECVDSTADDR 127.0.0.1>, #<Socket::AncillaryData: INET IP PKTINFO 127.0.0.1 lo0 spec_dst:127.0.0.1>, #<Socket::AncillaryData: INET6 IPV6 PKTINFO ::1 lo0>]
      anc vals: [[#<Addrinfo: 127.0.0.1>, 1, #<Addrinfo: 127.0.0.1>], [#<Addrinfo: ::1>, 1], true]
      ifaddrs: [#<Socket::Ifaddr lo0 UP,LOOPBACK,RUNNING,MULTICAST LINK[lo0]>, #<Socket::Ifaddr lo0 UP,LOOPBACK,RUNNING,MULTICAST 127.0.0.1 netmask=255.?.?.? (5 bytes for 16 bytes sockaddr_in)>]
      ip_address_list: [#<Addrinfo: 127.0.0.1>, #<Addrinfo: 127.0.2.2>, #<Addrinfo: 127.0.2.3>]
      hostname: true
      server addr: ["AF_INET", "127.0.0.1"]
      server inspect: "#<TCPServer:fd N, AF_INET, 127.0.0.1, PORT>"
      nonblock?: :none
      sync binmode: [true, true, #<Encoding:BINARY (ASCII-8BIT)>]
      accepted class: [TCPSocket, "127.0.0.1", "127.0.0.1"]
      gets: "hello\n"
      recv: "xyz"
      getsockopt: #<Socket::Option: INET SOCKET TYPE SOCK_STREAM>
      setsockopt: true
      recv_nonblock: :wait_readable
      recv_nonblock raise: IO::EAGAINWaitReadable: Resource temporarily unavailable - recvfrom(2) would block
      read eof: ""
      shutdown bad: SocketError: unknown shutdown argument: NOPE
      refused: "Connection refused - connect(2) for \"127.0.0.1\" port N"
      closed addr: IOError: closed stream
      udp recvfrom: ["dgram", "AF_INET", "127.0.0.1"]
      udp recvfrom_nonblock: IO::EAGAINWaitReadable: Resource temporarily unavailable - recvfrom(2) would block
      unix addrs: "[\"PATH\", [\"AF_UNIX\", \"PATH\"], [\"AF_UNIX\", \"PATH\"], \"#<UNIXServer:PATH>\"]"
      recv_io: [IO, true]
      recvmsg: ["msg", Addrinfo, Socket::AncillaryData]
      pair: [Socket, Socket]
      unixpair block: "a"
      unix connect fail: "No such file or directory - connect(2) for PATH"
      Socket.new: [true, 16]
      Socket.tcp: "hi"
      for_fd bad: Errno::EBADF: Bad file descriptor - not a socket file descriptor
      dnrl: [true, true]
      new basic: NoMethodError: undefined method 'initialize' for an instance of BasicSocket
    OUT
  end

  it "closed tcp server raises ioerror and a dead port refuses connections" do
    result = ze0(<<~'RUBY')
      # Every operation on a closed server raises IOError "closed stream"
      # (close itself is idempotent), and connecting to the freed port
      # raises Errno::ECONNREFUSED.

      require "socket"
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      p server.closed?
      server.close
      server.close
      p server.closed?
      begin
        server.accept
      rescue IOError => e
        puts "accept: #{e.message}"
      end
      begin
        server.addr
      rescue IOError => e
        puts "addr: #{e.message}"
      end
      begin
        TCPSocket.new("127.0.0.1", port)
      rescue Errno::ECONNREFUSED
        puts "refused"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      accept: closed stream
      addr: closed stream
      refused
    OUT
  end

  it "connect nonblock sockaddr 1arg" do
    result = ze0(<<~'RUBY')
      require "socket"

      def sockaddr_in(port, host)
        [Socket::AF_INET, port].pack("vn") +
          host.split(".").map(&:to_i).pack("C4") + ("\x00" * 8)
      end

      s1 = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      refused =
        begin
          s1.connect_nonblock(sockaddr_in(1, "127.0.0.1"))
        rescue => e
          e.class
        end
      p refused
      s1.close

      srv = TCPServer.new("127.0.0.1", 0)
      port = srv.addr[1]
      t = Thread.new { srv.accept }
      s2 = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      default =
        begin
          s2.connect_nonblock(sockaddr_in(port, "127.0.0.1"))
          :ok
        rescue IO::WaitWritable
          :wait_writable
        end
      p default
      IO.select(nil, [s2], nil, 5)
      second =
        begin
          s2.connect_nonblock(sockaddr_in(port, "127.0.0.1"))
          :connected
        rescue Errno::EISCONN
          :connected
        end
      p second
      t.value.close rescue nil
      srv.close
      s2.close

      srv2 = TCPServer.new("127.0.0.1", 0)
      port2 = srv2.addr[1]
      t2 = Thread.new { srv2.accept }
      s3 = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      flag = s3.connect_nonblock(sockaddr_in(port2, "127.0.0.1"), exception: false)
      p flag
      IO.select(nil, [s3])
      again = s3.connect_nonblock(sockaddr_in(port2, "127.0.0.1"), exception: false)
      p again
      t2.value.close rescue nil
      srv2.close
      s3.close
    RUBY

    _(result).must_answer <<~'OUT'
      IO::EINPROGRESSWaitWritable
      :wait_writable
      :connected
      :wait_writable
      0
    OUT
  end

  it "eof on a non seekable descriptor" do
    result = ze0(<<~'RUBY')
      # `eof?` on a PIPE or SOCKET peeks one byte instead of seeking.
      #
      # The old implementation probed end-of-file with `pos` + `seek(End)` + seek
      # back, which is `ESPIPE` on anything that cannot seek -- so `eof?` raised
      # for every pipe and socket, and Net::HTTP keep-alive died on the second
      # request in one `start`.
      #
      # A peek COSTS a byte, so the byte has to go somewhere every reader looks.
      # That is the whole design: it is parked in the read-ahead buffer and served
      # by one funnel, so `read`, `read(n)`, `getbyte` and `each_codepoint` all see
      # it. Two traps came with it, and both are rows here:
      #
      #   * the buffer is given back by seeking BACKWARD before an unbuffered row
      #     runs -- which a non-seekable descriptor cannot do, so it keeps its
      #     bytes rather than dropping them (dropping consumed the peek and handed
      #     the next reader the byte AFTER it);
      #   * `BasicSocket#recv` goes straight to the descriptor and cannot see the
      #     buffer at all, so it REFUSES, which is what ruby does.

      require "socket"

      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end

      # --- A pipe ---------------------------------------------------------------
      r, w = IO.pipe
      w.write("abcd")
      w.close
      show { r.read(2) }
      show { r.eof? }
      show { r.read(1) }
      show { r.getbyte }
      show { r.read }
      show { r.eof? }
      r.close

      # Reading a pipe to the end, which is what the seek probe used to raise on.
      r2, w2 = IO.pipe
      w2.write("hello")
      w2.close
      show { r2.read }
      show { r2.eof? }
      r2.close

      # An empty pipe is at end as soon as the writer closes.
      r3, w3 = IO.pipe
      w3.close
      show { r3.eof? }
      show { r3.read }
      r3.close

      # --- A socket -------------------------------------------------------------
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      t = Thread.new do
        c = server.accept
        c.write("abcdef")
        c.close
      end
      client = TCPSocket.new("127.0.0.1", port)
      show { client.read(2) }
      show { client.eof? }
      # `recv` cannot see the peeked byte, so it refuses rather than skipping it.
      show { client.recv(2) }
      show { client.read }
      show { client.eof? }
      client.close
      t.join
      server.close

      # --- A regular file keeps the exact position probe ------------------------
      require "tmpdir"
      Dir.mktmpdir do |dir|
        path = File.join(dir, "f")
        File.write(path, "abcd")
        File.open(path) do |f|
          show { f.eof? }
          show { f.read(2) }
          show { f.eof? }
          show { f.read }
          show { f.eof? }
          show { f.pos }
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "ab"
      false
      "c"
      100
      ""
      true
      "hello"
      true
      true
      ""
      "ab"
      false
      IOError: recv for buffered IO
      "cdef"
      true
      false
      "ab"
      false
      "cd"
      true
      4
    OUT
  end

  it "exception module hierarchy" do
    result = ze0(<<~'RUBY')
      # `IO::WaitReadable` -- and the `IO::EAGAINWaitReadable` / `EWOULDBLOCK` classes
      # built on it -- does not exist here, so every rescue arm that matches on the
      # marker module fails to resolve. ruby mixes those modules into the Errno
      # classes so a nonblocking read can be caught by protocol rather than by errno.
      # Ruby's exception hierarchy is not a chain: a class can include modules, and
      # `rescue M` / `#is_a?(M)` must agree about them.
      module Retryable; end
      class NetGlitch < StandardError
        include Retryable
      end
      begin
        raise NetGlitch, "x"
      rescue Retryable
        puts "rescued via module"
      rescue => e
        p ["fell through", e.class]
      end
      begin
        raise NetGlitch, "x"
      rescue => e
        p e.is_a?(Retryable)
        p e.is_a?(NetGlitch)
        p e.is_a?(StandardError)
      end
      p NetGlitch.ancestors.first(4)

      # the readiness family: an Errno subclass that also includes a module, with the
      # module reached from two different Errno parents
      require "socket"
      begin
        raise IO::EAGAINWaitReadable, "x"
      rescue IO::WaitReadable => e
        p ["module", e.class]
      end
      begin
        raise IO::EAGAINWaitReadable, "x"
      rescue Errno::EAGAIN
        p "errno"
      end
      begin
        raise IO::EAGAINWaitReadable, "x"
      rescue SystemCallError
        p "syscall"
      end
      begin
        raise IO::EAGAINWaitReadable, "x"
      rescue => e
        p e.is_a?(IO::WaitReadable)
        p e.is_a?(Errno::EAGAIN)
        p e.is_a?(SystemCallError)
        p e.is_a?(IO::WaitWritable)
      end
      begin
        raise IO::EINPROGRESSWaitWritable, "y"
      rescue IO::WaitWritable => e
        p ["w", e.class]
      end
      # Errno::EWOULDBLOCK IS Errno::EAGAIN in CRuby
      begin
        raise Errno::EAGAIN, "z"
      rescue Errno::EWOULDBLOCK
        p "EWOULDBLOCK catches EAGAIN"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      rescued via module
      true
      true
      true
      [NetGlitch, Retryable, StandardError, Exception]
      ["module", IO::EAGAINWaitReadable]
      "errno"
      "syscall"
      true
      true
      true
      false
      ["w", IO::EINPROGRESSWaitWritable]
      "EWOULDBLOCK catches EAGAIN"
    OUT
  end

  it "gem s ruby half runs over the c half" do
    result = ze0(<<~'RUBY')
      # lib/socket.rb, as the gem ships it, over the C half: servers and
      # clients of each family, the non-blocking calls, and a descriptor sent
      # through a unix socket.
      require "socket"
      def t(label)
        r = yield
        puts "#{label}: #{r.inspect}"
      rescue Exception => e
        puts "#{label}: #{e.class}: #{e.message}"
      end
      t("tcp_server_sockets") { socks = Socket.tcp_server_sockets("127.0.0.1", 0); r = socks.map { |s| [s.class, s.local_address.ipv4?] }; socks.each(&:close); r }
      t("udp_server_sockets") { socks = Socket.udp_server_sockets("127.0.0.1", 0); r = socks.map(&:class); socks.each(&:close); r }
      t("addrinfo bind/connect") do
        srv = Addrinfo.tcp("127.0.0.1", 0).listen
        port = srv.local_address.ip_port
        cl = Addrinfo.tcp("127.0.0.1", port).connect
        peer, peer_ai = srv.accept
        cl.write("x"); r = [peer.read(1), peer_ai.ipv4?, peer.class]
        [cl, peer, srv].each(&:close)
        r
      end
      t("nonblock connect/accept") do
        srv = Socket.new(:INET, :STREAM); srv.bind(Addrinfo.tcp("127.0.0.1", 0)); srv.listen(5)
        cl = Socket.new(:INET, :STREAM)
        st = cl.connect_nonblock(srv.local_address, exception: false)
        IO.select(nil, [cl], nil, 5)
        acc = srv.accept_nonblock(exception: false)
        acc = (IO.select([srv], nil, nil, 5); srv.accept_nonblock) if acc == :wait_readable
        r = [st, acc.class, acc[1].class, cl.connect_nonblock(srv.local_address, exception: false)]
        [cl, acc[0], srv].each(&:close)
        r
      end
      t("accept_nonblock empty") { srv = TCPServer.new("127.0.0.1", 0); r = [srv.accept_nonblock(exception: false)]; begin; srv.accept_nonblock; rescue IO::WaitReadable => e; r << e.class << e.message; end; srv.close; r }
      t("sendmsg/recvmsg rights") do
        a, b = UNIXSocket.pair
        r, w = IO.pipe
        a.sendmsg("hey", 0, nil, Socket::AncillaryData.unix_rights(r))
        msg, from, flags, ctl = b.recvmsg(:scm_rights => true)
        io = ctl.unix_rights[0]
        w.write("pipe"); w.close
        res = [msg, from.inspect, flags, ctl.inspect.sub(/\d+>\z/, "N>"), io.class, io.read]
        [a, b, r].each(&:close)
        res
      end
      t("recvmsg nonblock") { a, b = UNIXSocket.pair; r = b.recvmsg_nonblock(exception: false); a.write("q"); r2 = b.recvmsg_nonblock(10); [a, b].each(&:close); [r, r2[0]] }
      t("recvfrom unix") { a, b = UNIXSocket.pair; a.write("u"); r = b.recvfrom(5); [a, b].each(&:close); r }
      t("socket recvfrom") { a, b = Socket.pair(:UNIX, :DGRAM); a.send("d", 0); r = b.recvfrom(5); [a, b].each(&:close); [r[0], r[1].class, r[1].inspect] }
      t("unix_server_socket") { path = "/tmp/ze0-us-#{$$}"; r = Socket.unix_server_socket(path) { |s| [s.class, s.local_address.unix_path == path] }; File.exist?(path) && File.delete(path); r }
      t("Socket.unix") do
        path = "/tmp/ze0-u2-#{$$}"
        srv = UNIXServer.new(path)
        th = Thread.new { c = srv.accept; c.write("ok"); c.close }
        r = Socket.unix(path) { |s| s.read }
        th.join; srv.close; File.delete(path)
        r
      end
      t("ipv6 loop") { srv = TCPServer.new("::1", 0); c = TCPSocket.new("::1", srv.addr[1]); a = srv.accept; r = [srv.addr[0], a.peeraddr[3], c.remote_address.inspect.sub(/\d+ TCP/, "P TCP")]; [c, a, srv].each(&:close); r }
      t("udp connect send") { u = UDPSocket.new(:INET6); u.bind("::1", 0); v = UDPSocket.new(Socket::AF_INET6); v.connect("::1", u.addr[1]); v.send("six", 0); r = u.recvfrom(10); [u, v].each(&:close); [r[0], r[1][0]] }
      t("getpeereid") { a, b = UNIXSocket.pair; r = a.getpeereid == [Process.euid, Process.egid]; [a, b].each(&:close); r }
      t("local peercred") { a, b = UNIXSocket.pair; o = a.getsockopt(0, Socket::LOCAL_PEERCRED); [a, b].each(&:close); o.inspect.sub(/euid=\d+.*\(/, "euid=N (") }
      t("so_error inspect") { s = Socket.new(:INET, :STREAM); o = s.getsockopt(:SOCKET, :ERROR); s.close; o.inspect }
      t("getsockopt rcvbuf") { s = Socket.new(:INET, :DGRAM); o = s.getsockopt(:SOCKET, :RCVBUF); s.close; [o.int > 0, o.inspect.sub(/\d+>/, "N>")] }
      t("closed ops") { s = Socket.new(:INET, :STREAM); s.close; s.getsockname }
      t("instance vars") { s = Socket.new(:INET, :STREAM); r = s.instance_variables; s.close; r }
      t("ip_address_list") { Socket.ip_address_list.map(&:afamily).uniq.sort }
      t("tcp timeout") { srv = TCPServer.new("127.0.0.1", 0); s = Socket.tcp("127.0.0.1", srv.addr[1], connect_timeout: 1); r = s.remote_address.ip_port == srv.addr[1]; [s, srv].each(&:close); r }
      t("tcpserver port only") { s = TCPServer.new(0); r = s.addr[0]; s.close; r }

    RUBY

    _(result).must_answer <<~'OUT'
      tcp_server_sockets: [[Socket, true]]
      udp_server_sockets: [Socket]
      addrinfo bind/connect: ["x", true, Socket]
      nonblock connect/accept: [:wait_writable, Array, Addrinfo, 0]
      accept_nonblock empty: [:wait_readable, IO::EAGAINWaitReadable, "Resource temporarily unavailable - accept(2) would block"]
      sendmsg/recvmsg rights: ["hey", "#<Addrinfo: empty-sockaddr SOCK_STREAM>", 0, "#<Socket::AncillaryData: UNIX SOCKET RIGHTS N>", IO, "pipe"]
      recvmsg nonblock: [:wait_readable, "q"]
      recvfrom unix: ["u", ["AF_UNIX", ""]]
      socket recvfrom: ["d", Addrinfo, "#<Addrinfo: empty-path-AF_UNIX-sockaddr SOCK_DGRAM>"]
      unix_server_socket: [Socket, true]
      Socket.unix: "ok"
      ipv6 loop: ["AF_INET6", "::1", "#<Addrinfo: [::1]:P TCP>"]
      udp connect send: ["six", "AF_INET6"]
      getpeereid: true
      local peercred: "#<Socket::Option: UNIX level:0 PEERCRED version=0 euid=N (xucred)>"
      so_error inspect: "#<Socket::Option: INET SOCKET ERROR Undefined error: 0 (0)>"
      getsockopt rcvbuf: [true, "#<Socket::Option: INET SOCKET RCVBUF N>"]
      closed ops: IOError: closed stream
      instance vars: []
      ip_address_list: [2, 30]
      tcp timeout: true
      tcpserver port only: "AF_INET6"
    OUT
  end

  it "poly handle face" do
    result = ze0(<<~'RUBY')
      # A handle read out of a container arrives boxed, and the boxed value had no
      # method surface at all: every Addrinfo and Socket::Option reader raised
      # NoMethodError. Each of these names belongs to exactly one builtin handle
      # class and to no other class in the language, so the name alone identifies
      # the receiver -- the value is unboxed back to its own type and the handle's
      # typed emitter compiles against the real pointer. The runtime cls_id is
      # checked first, so a value of any other kind still raises (#4158 follow-up).
      require "socket"

      a = [Addrinfo.tcp("127.0.0.1", 8080)]
      p a[0].class
      p a[0].ip_port
      p a[0].ip_address
      p a[0].ipv4?
      p a[0].ipv6?
      p a[0].socktype == Socket::SOCK_STREAM

      s = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      o = [s.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE)]
      p o[0].class
      p o[0].int == Socket::SOCK_STREAM
      s.close

      # a value of another kind reaching one of these names still raises, naming
      # its own class -- the face never dereferences on the strength of the name
      begin
        [42][0].ip_port
      rescue NoMethodError
        puts "NoMethodError"
      end

      # and a user class that defines the name keeps it
      class Opt
        def level = "mine"
      end
      p [Opt.new][0].level
    RUBY

    _(result).must_answer <<~'OUT'
      Addrinfo
      8080
      "127.0.0.1"
      true
      false
      true
      Socket::Option
      true
      NoMethodError
      "mine"
    OUT
  end

  it "send shadowing" do
    result = ze0(<<~'RUBY')
      # `send` is not magic: it is an ordinary method on Kernel, so a class that
      # defines its own wins the lookup by sitting earlier in the ancestor chain --
      # and only Kernel's reinterprets its first argument as a method name.
      #
      # The interesting case is a receiver whose class the compiler cannot see. A
      # `send` there has to ask the chain at RUNTIME rather than assume Kernel's.

      require "socket"

      # --- a user class that defines `send` ----------------------------------------
      class Radio
        def send(message, urgency = 0) = "#{message}/#{urgency}"
        def beep = "beep"
      end

      # Through a typed local, and through one the compiler can't type.
      r = Radio.new
      p r.send("hi")
      p r.send("hi", 2)
      untyped, = [Radio.new]
      p untyped.send("hi", 3)
      p [Radio.new].first.send("bye")

      # A subclass inherits the shadow.
      class Walkie < Radio; end
      w, = [Walkie.new]
      p w.send("over")

      # --- BasicSocket#send: the same rule, from a builtin -------------------------
      # `a, b = UNIXSocket.pair` gives locals with no static type at all.
      a, b = UNIXSocket.pair
      p a.send("hello", 0)
      p b.recv(5)
      sock = a
      p sock.send("bye", 0)
      p b.recv(3)
      a.close
      b.close

      # --- Kernel#send still reinterprets, for everything that does NOT shadow -----
      class Plain
        def greet(who) = "hi #{who}"
        private def secret = "shh"
      end
      plain = Plain.new
      p plain.send(:greet, "ada")
      p plain.send("greet", "grace")
      p plain.send(:secret)
      mystery, = [Plain.new]
      p mystery.send(:greet, "ada")
      p mystery.send("secret")

      # Builtin receivers take the same path.
      p [3, 1, 2].send(:sort)
      p "abc".send(:upcase)
      p 5.send(:+, 6)
      list, = [[3, 1, 2]]
      p list.send(:sort)
      p list.send(:push, 9)

      # A block rides along.
      p [1, 2, 3].send(:map) { |x| x * 2 }
      nums, = [[1, 2, 3]]
      p nums.send(:select) { |x| x.odd? }

      # --- public_send is visibility-gated, shadow or not --------------------------
      p plain.public_send(:greet, "ada")
      begin
        plain.public_send(:secret)
      rescue NoMethodError => e
        puts e.message
      end
      begin
        mystery.public_send(:secret)
      rescue NoMethodError => e
        puts e.message
      end

      # A class defining `send` does NOT thereby define `public_send`.
      p r.public_send(:beep)
      p untyped.public_send(:beep)

      # --- __send__ always resolves through the chain ------------------------------
      p plain.__send__(:greet, "ada")
      p mystery.__send__(:greet, "grace")
      p r.__send__(:beep)
    RUBY

    _(result).must_answer <<~'OUT'
      "hi/0"
      "hi/2"
      "hi/3"
      "bye/0"
      "over/0"
      5
      "hello"
      3
      "bye"
      "hi ada"
      "hi grace"
      "shh"
      "hi ada"
      "shh"
      [1, 2, 3]
      "ABC"
      11
      [1, 2, 3]
      [3, 1, 2, 9]
      [2, 4, 6]
      [1, 3]
      "hi ada"
      private method 'secret' called for an instance of Plain
      private method 'secret' called for an instance of Plain
      "beep"
      "beep"
      "hi ada"
      "hi grace"
      "beep"
    OUT
  end

  it "socket binary write" do
    result = ze0(<<~'RUBY')
      # `TCPSocket#write_nonblock` is not implemented, so line 40 raises.
      require "socket"

      # A String carrying an embedded NUL must reach the peer whole: #bytesize
      # reports the header length, and the write has to use it rather than
      # stopping at the first NUL. The read side was already length-aware.
      payload = "AB\x00CD"

      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]

      t = Thread.new do
        conn = server.accept
        got = conn.read(5)
        conn.close
        got
      end

      sock = TCPSocket.new("127.0.0.1", port)
      wrote = sock.write(payload)
      sock.close

      got = t.value
      server.close

      p payload.bytesize
      p wrote
      p got.bytesize
      p got.bytes

      # #write_nonblock sizes its operand the same way.
      srv2 = TCPServer.new("127.0.0.1", 0)
      port2 = srv2.addr[1]
      t2 = Thread.new do
        conn = srv2.accept
        got2 = conn.read(5)
        conn.close
        got2
      end
      sock2 = TCPSocket.new("127.0.0.1", port2)
      wrote2 = sock2.write_nonblock(payload)
      sock2.close
      p wrote2
      p t2.value.bytesize
      srv2.close
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      5
      [65, 66, 0, 67, 68]
      5
      5
    OUT
  end

  it "socket pack sockaddr" do
    result = ze0(<<~'RUBY')
      # Socket.sockaddr_in and Addrinfo#to_sockaddr: the packed sockaddr String the
      # 1-argument connect_nonblock takes. Without them a caller had to build the
      # bytes by hand (`[Socket::AF_INET, port].pack('vn') + ...`), which only
      # happens to work for AF_INET on a little-endian host (#4137, after #4135).
      require "socket"

      sa = Socket.sockaddr_in(4567, "127.0.0.1")
      p sa.bytesize
      p Socket.unpack_sockaddr_in(sa)

      # pack_sockaddr_in is CRuby's documented alias, not a second implementation.
      p Socket.pack_sockaddr_in(4567, "127.0.0.1") == sa

      # An already-resolved endpoint packs to the same bytes -- which is the point:
      # the caller does not pay for the name lookup twice.
      ai = Addrinfo.tcp("127.0.0.1", 4567)
      p ai.to_sockaddr == sa
      p Socket.unpack_sockaddr_in(ai.to_sockaddr)

      # A zero port and a zero octet both put NUL inside the string, so the result
      # has to be a byte string rather than a C string.
      z = Socket.sockaddr_in(0, "0.0.0.0")
      p z.bytesize
      p Socket.unpack_sockaddr_in(z)

      # IPv6 packs to the longer sockaddr_in6, and unpacks back.
      v6 = Socket.sockaddr_in(80, "::1")
      p v6.bytesize
      p Socket.unpack_sockaddr_in(v6)

      # The round trip through a real connection, which is what the form is for.
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      addr = Addrinfo.tcp("127.0.0.1", port)
      sock = Socket.new(addr.afamily, Socket::SOCK_STREAM, 0)
      begin
        sock.connect_nonblock(addr.to_sockaddr)
      rescue IO::WaitWritable
        IO.select(nil, [sock])
        begin
          sock.connect_nonblock(addr.to_sockaddr)
        rescue Errno::EISCONN
        end
      end
      peer = server.accept
      sock.write("ping")
      p peer.readpartial(4)
      p Socket.unpack_sockaddr_in(addr.to_sockaddr)[0] == port
      sock.close
      peer.close
      server.close
    RUBY

    _(result).must_answer <<~'OUT'
      16
      [4567, "127.0.0.1"]
      true
      true
      [4567, "127.0.0.1"]
      16
      [0, "0.0.0.0"]
      28
      [80, "::1"]
      "ping"
      true
    OUT
  end

  it "socket send" do
    result = ze0(<<~'RUBY')
      # `BasicSocket#send` overrides `Kernel#send`: on a socket, `sock.send(data,
      # flags)` writes bytes to the peer and answers the count -- it does NOT invoke a
      # method named by `data`. zeo implements `BasicSocket#send`, but `send` is also a
      # compiler/runtime intrinsic that reinterprets its first argument as a method
      # name whenever the receiver's socket type isn't statically known (here `a` is an
      # untyped local from a multiple-assignment), so zeo raises NoMethodError instead
      # of sending. This is the same limitation as any redefined `#send` (cf. the
      # `Ractor#send` shadow-arm note in `codegen::call`): resolving it needs the
      # receiver typed as a `BasicSocket` descendant, which local-type tracking does
      # not yet propagate through `a, b = UNIXSocket.pair`.
      require "socket"

      a, b = UNIXSocket.pair
      n = a.send("hello", 0)
      puts n
      puts b.recv(5)
      a.close
      b.close
    RUBY

    _(result).must_answer "5\nhello\n"
  end

  it "systemcallerror hierarchy" do
    result = ze0(<<~'RUBY')
      # Every Errno::* is a SystemCallError, in `rescue` as well as in #is_a?.
      begin
        File.open("/nonexistent_spinel_xyz")
      rescue SystemCallError
        p "caught SystemCallError"
      rescue => e
        p ["other", e.class]
      end
      begin
        File.open("/nonexistent_spinel_xyz")
      rescue => e
        p e.class
        p e.is_a?(SystemCallError)
        p e.is_a?(StandardError)
        p e.is_a?(Errno::ENOENT)
        p e.is_a?(TypeError)
      end
      begin
        File.open("/nonexistent_spinel_xyz")
      rescue StandardError
        p "caught StandardError"
      end

      require "socket"
      r = (TCPSocket.new("127.0.0.1", 1) rescue $!.class); p r
      begin
        TCPSocket.new("127.0.0.1", 1)
      rescue SystemCallError
        p "socket error is a SystemCallError"
      end

      # a non-Errno error must NOT be swept up by SystemCallError
      begin
        raise TypeError, "x"
      rescue SystemCallError
        p "wrong"
      rescue TypeError
        p "TypeError stays a TypeError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "caught SystemCallError"
      Errno::ENOENT
      true
      true
      true
      false
      "caught StandardError"
      Errno::ECONNREFUSED
      "socket error is a SystemCallError"
      "TypeError stays a TypeError"
    OUT
  end

  it "tcp server addr shape listen and backlog queueing" do
    result = ze0(<<~'RUBY')
      # #addr is `[family, port, name, ip]` (numeric name -- CRuby's
      # do_not_reverse_lookup default); #listen on a bound listener is a
      # validated no-op answering 0; and two clients that connect BEFORE any
      # accept queue in the listen backlog and are handed out in order.

      require "socket"
      server = TCPServer.new("127.0.0.1", 0)
      addr = server.addr
      p addr[0]
      p addr[1] > 0
      p addr[2]
      p addr[3]
      p server.listen(5)
      c1 = TCPSocket.new("127.0.0.1", addr[1])
      c2 = TCPSocket.new("127.0.0.1", addr[1])
      c1.puts "first"
      c2.puts "second"
      s1 = server.accept
      p s1.gets
      s2 = server.accept
      p s2.gets
      [c1, c2, s1, s2].each(&:close)
      server.close
    RUBY

    _(result).must_answer <<~'OUT'
      "AF_INET"
      true
      "127.0.0.1"
      "127.0.0.1"
      0
      "first\n"
      "second\n"
    OUT
  end

  it "tcp server and socket round trip" do
    result = ze0(<<~'RUBY')
      # require "socket" activates TCPServer/TCPSocket. A single-threaded round
      # trip: connect first (queues in the listen backlog), accept, then exchange
      # bytes via the inherited IO surface (write/gets/read on TCPSocket < IO).

      require "socket"
      server = TCPServer.new("127.0.0.1", 0)
      p server.addr[1] > 0
      p server.class
      c = TCPSocket.new("127.0.0.1", server.addr[1])
      s = server.accept
      p s.class
      s.write "hello\n"
      p c.gets
      c.write "back\n"
      p s.gets
      s.print "tail"
      s.close
      p c.read
      c.close
      server.close
      p server.closed?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      TCPServer
      TCPSocket
      "hello\n"
      "back\n"
      "tail"
      true
    OUT
  end
end
