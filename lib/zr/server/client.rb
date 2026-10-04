# frozen_string_literal: true

require "rbconfig"

module Zr
  class Server
    # The client of the warm compiler: `exe/zr` gives it the words of a
    # `zr run` or `zr build`, and it sends them to the server that listens
    # for this cache. It also holds the framing that both sides use to
    # send one message (`put`, `take`).
    class Client
      # One message: its size, then its Marshal.
      def self.put(io, message)
        bytes = Marshal.dump(message)
        io.write([bytes.bytesize].pack("Q<"), bytes)
      end

      def self.take(io)
        size = io.read(8)&.unpack1("Q<") or raise EOFError
        Marshal.load(io.read(size) || raise(EOFError))
      end

      # Gives `argv` to the server when one listens, and does not return:
      # it execs the program or exits with the build's status. Returns when
      # there is no server, or the server says to build here, and then the
      # caller builds as it would without one.
      def hand_to(argv)
        path = client_socket(argv) or return
        require "socket"
        reply = begin
          UNIXSocket.open(path) do |sock|
            Client.put(sock, { version: VERSION, argv: argv, settings: Config.given, cwd: Dir.pwd, env: ENV.to_h,
                               ruby: RbConfig.ruby, ruby_version: RUBY_VERSION })
            sock.send_io($stdout)
            sock.send_io($stderr)
            Client.take(sock)
          end
        rescue SystemCallError, IOError, TypeError, ArgumentError
          nil
        rescue Interrupt
          # A Ctrl-C while the server builds: the server stops the build when
          # this socket closes. zr ends by the signal, with no backtrace.
          Signal.trap(:INT, "SYSTEM_DEFAULT")
          Process.kill(:INT, Process.pid)
        end
        answer(reply)
      end

      # The server's socket for `argv`, or nil when the server does not
      # take it: a command other than `run` or `build`, a `zr run` of wasm or
      # for another target (the server builds only; the client runs), inside
      # a compiled program, or in the second start of zr.
      def client_socket(argv)
        return nil if Host.compiled? || ENV.key?(GcTuning::ADDED) || !%w[run build].include?(argv.first)
        return nil if argv.first == "run" && argv.any? { |word| word.start_with?("--emit", "--target") }

        path = Server.socket
        path && File.socket?(path) ? path : nil
      end

      private

      def answer(reply)
        case reply
        in { exit: Integer => code }
          $stdout.flush
          exit(code)
        in { run: String => binary, args: Array => args, temp: false }
          exec([binary, binary], *args)
        in { run: String => binary, args: Array => args, temp: true }
          require_relative "../cli"
          status = CLI.run_binary(binary, args)
          File.delete(binary) if File.exist?(binary)
          CLI.exit_as(status)
        else
          why = reply.is_a?(Hash) ? reply[:fallback] : "no answer"
          warn "zr: the server did not build this (#{why}); building here" if Config.current.timing?
          nil
        end
      end
    end
  end
end
