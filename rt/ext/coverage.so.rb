# frozen_string_literal: true

# `coverage.so`: the C half of ext/coverage, over the line counts the
# kernel keeps (rt/kernel/coverage.rb). The compiler writes down which
# lines of each file run a :line event; those are the lines a result
# counts, and every other line is nil. The Ruby half, coverage.rb, is
# ruby's own.
module Coverage
  MODES = %i[lines oneshot_lines branches methods eval].freeze
  STATES = { idle: 0, suspended: 1, running: 2 }.freeze
  private_constant :MODES, :STATES

  def self.supported?(mode)
    raise TypeError, "wrong argument type #{mode.class} (expected Symbol)" unless mode.is_a?(Symbol)

    MODES.include?(mode)
  end

  def self.setup(*args)
    raise RuntimeError, "coverage measurement is already setup" unless state == :idle
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..1)" if args.size > 1

    mode = mode_of(args)
    %i[branches methods].each do |target|
      Primitive.zr_unimplemented("Coverage of #{target}") if mode[target]
    end
    Primitive.zr_hidden_set(self, :__mode__, mode)
    shift(:suspended)
    nil
  end

  def self.resume
    raise RuntimeError, "coverage measurement is not set up yet" if state == :idle
    raise RuntimeError, "coverage measurement is already running" if state == :running

    shift(:running)
    nil
  end

  def self.start(*args)
    setup(*args)
    resume
  end

  def self.suspend
    raise RuntimeError, "coverage measurement is not running" unless state == :running

    shift(:suspended)
    nil
  end

  def self.peek_result
    raise RuntimeError, "coverage measurement is not enabled" if state == :idle

    measured(false)
  end

  def self.result(options = nil)
    raise RuntimeError, "coverage measurement is not enabled" if state == :idle

    stop = clear = true
    unless options.nil?
      options = Hash.try_convert(options) or raise TypeError, "no implicit conversion of #{options.class} into Hash"
      stop = options[:stop] ? true : false
      clear = options[:clear] ? true : false
    end
    if stop && !clear
      warn "stop implies clear"
      clear = true
    end
    answer = measured(clear)
    shift(:idle) if stop
    answer
  end

  def self.state = Primitive.zr_hidden_get(self, :__state__) || :idle

  def self.running? = state == :running

  class << self
    private

    # The targets `setup` takes: none for the compatible mode, which
    # answers each file's lines alone.
    def mode_of(args)
      return {} if args.empty?
      return { lines: true, branches: true, methods: true, eval: true } if args[0] == :all

      options = Hash.try_convert(args[0]) or raise TypeError, "no implicit conversion of #{args[0].class} into Hash"
      mode = MODES.to_h { |target| [target, options[target] ? true : false] }
      raise RuntimeError, "cannot enable lines and oneshot_lines simultaneously" if mode[:lines] && mode[:oneshot_lines]

      mode.select { |_, on| on }
    end

    def shift(to)
      Primitive.zr_hidden_set(self, :__state__, to)
      Primitive.zr_coverage_state_set(STATES.fetch(to))
    end

    # The lines each measured file ran, as the mode shapes them.
    def measured(clear)
      mode = Primitive.zr_hidden_get(self, :__mode__)
      totals = Hash.new { |hash, path| hash[path] = [] }
      Primitive.zr_coverage_counts(clear).each do |path, counts|
        into = totals[path]
        counts.each_with_index { |count, i| into[i] = (into[i] || 0) + count }
      end
      totals.to_h do |path, counts|
        lines = lines_of(path, counts)
        next [path, lines.freeze] if mode.empty?

        shaped = {}
        shaped[:lines] = lines.freeze if mode[:lines]
        shaped[:oneshot_lines] = lines.each_index.select { |i| lines[i]&.positive? }.map { |i| i + 1 }.freeze if mode[:oneshot_lines]
        [path, shaped]
      end.freeze
    end

    # The file's line array: a count for each line that runs a :line
    # event, nil for every other line.
    def lines_of(path, counts)
      count, executable = coverable[path]
      return counts.map { |n| n.zero? ? nil : n } if count.nil?

      Array.new(count) { |i| executable.include?(i + 1) ? counts[i] || 0 : nil }
    end

    def coverable
      Primitive.zr_hidden_get(self, :__coverable__) || Primitive.zr_hidden_set(self, :__coverable__, compiled_lines)
    end

    def compiled_lines
      Primitive.zr_load_names(6).lines(chomp: true).to_h do |row|
        path, count, lines = row.split("\t", 3)
        [path, [Integer(count), lines.to_s.split(",").to_set { |line| Integer(line) }]]
      end
    end
  end
end
