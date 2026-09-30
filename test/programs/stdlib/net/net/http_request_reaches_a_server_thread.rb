# Net::HTTP talks to a TCPServer in a thread of the same program: each
# side parks on its socket, and the scheduler polls every parked socket
# while no thread can run.
require "socket"
require "net/http"
server = TCPServer.new("127.0.0.1", 0)
port = server.addr[1]
t = Thread.new do
  2.times do
    c = server.accept
    req = +""
    while (line = c.gets) && line != "\r\n"
      req << line
    end
    body = "hello #{req.lines.first.split[1]}"
    c.write "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    c.close
  end
end
p Net::HTTP.get(URI("http://127.0.0.1:#{port}/a"))
res = Net::HTTP.start("127.0.0.1", port) { |h| h.get("/b") }
p res.code, res.body
t.join

