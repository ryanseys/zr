# frozen_string_literal: true

require "rbconfig"
require_relative "config"
require_relative "paths"
require_relative "tune"

module Zr
  # A warm compiler for the edit loop: `zr-dev serve` keeps one process
  # with the compiler loaded and YJIT warm, and each `zr run` or `zr build`
  # of this checkout gives it the build.
  #
  # A new zr process pays for its start before any build: ruby, the
  # compiler's files, and a cold YJIT, which lowers the kernel in 0.93 s
  # where a warm one takes 0.50 s. The server pays for these once.
  #
  # The client (`exe/zr`) sends its words, its working directory and its
  # environment, and passes its stdout and stderr. The server forks a
  # child for each request. The child builds as `zr` does, writes to the
  # client's own stdout and stderr, and answers with the binary to run or
  # with an exit status. The client then execs the binary itself, so the
  # program has the client's terminal, signals and exit status, as it
  # does without the server. (A child of the server is in another session:
  # the terminal would stop it at a read, and Ctrl-C would not reach it.)
  #
  # Each child starts from the state that the server had when it was
  # ready, and drops what depends on the files of the build (the runtime,
  # the settings). The server keeps only what content names: the
  # prelinked images. When a file that the server loaded changes (the
  # compiler itself), the server answers "fall back", so that the client
  # builds alone, and starts itself again.
  module Server
    VERSION = 1

    module_function

    # The socket of the server for this cache, or nil when the server is
    # off (`ZR_SERVER=0`) or the path is too long for a socket.
    def socket
      path = Config.current.server
      return nil if path == "0"

      path ||= File.join(Paths.cache, "server.sock")
      path.bytesize < 104 ? path : nil
    end

    # --- the client --------------------------------------------------------

    # Gives `argv` to the server when one listens, and does not return:
    # it execs the program or exits with the build's status. Returns when
    # there is no server, or the server says to build here, and then the
    # caller builds as it would without one.
    def hand_to(argv)
      path = client_socket(argv) or return
      require "socket"
      reply = begin
        UNIXSocket.open(path) do |sock|
          put(sock, { version: VERSION, argv: argv, cwd: Dir.pwd, env: ENV.to_h, ruby: RbConfig.ruby, ruby_version: RUBY_VERSION })
          sock.send_io($stdout)
          sock.send_io($stderr)
          take(sock)
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
      return nil if Zr.compiled? || ENV.key?(Tune::ADDED) || !%w[run build].include?(argv.first)
      return nil if argv.first == "run" && argv.any? { |word| word.start_with?("--emit", "--target") }

      path = socket
      path && File.socket?(path) ? path : nil
    end

    def answer(reply)
      case reply
      in { exit: Integer => code }
        $stdout.flush
        exit(code)
      in { run: String => binary, args: Array => args, temp: false }
        exec([binary, binary], *args)
      in { run: String => binary, args: Array => args, temp: true }
        require_relative "cli"
        status = CLI.run_binary(binary, args)
        File.delete(binary) if File.exist?(binary)
        CLI.exit_as(status)
      else
        why = reply.is_a?(Hash) ? reply[:fallback] : "no answer"
        warn "zr: the server did not build this (#{why}); building here" if Config.current.timing?
        nil
      end
    end

    # One message: its size, then its Marshal.
    def put(io, message)
      bytes = Marshal.dump(message)
      io.write([bytes.bytesize].pack("Q<"), bytes)
    end

    def take(io)
      size = io.read(8)&.unpack1("Q<") or raise EOFError
      Marshal.load(io.read(size) || raise(EOFError))
    end

    # --- the server --------------------------------------------------------

    # Serves until no request comes for `idle` seconds. `log` gets one
    # line for each request. `prime` makes the server warm before its first
    # request (a few seconds).
    #
    # One loop in the main thread waits for a request, for the end of a
    # build (its child holds the write end of a pipe), and for a client
    # that goes away. (In ruby 4.0.7, a `waitpid` in another thread never
    # returned the child while the main thread waited in `IO.select`.)
    def serve(path: socket, idle: 1800, log: $stdout, prime: true)
      raise ArgumentError, "the server has no socket (ZR_SERVER=0, or the path is too long)" unless path

      require "socket"
      @log = log
      @argv = [RbConfig.ruby, $PROGRAM_NAME, *ARGV]
      @jobs = {}
      began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      primed if prime
      @stamps = stamps
      listener = listen(path)
      # The binaries that the clients of an earlier server did not remove.
      require_relative "cache/janitor"
      Cache::Janitor.remove(Cache::Janitor.served)
      say format("listening at %s, ready in %.1f s", path, Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)
      loop do
        clients = @jobs.values.map { |job| job[:client] }.reject(&:closed?)
        ready, = IO.select([listener, *@jobs.keys, *clients], nil, nil, @jobs.empty? ? idle : nil)
        break say("idle for #{idle} s; stopping") unless ready

        ready.each { |io| io.equal?(listener) ? request(listener, path, listener.accept) : event(io) }
      end
    ensure
      listener&.close
      File.delete(path) if path && listener && File.socket?(path)
    end

    def listen(path)
      File.delete(path) if File.socket?(path)
      Paths.mkdir_p(File.dirname(path))
      UNIXServer.new(path).tap { File.chmod(0o600, path) }
    end

    # Reads one request, and forks its build, or answers "fall back".
    def request(listener, path, client)
      message = take(client)
      if (why = refusal(message))
        put(client, { fallback: why })
        client.close
        restart(listener, path) if why == "zr changed"
        return
      end
      ios = [client.recv_io, client.recv_io]
      done, held = IO.pipe
      pid = fork do
        done.close
        child(client, message, held, *ios)
      end
      [held, *ios].each(&:close)
      @jobs[done] = { pid: pid, client: client, argv: message[:argv], began: Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    rescue SystemCallError, IOError, TypeError, ArgumentError => e
      say "a request failed: #{e.class}: #{e.message}"
      client.close unless client.closed?
    end

    # A build answered (a byte on its pipe) or ended (the pipe closed), or
    # a client went away. A client that goes away before its answer (a
    # Ctrl-C) stops the build's group, whose end comes next.
    def event(io)
      if (job = @jobs[io])
        return job[:answered] = true unless io.read_nonblock(1, exception: false).nil?

        @jobs.delete(io)
        io.close
        Process.waitpid(job[:pid])
        job[:client].close unless job[:client].closed?
        say format("%s: %.2f s%s", job[:argv].join(" "), Process.clock_gettime(Process::CLOCK_MONOTONIC) - job[:began],
                   job[:stopped] ? ", stopped: the client went away" : "")
        refresh if @jobs.empty?
        return
      end
      done, job = @jobs.find { |_, held| held[:client].equal?(io) }
      return unless job && io.read_nonblock(1, exception: false).nil?

      io.close
      job[:answered] ||= !done.read_nonblock(1, exception: false).equal?(:wait_readable)
      return if job[:answered]

      job[:stopped] = true
      Process.kill(:KILL, -job[:pid])
    rescue SystemCallError, IOError => e
      say "#{e.class}: #{e.message}"
    end

    # Why the server must not build this request, or nil. A build in the
    # server must be the build that the client would do alone.
    def refusal(message)
      return "another protocol" unless message.is_a?(Hash) && message[:version] == VERSION
      return "another ruby" unless message[:ruby] == RbConfig.ruby && message[:ruby_version] == RUBY_VERSION
      return "zr changed" unless stamps == @stamps

      env = message[:env]
      %w[RUBYOPT RUBYLIB ZR_TUNE].each { |name| return "another #{name}" unless env[name] == ENV[name] }
      nil
    end

    # The build of one request, in a forked child: it runs the command as
    # `zr` does, with the client's directory, environment and output, and
    # answers with a binary to run or an exit status.
    def child(client, message, done, out, err)
      Process.setpgid(0, 0)
      $stdin.reopen(File::NULL)
      $stdout.reopen(out)
      $stderr.reopen(err)
      Dir.chdir(message[:cwd])
      ENV.replace(message[:env])
      fresh!(message)
      reply = nil
      CLI.served! { |binary, args, temp| reply = ran(binary, args, temp) }
      begin
        CLI.start(message[:argv])
        reply ||= { exit: 0 }
      rescue SystemExit => e
        reply = { exit: e.status }
      rescue Exception => e # rubocop:disable Lint/RescueException -- a child must answer
        warn "zr: #{e.class}: #{e.message}", *e.backtrace&.first(5)
        reply = { exit: 1 }
      end
      $stdout.flush
      $stderr.flush
      done.write("a")
      put(client, reply)
      exit!(0)
    end

    # The answer for a binary: the kept one as it is, or one in the build
    # directory under a second name, which the client deletes after the run.
    def ran(binary, args, temp)
      return { run: binary, args: args, temp: false } unless temp

      kept = File.join(Paths.cache, "served", "#{Process.pid}-program")
      Paths.mkdir_p(File.dirname(kept))
      File.link(binary, kept)
      { run: kept, args: args, temp: true }
    end

    # Drops the state that depends on the environment, so a child reads it
    # as a new zr would. The runtime and eval support that the server
    # loaded (`refresh`) stay when they are this build's: the same
    # settings, no path root, and the same runtime digest now.
    def fresh!(message = nil)
      Config.instance_variable_set(:@current, nil)
      Paths.instance_variable_set(:@cache, nil)
      Libraries.instance_variable_set(:@roots, nil) if defined?(Libraries)
      return if message && @digest && settings(message[:env]) == settings(ENV) && message[:argv].none? { |word| word.start_with?("--path-root") } &&
                RuntimeSources.for(Target.default).runtime_digest == @digest

      Zr.instance_variable_set(:@runtimes, nil)
      Zr.instance_variable_set(:@eval_supports, nil)
    end

    # The variables that steer a build.
    def settings(env) = env.select { |name, _| name.start_with?("ZR_") && name != "ZR_SERVER" && name != "ZR_TIMING" }

    # Loads, in the server, what the next builds read for the runtime of
    # the files as they are now: its description and symbols, and the
    # prelinked image of each object set that the cache has (the runtime,
    # and the runtime with eval support). A child then forks with them.
    # The server calls this when it is ready and after each build, so the
    # build after an edit to the runtime starts warm too.
    def refresh
      target = Target.default
      digest = RuntimeSources.for(target).runtime_digest
      return if digest.nil? || digest == @digest

      fresh!
      runtime = Zr.runtime(target)
      return @digest = nil unless File.exist?(runtime.object_path)

      runtime.description
      runtime.symbols
      live = Cache::Janitor.live_for(target)
      images = live.select { |path| path.end_with?("-prelink.bin") && File.exist?(path) }
      prelinks = Native::Build.instance_variable_get(:@prelinks) || {}
      prelinks.select! { |path, _| images.include?(path) }
      evals = live.select { |path| path.end_with?(".o") && path != runtime.object_path }
      [[runtime.object_path], *evals.map { |eval| [runtime.object_path, eval] }].each do |set|
        Native::Build.prelink(set) if images.include?(Native::Build.prelink_path(set))
      end
      @digest = digest
      say "loaded the runtime #{digest[0, 12]}"
    rescue StandardError => e
      @digest = nil
      say "could not load the runtime: #{e.class}: #{e.message}"
    end

    # Loads the compiler and warms it: lowers the kernel and three core
    # files, and builds and links a small program. Then drops that state,
    # loads the runtime for the next builds (`refresh`), and prepares the
    # heap for the forks (`Process.warmup`).
    def primed
      require_relative "cli"
      require_relative "runtime"
      require_relative "native/build"
      require_relative "cache/run"
      require_relative "cache/janitor"
      require_relative "cache/parse"
      target = Target.default
      runtime = Runtime.new(target)
      unit = runtime.unit
      %w[array string hash].each do |name|
        path = File.join(Paths::ROOT, "runtime/core/#{name}.rb")
        Lower.new(Hir.build(File.read(path), path, eval_support: false, target: target), unit, runtime.send(:kernel_symbols),
                  entry: "zr_core_#{name}", internal: true, target: target).run
      end
      Paths.tmpdir("zr-serve-") do |work|
        file = File.join(work, "primer.rb")
        File.write(file, "puts [1, 2].map { |n| n * 2 }.sum\n")
        program = Native::Build.lower(File.read(file), file, target: target)
        Native::Build.program(program, File.join(work, "primer"), work: work)
      end
      fresh!
      refresh
      GC.start
      Process.warmup if Process.respond_to?(:warmup)
    end

    # The stamp of each file of zr that the server loaded: when one
    # changes, the server's code is old.
    def stamps
      root = "#{Paths::ROOT}/"
      [*$LOADED_FEATURES.select { |path| path.start_with?(root) }, File.join(Paths::ROOT, "exe/zr")].sort.to_h do |path|
        stat = File.stat(path)
        [path, [stat.size, stat.mtime.to_r]]
      rescue SystemCallError
        [path, nil]
      end
    end

    # Starts the server again, with the new code: the same command.
    def restart(listener, path)
      say "zr changed; starting again"
      listener.close
      File.delete(path) if File.socket?(path)
      exec(*@argv)
    end

    def say(line)
      @log&.puts("zr server: #{line}")
      @log&.flush
    end
  end
end
