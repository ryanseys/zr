# IO#cursor writes its query in raw mode and reads the reply there, and
# IO.console hands its keywords to the method it sends; keywords alone
# stand where the Symbol goes, as console_dev reads them.
require "io/console"
require "pty"

m, s = PTY.open
replies = ["\e[12;34R", "\e[7R", "\e[3;4X", "\e[12;34;56R", "\e[;R", "\e[1;1R", "x"]
replies.each do |reply|
  th = Thread.new do
    query = m.readpartial(10)
    m.print(reply)
    m.flush
    query
  end
  p [s.cursor, th.value]
end
p s.echo?
begin
  IO.console(freeze: true)
rescue TypeError => e
  p [e.class, e.message]
end
begin
  IO.console("clone")
rescue TypeError => e
  p [e.class, e.message]
end
