# IO.select asks each stream whether it holds buffered bytes, through
# Kernel#send as CRuby's C would. A stream whose class defines its own
# `send`, as BasicSocket does for send(2), must not take that call:
# a Socket in IO.select raised "wrong number of arguments".
class Channel < IO
  def send(message, flags)
    raise "Channel#send(#{message.inspect}, #{flags})"
  end
end

reader, writer = Channel.pipe
writer.write("x")
ready = IO.select([reader], [writer], nil, 1)
p ready.map { |list| list.map(&:class) }
p reader.read_nonblock(1)
[reader, writer].each(&:close)

