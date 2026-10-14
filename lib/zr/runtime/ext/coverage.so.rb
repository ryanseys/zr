# frozen_string_literal: true

# `coverage.so`: the C half of ext/coverage, over the line counts the
# kernel keeps (lib/zr/runtime/kernel/coverage.rb). The compiler writes down which
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
    Primitive.zr_hidden_set(self, :__mode__, mode)
    Primitive.zr_coverage_evals_set(mode[:eval] ? true : false)
    Primitive.zr_hidden_set(self, :__eval_lines__, {})
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
      hash = Hash.try_convert(options) or raise TypeError, no_implicit_conversion(options, "Hash")
      stop = hash[:stop] ? true : false
      clear = hash[:clear] ? true : false
    end
    if stop && !clear
      warn "stop implies clear", uplevel: 0
      clear = true
    end
    answer = measured(clear)
    shift(:idle) if stop
    answer
  end

  def self.state = Primitive.zr_hidden_get(self, :__state__) || :idle

  def self.running? = state == :running

  # coverage.c defines these with rb_define_module_function, so a class
  # that includes Coverage has a private copy of each.
  %i[setup start resume suspend peek_result result state running?].each do |name|
    define_method(name) { |*args| Coverage.public_send(name, *args) }
    private name
  end

  class << self
    private

    # The targets that `setup` takes: none for the compatible mode, which
    # returns only each file's lines.
    def mode_of(args)
      return {} if args.empty?
      return { lines: true, branches: true, methods: true, eval: true } if args[0] == :all

      options = Hash.try_convert(args[0]) or raise TypeError, no_implicit_conversion(args[0], "Hash")
      mode = MODES.to_h { |target| [target, options[target] ? true : false] }
      raise RuntimeError, "cannot enable lines and oneshot_lines simultaneously" if mode[:lines] && mode[:oneshot_lines]

      mode.select { |_, on| on }
    end

    def shift(to)
      Primitive.zr_hidden_set(self, :__state__, to)
      Primitive.zr_coverage_state_set(STATES.fetch(to))
    end

    # The lines each measured file ran, as the mode shapes them. A file
    # coverage did not measure is left out whatever the mode, so its
    # branches go with its lines.
    def measured(clear)
      mode = Primitive.zr_hidden_get(self, :__mode__)
      totals = Hash.new { |hash, path| hash[path] = [] }
      Primitive.zr_coverage_counts(clear).each do |path, counts|
        into = totals[path]
        counts.each_with_index { |count, i| into[i] = (into[i] || 0) + count }
      end
      runs = mode[:branches] ? Primitive.zr_coverage_branch_counts(clear) : nil
      claims = mode[:methods] ? claimed(Primitive.zr_coverage_method_counts(clear)) : nil
      untracked.each { |path| totals.delete(path) }
      totals.to_h do |path, counts|
        lines = lines_of(path, counts)
        next [path, lines.freeze] if mode.empty?

        shaped = {}
        shaped[:lines] = lines.freeze if mode[:lines]
        shaped[:oneshot_lines] = lines.each_index.select { |i| lines[i]&.positive? }.map { |i| i + 1 }.freeze if mode[:oneshot_lines]
        # rb_coverage_peek_result freezes the line arrays only.
        shaped[:branches] = branches_of(path, runs) if runs
        shaped[:methods] = claims[path] || {} if claims
        [path, shaped]
      end.freeze
    end

    # A file's branches: each root, and under it each of its sides with
    # the times that side ran. The key is `[kind, id, start line, start
    # column, end line, end column]` with the id counted from 0 a file,
    # which is what the rows are already in the order of.
    def branches_of(path, runs)
      rows = branch_table[path] or return {}

      out = {}
      roots = {}
      rows.each_with_index do |(kind, counter, root, *where), i|
        key = [kind, i, *where].freeze
        if root.nil?
          roots[i] = (out[key] = {})
        else
          roots[root][key] = runs[counter] || 0
        end
      end
      out
    end

    # Each method that a definition claimed while coverage was set up, as
    # `{path => {[owner, name, start line, start column, end line, end
    # column] => count}}`. The claim contains the owner and the name, and
    # its def-site entry contains the span. A file that coverage did not
    # measure drops out with its lines. Two claims of one key add, as the
    # C extension does with a method defined twice.
    def claimed(rows)
      sites = def_table
      out = {}
      rows.each_slice(4) do |site, owner, name, count|
        where = sites[site] or next

        path, span = where
        methods = (out[path] ||= {})
        key = [owner, name, *span].freeze
        methods[key] = (methods[key] || 0) + count
      end
      out
    end

    # Every def site that the compiler recorded, by its id: the file where
    # it was written and the span by which ruby identifies a method made from it.
    def def_table
      Primitive.zr_hidden_get(self, :__defs__) || Primitive.zr_hidden_set(self, :__defs__, compiled_defs)
    end

    def compiled_defs
      sites = {}
      Primitive.zr_load_names(7).lines(chomp: true).each do |row|
        path, *cells = row.split("\t")
        cells.each do |cell|
          id, *span = cell.split(",").map { |n| Integer(n) }
          sites[id] = [path, span]
        end
      end
      sites
    end

    # The branch rows the compiler wrote down, by file.
    def branch_table
      Primitive.zr_hidden_get(self, :__branches__) || Primitive.zr_hidden_set(self, :__branches__, compiled_branches)
    end

    def compiled_branches
      Primitive.zr_load_names(6).lines(chomp: true).to_h do |row|
        path, *rows = row.split("\t")
        [path, rows.map do |cells|
          kind, counter, root, *where = cells.split(",")
          [kind.to_sym, Integer(counter), root.empty? ? nil : Integer(root), *where.map { |n| Integer(n) }]
        end]
      end
    end

    # The file's line array: a count for each line that runs a :line
    # event, nil for every other line.
    # An eval's lines under `eval: true` join those of its file.
    def lines_of(path, counts)
      count, executable = coverable[path]
      if (count_of_eval, eval = eval_lines[path])
        count = [count || 0, count_of_eval].max
        executable = (executable || Set.new) | eval
      end
      return counts.map { |n| n.zero? ? nil : n } if count.nil?

      Array.new(count) { |i| executable.include?(i + 1) ? counts[i] || 0 : nil }
    end

    def untracked
      Primitive.zr_hidden_get(self, :__untracked__) || Primitive.zr_hidden_set(self, :__untracked__, Set.new)
    end

    def eval_lines
      Primitive.zr_hidden_get(self, :__eval_lines__) || Primitive.zr_hidden_set(self, :__eval_lines__, {})
    end

    def coverable
      Primitive.zr_hidden_get(self, :__coverable__) || Primitive.zr_hidden_set(self, :__coverable__, compiled_lines)
    end

    # The lines and the def sites of a file that a require compiled while
    # the program ran: `{path => [line count, [line, ...]]}` and
    # `{path => [[id, *span], ...]}`. An eval's lines (`eval`) count only
    # under `eval: true`, and only until coverage stops.
    def compiled_lines!(rows, defs, eval = false)
      return if eval && !Primitive.zr_hidden_get(self, :__mode__)&.fetch(:eval, false)

      # A file compiled before coverage starts is not measured, even when
      # it starts coverage itself, until a later compile of it.
      unless eval
        idle = state == :idle
        rows.each_key { |path| idle ? untracked << path : untracked.delete(path) }
        return if idle
      end

      table = eval ? eval_lines : coverable
      rows.each do |path, (count, lines)|
        # rb_iseq_new_eval makes the line array of an eval's file only when
        # the file has none. A later eval counts into it, each of its lines
        # from zero again, and its lines past the end count nowhere.
        if eval && (known = known_size(path))
          count = known
          lines = lines.select { |line| line <= known }
          Primitive.zr_coverage_reset(path, lines.to_a)
        end
        was_count, was = table[path] || [0, Set.new]
        table[path] = [[was_count, count].max, was | lines]
      end
      sites = def_table
      defs.each { |path, list| list.each { |id, *span| sites[id] = [path, span] } }
    end

    # The size of the line array that an earlier eval gave `path`, or nil.
    def known_size(path) = eval_lines[path]&.first

    # The first def-site id that no compiled scope has, for the next
    # compile at run time; nil while Coverage does not measure.
    def next_def_site
      return nil if state == :idle

      (def_table.keys.max || -1) + 1
    end

    def compiled_lines
      Primitive.zr_load_names(5).lines(chomp: true).to_h do |row|
        path, count, lines = row.split("\t", 3)
        [path, [Integer(count), lines.to_s.split(",").to_set { |line| Integer(line) }]]
      end
    end
  end
end
