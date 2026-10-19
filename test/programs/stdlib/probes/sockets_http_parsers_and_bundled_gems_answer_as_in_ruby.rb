# A probe of many methods, each line one call and its answer or its error,
# compared with ruby's. The sockets and HTTP server are local.
def t(label)
  r = begin
    yield.inspect
  rescue Exception => e
    "#{e.class}: #{e.message}"
  end
  puts "#{label}: #{r}"
end

require "socket"; require "net/http"; require "strscan"; require "ripper"; require "prism"; require "etc"; require "pstore"; require "tmpdir"
require "matrix"; require "prime"; require "ostruct"; require "rdoc"; require "io/wait"; require "getoptlong"; require "resolv"; require "open-uri"
t("tcp") { s = TCPServer.new("127.0.0.1", 0); port = s.addr[1]; th = Thread.new { c = s.accept; l = c.gets; c.write("echo:#{l}"); c.close }; c = TCPSocket.new("127.0.0.1", port); c.puts "hi"; r = c.read; th.join; s.close; r }
t("unix") { Dir.mktmpdir { |d| path = File.join(d, "s"); srv = UNIXServer.new(path); th = Thread.new { a = srv.accept; a.write(a.read(3).upcase); a.close }; u = UNIXSocket.new(path); u.write("abc"); r = u.read; th.join; r } }
t("socketpair") { a, b = UNIXSocket.pair; a.send("x", 0); b.recv(1) }
t("addrinfo") { ai = Addrinfo.tcp("127.0.0.1", 80); [ai.ip_address, ai.ip_port, ai.ipv4?, ai.inspect] }
t("http") { s = TCPServer.new("127.0.0.1", 0); port = s.addr[1]; th = Thread.new { c = s.accept; while (l = c.gets) && l != "\r\n"; end; c.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nX-A: b\r\nConnection: close\r\n\r\nok"); c.close }; res = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/p")); th.join; s.close; [res.code, res.body, res["x-a"], res.class] }
t("http post") { s = TCPServer.new("127.0.0.1", 0); port = s.addr[1]; got = nil; th = Thread.new { c = s.accept; h = []; while (l = c.gets) && l != "\r\n"; h << l; end; len = h.grep(/Content-Length/i).first.split(":").last.to_i; got = c.read(len); c.write("HTTP/1.1 201 Created\r\nContent-Length: 0\r\n\r\n"); c.close }; res = Net::HTTP.post_form(URI("http://127.0.0.1:#{port}/"), "a" => "1 2"); th.join; [res.code, got] }
t("strscan") { s = StringScanner.new("3.14 is pi"); [s.scan(/\d+/), s.scan(/\./), s.scan_until(/is/), s.pos, s.rest, s.check(/\s+/), s.matched, s.eos?, s.peek(2)] }
t("strscan named") { s = StringScanner.new("key=val"); s.scan(/(?<k>\w+)=(?<v>\w+)/); [s[:k], s[:v], s.named_captures, s.captures] }
t("ripper lex") { Ripper.lex("a = 1 # c").map { [_1[1], _1[2]] } }
t("ripper sexp") { Ripper.sexp("def f(x) = x + 1") }
t("prism") { r = Prism.parse("foo(1, bar: 2)"); [r.success?, r.value.statements.body.first.class, r.value.statements.body.first.name] }
t("prism err") { Prism.parse("def (").errors.map(&:message).first }
t("etc") { [Etc.getlogin.class, Etc.nprocessors.positive?, Etc.getpwuid.name.class, Etc.sysconf(Etc::SC_PAGESIZE).positive?] }
t("pstore") { Dir.mktmpdir { |d| ps = PStore.new(File.join(d, "s")); ps.transaction { ps[:a] = [1, 2] }; ps.transaction(true) { [ps[:a], ps.roots] } } }
t("matrix") { m = Matrix[[1, 2], [3, 4]]; [m.det, m.inverse, m * Vector[1, 1], m.transpose, m.rank, Matrix.identity(2)] }
t("prime") { [Prime.first(5), 97.prime?, 360.prime_division, Prime.each(20).to_a.last, Prime.int_from_prime_division([[2, 3]])] }
t("ostruct") { o = OpenStruct.new(a: 1); o.b = 2; o[:c] = 3; [o.to_h, o.respond_to?(:b), o.dig(:a), o.inspect, o == OpenStruct.new(a: 1, b: 2, c: 3)] }
t("rdoc markup") { RDoc::Markup::ToHtml.new(RDoc::Options.new).convert("= Title\n\n*bold* _em_ +code+\n\n* item") }
t("io wait") { r, w = IO.pipe; w.write("x"); [r.ready?.class, r.wait_readable(0).class, w.wait_writable(0).class] }
t("getoptlong") { ARGV.replace(%w[--name x -v rest]); o = GetoptLong.new(["--name", GetoptLong::REQUIRED_ARGUMENT], ["-v", GetoptLong::NO_ARGUMENT]); r = []; o.each { r << [_1, _2] }; r + [ARGV] }
t("resolv hosts") { Resolv::Hosts.new("/dev/null").getaddresses("localhost") }
t("open-uri file") { Dir.mktmpdir { |d| f = File.join(d, "x.txt"); File.write(f, "hey"); URI.open(f, &:read) } }
t("ipsocket") { Socket.getaddrinfo("127.0.0.1", 80, nil, :STREAM).first.values_at(0, 1, 3) }
