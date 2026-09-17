# frozen_string_literal: true

require "spec_helper"

describe "Net programs" do
  it "glob require and loaded features" do
    result = ze0(<<~'RUBY')
      # net/smtp loads its authenticators with a glob-and-require, and rubygems its
      # plugins the same way. The pattern is a compile-time fact, so the matches are
      # spliced like any other require -- and because they were, the loop's own
      # `require_relative` finds them already loaded and answers false rather than
      # raising.
      require "net/smtp"

      p defined?(Net::SMTP::AuthPlain)
      p defined?(Net::SMTP::AuthLogin)
      p defined?(Net::SMTP::AuthCramMD5)
      p Net::SMTP::AuthPlain.superclass

      # `$LOADED_FEATURES` holds every file the front end spliced, so re-requiring one
      # is the no-op Ruby makes it.
      p $LOADED_FEATURES.is_a?(Array)
      p $LOADED_FEATURES.any? { |f| f.end_with?("net/smtp.rb") }
      p $LOADED_FEATURES.any? { |f| f.end_with?("net/smtp/auth_plain.rb") }
      p $" .equal?($LOADED_FEATURES)

      # Socket.tcp exists (net/http probes for it to decide which connect path to
      # take); no connection is attempted here.
      require "socket"
      p Socket.respond_to?(:tcp)
      p Socket.method(:tcp).is_a?(Method)

      # `deprecate_constant` validates its arguments the way its siblings do.
      module Legacy
        OLD = 1
        deprecate_constant :OLD
      end
      p Legacy::OLD
      begin
        Legacy.deprecate_constant(:NOPE)
      rescue NameError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "constant"
      "constant"
      "constant"
      Net::SMTP::Authenticator
      true
      true
      true
      true
      true
      true
      1
      constant Legacy::NOPE not defined
    OUT
  end

  it "http request reaches a server thread" do
    result = ze0(<<~'RUBY')
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

    RUBY

    _(result).must_answer <<~'OUT'
      "hello /a"
      "200"
      "hello /b"
    OUT
  end

  it "issue net http missing" do
    _(ze0(<<~'RUBY')).must_answer "true\n"
      # `require "net/http"` -- the vendored gem loads and `Net::HTTP.get` answers.
      # net/http has no C extension of its own; it builds on the socket ext.
      require "net/http"
      p Net::HTTP.respond_to?(:get)
    RUBY
  end

  it "issue net smtp missing" do
    _(ze0(<<~'RUBY')).must_answer "\"constant\"\n"
      # `require "net/smtp"` -- the vendored gem loads and defines `Net::SMTP`.
      require "net/smtp"
      p defined?(Net::SMTP)
    RUBY
  end
end
