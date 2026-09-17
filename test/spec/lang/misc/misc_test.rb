# frozen_string_literal: true

require "spec_helper"

describe "Misc programs" do
  it "sp net poll persistent" do
    _(ze0(<<~'RUBY', path: "lang/misc/sp_net_poll_persistent.rb")).must_answer "", stderr: "lang/misc/sp_net_poll_persistent.rb:10:in '<module:Net>': undefined method 'ffi_func' for module Net (NoMethodError)\n\n  ffi_func :sp_net_poll_register,   [:int, :int], :int\n  ^^^^^^^^\n\tfrom lang/misc/sp_net_poll_persistent.rb:9:in '<main>'\n", status: 1
      # Persistent registration: register once per connection, then read only what
      # fired. The older reset/add/run/ready contract rebuilds the set every tick, so
      # a caller with N parked fds does O(N) work per tick however few are ready;
      # these cost O(events) instead. (matz/spinel#4103)
      #
      # fd 1 is this process's stdout: always open and always write-ready, whether it
      # is a file or a pipe with room, so the readiness assertion below holds on any
      # POSIX target without binding a port.
      module Net
        ffi_func :sp_net_poll_register,   [:int, :int], :int
        ffi_func :sp_net_poll_modify,     [:int, :int], :int
        ffi_func :sp_net_poll_unregister, [:int],       :int
        ffi_func :sp_net_poll_registered, [],           :int
        ffi_func :sp_net_poll_wait,       [:int],       :int
        ffi_func :sp_net_poll_event_fd,   [:int],       :int
        ffi_func :sp_net_poll_event_mode, [:int],       :int
      end

      # Registering keys on the fd: twice is once.
      puts "register: #{Net.sp_net_poll_register(1, 2)}"
      puts "again: #{Net.sp_net_poll_register(1, 2)}"
      puts "registered: #{Net.sp_net_poll_registered}"

      # stdout is write-ready, and the event names the fd and the mode.
      n = Net.sp_net_poll_wait(0)
      puts "ready: #{n}"
      puts "event fd: #{Net.sp_net_poll_event_fd(0)}"
      puts "event mode: #{Net.sp_net_poll_event_mode(0)}"

      # Reading past what fired answers "nothing", rather than walking off the set.
      puts "beyond fd: #{Net.sp_net_poll_event_fd(n)}"
      puts "beyond mode: #{Net.sp_net_poll_event_mode(n)}"
      puts "negative fd: #{Net.sp_net_poll_event_fd(-1)}"
      puts "negative mode: #{Net.sp_net_poll_event_mode(-1)}"

      # Interest changes in place, without a second registration.
      puts "modify: #{Net.sp_net_poll_modify(1, 1)}"
      puts "registered: #{Net.sp_net_poll_registered}"

      # An fd that was never registered is refused by both mutators.
      puts "modify absent: #{Net.sp_net_poll_modify(4242, 1)}"
      puts "unreg absent: #{Net.sp_net_poll_unregister(4242)}"
      puts "register bad fd: #{Net.sp_net_poll_register(-1, 1)}"

      # The set grows and shrinks with the registrations, well past the 256 the
      # older set was capped at.
      (3..600).each { |fd| Net.sp_net_poll_register(fd, 1) }
      puts "many: #{Net.sp_net_poll_registered}"
      (3..600).each { |fd| Net.sp_net_poll_unregister(fd) }
      puts "back to: #{Net.sp_net_poll_registered}"

      # Removing the last one empties it.
      puts "unregister: #{Net.sp_net_poll_unregister(1)}"
      puts "registered: #{Net.sp_net_poll_registered}"
    RUBY
  end

  it "sp net write partial" do
    _(ze0(<<~'RUBY', path: "lang/misc/sp_net_write_partial.rb")).must_answer "", stderr: "lang/misc/sp_net_write_partial.rb:9:in '<module:Net>': undefined method 'ffi_func' for module Net (NoMethodError)\n\n  ffi_func :sp_net_unix_listen,   [:str, :int],        :int\n  ^^^^^^^^\n\tfrom lang/misc/sp_net_write_partial.rb:8:in '<main>'\n", status: 1
      # Non-blocking write: hand back what the socket took, leave the policy for the
      # rest to the caller. sp_net_write_str / _bytes keep writing until everything
      # is gone, so one peer that cannot keep up delays delivery to every other one,
      # and nothing at the Ruby level can see it happening. (matz/spinel#4103)
      #
      # A UNIX-domain pair gives two live fds without binding a port, so this is
      # deterministic on any POSIX target.
      module Net
        ffi_func :sp_net_unix_listen,   [:str, :int],        :int
        ffi_func :sp_net_unix_connect,  [:str],              :int
        ffi_func :sp_net_accept,        [:int],              :int
        ffi_func :sp_net_set_nonblock,  [:int],              :int
        ffi_func :sp_net_write_partial, [:int, :str, :int],  :int
        ffi_func :sp_net_recv_some,     [:int, :int],        :str
        ffi_func :sp_net_close,         [:int],              :int
        ffi_func :sp_net_getpid,        [],                  :int
      end

      path = "/tmp/sp_net_wp_#{Net.sp_net_getpid}.sock"
      File.unlink(path) if File.exist?(path)
      lfd = Net.sp_net_unix_listen(path, 4)
      cfd = Net.sp_net_unix_connect(path)
      afd = Net.sp_net_accept(lfd)
      puts "paired: #{lfd > 0 && cfd > 0 && afd > 0}"

      Net.sp_net_set_nonblock(cfd)

      # An empty write is not an error and not a partial write.
      puts "empty: #{Net.sp_net_write_partial(cfd, '', 0)}"

      # A small write fits, and arrives whole.
      puts "small: #{Net.sp_net_write_partial(cfd, 'hello', 5)}"
      puts "read: #{Net.sp_net_recv_some(afd, 64)}"

      # Backpressure is visible rather than blocking: with nothing draining the far
      # end, the socket buffer fills and the write reports 0 accepted. The old
      # blocking write would still be parked here.
      chunk = "x" * 65536
      sent  = 0
      hit   = false
      200.times do
        n = Net.sp_net_write_partial(cfd, chunk, 65536)
        if n == 0
          hit = true
          break
        end
        break if n < 0
        sent += n
      end
      puts "backpressure: #{hit}"
      puts "accepted some first: #{sent > 0}"

      # Draining the far end makes room, and the write resumes -- the caller keeps
      # the remainder and retries, which is the whole point of the contract.
      #
      # ONE read, sized by what was actually buffered. How much the loop above got
      # in depends on the platform's socket buffer -- macOS defaults far smaller
      # than Linux -- so a second fixed-size read is a guess, and where the guess is
      # wrong it waits for bytes nobody will send. sp_net_recv_some waits for
      # readability even on a non-blocking fd, so that wait never ends.
      Net.sp_net_recv_some(afd, sent < 65536 ? sent : 65536)
      puts "resumes: #{Net.sp_net_write_partial(cfd, 'more', 4) > 0}"

      Net.sp_net_close(afd)
      Net.sp_net_close(cfd)
      Net.sp_net_close(lfd)
      File.unlink(path)
    RUBY
  end
end
