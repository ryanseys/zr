# Marshal.load from an object that reads takes single bytes with getbyte
# while it knows of no more bytes to come, and reads a known count with
# read, so it never reads past the value.
Input = Struct.new(:bytes, :used) do
  def initialize = super("\x04\x08[\x07".bytes, false)

  def getbyte = bytes.shift

  def read(_len, _outbuf = nil)
    return nil if used

    self.used = true
    "0" * (1024 * 128)
  end
end
p Marshal.load(Input.new)

IO.pipe do |r, w|
  w.write(Marshal.dump([1, "two", :three]) + Marshal.dump({ a: 1 }))
  w.close
  p Marshal.load(r)
  p Marshal.load(r)
end
