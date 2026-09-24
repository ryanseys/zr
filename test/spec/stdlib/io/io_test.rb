# frozen_string_literal: true

require "spec_helper"

describe "IO: the io/wait and io/nonblock libraries" do
  it "nonblock? and nonblock= read and set the flag, and the block form restores it" do
    result = zr(<<~'RUBY')
      # `require "io/nonblock"` -- `IO#nonblock?`, `#nonblock=`, and the block form
      # that sets the flag only for its block. CRuby's reader form requires that
      # block, and its `IO.pipe` hands back fds already marked non-blocking.
      require "io/nonblock"
      r, w = IO.pipe
      p [r.nonblock?, w.nonblock?]
      r.nonblock = false
      p r.nonblock?
      p r.nonblock(true) { r.nonblock? }
      p r.nonblock?
      begin
        r.nonblock(true)
      rescue LocalJumpError => e
        p e.message
      end
      f = File.open("/etc/hosts")
      p f.nonblock?
      f.close
      r.close
      w.close

      # The flag lives on the DESCRIPTOR and changes nothing about what the ordinary
      # rows mean: `gets` still blocks for its line rather than surfacing the EAGAIN
      # an empty non-blocking pipe answers with.
      r2, w2 = IO.pipe
      reader = Thread.new { r2.gets }
      sleep 0.2
      w2.puts "hello"
      p reader.value
      r2.close
      w2.close

      # The write side of the same rule: 200KB overflows the kernel pipe buffer, so
      # the writer waits for the reader to make room.
      r3, w3 = IO.pipe
      writer = Thread.new { w3.write("x" * 200_000); w3.close; :done }
      p r3.read.bytesize
      p writer.value
      r3.close
    RUBY

    _(result).must_answer <<~'OUT'
      [true, true]
      false
      true
      false
      "no block given"
      false
      "hello\n"
      200000
      :done
    OUT
  end

  it "wait_readable and wait_writable poll the descriptor of each end of a pipe" do
    result = zr(<<~'RUBY')
      # `require "io/wait"` is a native no-op feature (like io/console): IO gains
      # `#wait_readable`/`#wait_writable`, real `poll(2)` over the fd. A pipe with
      # a byte buffered is readable; its write end is writable. net/protocol's
      # BufferedIO drives its read/write timeouts through exactly these.

      require "io/wait"
      r, w = IO.pipe
      w.write("x")
      puts(r.wait_readable(1) ? "readable" : "timeout")
      puts(w.wait_writable(1) ? "writable" : "timeout")
    RUBY

    _(result).must_answer "readable\nwritable\n"
  end
end
