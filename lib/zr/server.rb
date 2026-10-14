# frozen_string_literal: true

require "rbconfig"
require_relative "config"
require_relative "paths"
require_relative "gc_tuning"
require_relative "server/client"

module Zr
  # A warm compiler for the edit loop: `zr-dev serve` keeps one process
  # with the compiler loaded and YJIT warm, and each `zr run` or `zr build`
  # of this checkout gives it the build.
  #
  # A new zr process pays for its start before any build: ruby, the
  # compiler's files, and a cold YJIT, which lowers the kernel in 0.93 s
  # where a warm one takes 0.50 s. The server pays for these once.
  #
  # The client (`exe/zr`, `Server::Client`) sends its words, its working
  # directory and its environment, and passes its stdout and stderr. The
  # server forks a child for each request. The child builds as `zr` does,
  # writes to the client's own stdout and stderr, and answers with the
  # binary to run or with an exit status. The client then execs the binary
  # itself, so the program has the client's terminal, signals and exit
  # status, as it does without the server. (A child of the server is in
  # another session: the terminal would stop it at a read, and Ctrl-C
  # would not reach it.)
  #
  # Each child starts from the state that the server had when it was
  # ready, and drops what depends on the files of the build (the runtime,
  # the settings). The server keeps only what content names: the
  # prelinked images. When a file that the server loaded changes (the
  # compiler itself), the server answers "fall back", so that the client
  # builds alone, and starts itself again.
  class Server
    # @rbs @path: String?
    # @rbs @idle: Integer
    # @rbs @log: IO?
    # @rbs @prime: bool
    # @rbs @argv: Array[String]
    # @rbs @jobs: Hash[IO, { pid: Integer, client: UNIXSocket, argv: Array[String], began: Float, ?answered: bool, ?stopped: bool }]
    # @rbs @stamps: Hash[String, [Integer, Rational]?]?
    # @rbs @digest: String?
    # @rbs @fingerprint: Hash[String, String]?

    VERSION = 2

    # The socket of the server for this cache, or nil when the server is
    # off (`ZR_SERVER=0`) or the path is too long for a socket.
    #: () -> String?
    def self.socket
      path = Config.current.server
      return nil if path == "0"

      path ||= File.join(Paths.cache, "server.sock")
      path.bytesize < 104 ? path : nil
    end

    # The entry points of `exe/zr` and `zr-dev serve`.
    #: (Array[String] argv) -> void
    def self.hand_to(argv) = Client.new.hand_to(argv)

    #: (**untyped options) -> void
    def self.serve(**options) = new(**options).serve

    # `path` is the socket to listen at, `idle` the seconds with no request
    # after which the server stops, and `log` gets one line for each
    # request. `prime` makes the server warm before its first request (a
    # few seconds).
    #: (?path: String?, ?idle: Integer, ?log: IO?, ?prime: bool) -> void
    def initialize(path: Server.socket, idle: 1800, log: $stdout, prime: true)
      @path = path
      @idle = idle
      @log = log
      @prime = prime
      @argv = [RbConfig.ruby, $PROGRAM_NAME, *ARGV]
      # The builds that run: the pipe of each build to its job.
      @jobs = {} #: Hash[IO, { pid: Integer, client: UNIXSocket, argv: Array[String], began: Float, ?answered: bool, ?stopped: bool }]
      # The stamps of zr's files when the server was ready (`stamps`).
      @stamps = nil
      # The digest of the runtime that the server has loaded (`refresh`).
      @digest = nil
    end

    # Serves until no request comes for `idle` seconds.
    #
    # One loop in the main thread waits for a request, for the end of a
    # build (its child holds the write end of a pipe), and for a client
    # that goes away. (In ruby 4.0, a `waitpid` in another thread never
    # returned the child while the main thread waited in `IO.select`.)
    #: () -> void
    def serve
      path = @path or raise ArgumentError, "the server has no socket (ZR_SERVER=0, or the path is too long)"

      require "socket"
      began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      primed if @prime
      @stamps = stamps
      listener = listen
      begin
        # The binaries that the clients of an earlier server did not remove.
        require_relative "cache/janitor"
        Cache::Janitor.remove(Cache::Janitor.served)
        say format("listening at %s, ready in %.1f s", path, Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)
        loop do
          clients = @jobs.values.map { |job| job[:client] }.reject(&:closed?)
          waited = [listener, *@jobs.keys, *clients] #: Array[IO]
          ready, = IO.select(waited, nil, nil, @jobs.empty? ? @idle : nil)
          unless ready
            say("idle for #{@idle} s; stopping")
            break
          end

          ready.each { |io| io.equal?(listener) ? request(listener, listener.accept) : event(io) }
        end
      ensure
        listener.close
        File.delete(path) if File.socket?(path)
      end
    end

    # Why the server must not build this request, or nil. A build in the
    # server must be the build that the client would do alone.
    #: (untyped message) -> String?
    def refusal(message)
      return "another protocol" unless message.is_a?(Hash) && message[:version] == VERSION
      return "another ruby" unless message[:ruby] == RbConfig.ruby && message[:ruby_version] == RUBY_VERSION
      return "zr changed" unless stamps == @stamps

      env = message[:env]
      %w[RUBYOPT RUBYLIB].each { |name| return "another #{name}" unless env[name] == ENV[name] }
      return "another ZR_TUNE" unless Config.new(message[:settings], env).tune? == Config.current.tune?

      nil
    end

    # The stamp of each file of zr that the server loaded: when one
    # changes, the server's code is old.
    #: () -> Hash[String, [Integer, Rational]?]
    def stamps
      root = "#{Paths::ROOT}/"
      [*$LOADED_FEATURES.select { |path| path.start_with?(root) }, File.join(Paths::ROOT, "exe/zr")].sort.to_h do |path|
        stat = File.stat(path)
        [path, [stat.size, stat.mtime.to_r]]
      rescue SystemCallError
        [path, nil]
      end
    end

    private

    #: () -> UNIXServer
    def listen
      path = @path #: String
      File.delete(path) if File.socket?(path)
      Paths.mkdir_p(File.dirname(path))
      UNIXServer.new(path).tap { File.chmod(0o600, path) }
    end

    # Reads one request, and forks its build, or answers "fall back".
    #: (UNIXServer listener, UNIXSocket client) -> void
    def request(listener, client)
      message = Client.take(client)
      if (why = refusal(message))
        Client.put(client, { fallback: why })
        client.close
        restart(listener) if why == "zr changed"
        return
      end
      out = client.recv_io
      err = client.recv_io
      done, held = IO.pipe
      pid = fork do
        done.close
        child(client, message, held, out, err)
      end
      [held, out, err].each(&:close)
      @jobs[done] = { pid: pid, client: client, argv: message[:argv], began: Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    rescue SystemCallError, IOError, TypeError, ArgumentError => e
      say "a request failed: #{e.class}: #{e.message}"
      client.close unless client.closed?
    end

    # A build answered (a byte on its pipe) or ended (the pipe closed), or
    # a client went away. A client that goes away before its answer (a
    # Ctrl-C) stops the build's group, whose end comes next.
    #: (IO io) -> void
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
      found = @jobs.find { |_, held| held[:client].equal?(io) } or return
      done, job = found
      return unless io.read_nonblock(1, exception: false).nil?

      io.close
      job[:answered] ||= !done.read_nonblock(1, exception: false).equal?(:wait_readable)
      return if job[:answered]

      job[:stopped] = true
      Process.kill(:KILL, -job[:pid])
    rescue SystemCallError, IOError => e
      say "#{e.class}: #{e.message}"
    end

    # The build of one request, in a forked child: it runs the command as
    # `zr` does, with the client's directory, environment and output, and
    # answers with a binary to run or an exit status.
    #: (UNIXSocket client, untyped message, IO done, IO out, IO err) -> void
    def child(client, message, done, out, err)
      Process.setpgid(0, 0)
      $stdin.reopen(File::NULL)
      $stdout.reopen(out)
      $stderr.reopen(err)
      Dir.chdir(message[:cwd])
      ENV.replace(message[:env])
      Config.given!(message[:settings])
      fresh!(message)
      reply = nil #: Hash[Symbol, untyped]?
      CLI.served! { |binary, args, temp| reply = ran(binary, args, temp) }
      begin
        CLI.start(message[:argv])
        reply ||= { exit: 0 }
      rescue SystemExit => e
        reply = { exit: e.status }
      rescue Exception => e # rubocop:disable Lint/RescueException -- a child must answer
        warn "zr: #{e.class}: #{e.message}", *Array(e.backtrace).first(5)
        reply = { exit: 1 }
      end
      $stdout.flush
      $stderr.flush
      done.write("a")
      Client.put(client, reply)
      exit!(0)
    end

    # The answer for a binary: the kept one as it is, or one in the build
    # directory under a second name, which the client deletes after the run.
    #: (String binary, Array[String] args, bool temp) -> { run: String, args: Array[String], temp: bool }
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
    #: (?untyped message) -> void
    def fresh!(message = nil)
      Session.current.reset!(keep_runtimes: true)
      return if message && @digest && Config.current.fingerprint == @fingerprint && message[:argv].none? { |word| word.start_with?("--path-root") } &&
                RuntimeSources.for(Target.default).runtime_digest == @digest

      Session.current.reset!
    end

    # Loads, in the server, what the next builds read for the runtime of
    # the files as they are now: its description and symbols, and the
    # prelinked image of each object set that the cache has (the runtime,
    # and the runtime with eval support). A child then forks with them.
    # The server calls this when it is ready and after each build, so the
    # build after an edit to the runtime starts warm too.
    #: () -> void
    def refresh
      target = Target.default
      digest = RuntimeSources.for(target).runtime_digest
      return if digest.nil? || digest == @digest

      fresh!
      runtime = Runtime.for(target)
      return @digest = nil unless File.exist?(runtime.object_path)

      runtime.description
      runtime.symbols
      live = Cache::Janitor.live_for(target)
      images = live.select { |path| path.end_with?("-prelink.bin") && File.exist?(path) }
      Native::Build.prelinks.select! { |path, _| images.include?(path) }
      evals = live.select { |path| path.end_with?(".o") && path != runtime.object_path }
      [[runtime.object_path], *evals.map { |eval| [runtime.object_path, eval] }].each do |set|
        Native::Build.prelink(set) if images.include?(Native::Build.prelink_path(set))
      end
      @digest = digest
      @fingerprint = Config.current.fingerprint
      say "loaded the runtime #{digest[0, 12]}"
    rescue StandardError => e
      @digest = nil
      say "could not load the runtime: #{e.class}: #{e.message}"
    end

    # Loads the compiler and warms it: lowers the kernel and three core
    # files, and builds and links a small program. Then drops that state,
    # loads the runtime for the next builds (`refresh`), and prepares the
    # heap for the forks (`Process.warmup`).
    #: () -> void
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
        path = File.join(Paths::RUNTIME, "core/#{name}.rb")
        Runtime.lower_core_file(path, File.read(path), unit, unit.symbols.ids.dup.freeze, target)
      end
      Paths.tmpdir("zr-serve-") do |work|
        file = File.join(work, "primer.rb")
        File.write(file, "puts [1, 2].map { |n| n * 2 }.sum\n")
        program = Native::Build.lower(File.read(file), file, target: target)
        Native::Build.program(program, File.join(work, "primer"), work: work)
      end
      fresh!
      refresh
      Process.warmup if Process.respond_to?(:warmup)
    end

    # Starts the server again, with the new code: the same command.
    #: (UNIXServer listener) -> void
    def restart(listener)
      say "zr changed; starting again"
      listener.close
      path = @path #: String
      File.delete(path) if File.socket?(path)
      exec(*@argv)
    end

    #: (String line) -> void
    def say(line)
      @log&.puts("zr server: #{line}")
      @log&.flush
    end
  end
end
