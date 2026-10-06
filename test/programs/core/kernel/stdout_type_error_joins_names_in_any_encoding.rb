# The error for a $stdout without `write` joins the global's name and the
# class's name as rb_sprintf does: a name in an encoding that the
# message cannot take is converted into the message's encoding.
alias $標準出力 $stdout
x = eval("class Xほげ; self; end".encode("euc-jp"))
begin
  $標準出力 = x.new
rescue TypeError => e
  p e.message, e.message.encoding
end
begin
  $stdout = x.new
rescue TypeError => e
  p e.message.encoding, e.message.bytes.size
end
[[:$>, 1], [:$stderr, Object.new]].each do |name, value|
  eval("#{name} = value")
rescue TypeError => e
  p e.message
end
p $stdout.equal?(STDOUT)
