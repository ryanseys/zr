# frozen_string_literal: true

require "spec_helper"

describe "OpenStruct: regressions" do
  it "an OpenStruct reads and writes by method and by subscript, and inspects its members" do
    result = ze0(<<~'RUBY')
      require "ostruct"

      o = OpenStruct.new(a: 1, b: "hi")
      p o.a
      p o.b
      o.c = [1, 2]
      p o.c
      p o[:a]
      o[:d] = 9
      p o[:d]
      p o.to_h
      p o.respond_to?(:a)
      p o.respond_to?(:z)
      p o.class
      p o
      p o.is_a?(OpenStruct)
      p o.is_a?(Struct)
      p o.instance_of?(OpenStruct)

      o2 = OpenStruct.new(a: 1, b: "hi", c: [1, 2], d: 9)
      p o == o2
      o2.d = 10
      p o == o2
      p o.nothere

      empty = OpenStruct.new
      p empty.to_h
      empty.set = "later"
      p empty.set

      arr = [OpenStruct.new(x: 1), "s", 42]
      p arr

      def show(v)
        p v
      end
      show(OpenStruct.new(n: 7))
    RUBY

    _(result).must_answer <<~'OUT'
      1
      "hi"
      [1, 2]
      1
      9
      {a: 1, b: "hi", c: [1, 2], d: 9}
      true
      false
      OpenStruct
      #<OpenStruct a=1, b="hi", c=[1, 2], d=9>
      true
      false
      true
      true
      false
      nil
      {}
      "later"
      [#<OpenStruct x=1>, "s", 42]
      #<OpenStruct n=7>
    OUT
  end

  it "OpenStruct#class is OpenStruct" do
    result = ze0(<<~'RUBY')
      require "ostruct"
      def assert_equal(expected, actual)
        raise unless expected == actual
      end
      o = OpenStruct.new(a: 1)
      assert_equal OpenStruct, o.class
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "an OpenStruct returned from a method keeps what the method wrote into it" do
    result = ze0(<<~'RUBY')
      require "ostruct"

      class Main
        def parse(flag)
          return 0 if flag

          result
        end

        def result
          options = OpenStruct.new
          options[:name] = "lee"
          options
        end
      end

      options = Main.new.parse(false)
      raise unless options[:name] == "lee"
      puts "ok3193"
    RUBY

    _(result).must_answer "ok3193\n"
  end

  it "OpenStruct.new takes a Hash held in a variable" do
    result = ze0(<<~'RUBY')
      require "ostruct"
      hash = {a: 1}
      object = OpenStruct.new(hash)
      raise unless object[:a] == 1
      puts "ok3194"
    RUBY

    _(result).must_answer "ok3194\n"
  end

  it "an OpenStruct returned from one arm of a method reads by method name" do
    result = ze0(<<~'RUBY')
      require "ostruct"

      class Crash
        def foo(bool)
          return 123 if !bool
          OpenStruct.new({name: "lee"})
        end
      end

      object = Crash.new.foo(true)
      raise unless object.name == "lee"
      puts "ok3197"
    RUBY

    _(result).must_answer "ok3197\n"
  end

  it "a subscript write to a returned OpenStruct shows through the reader" do
    result = ze0(<<~'RUBY')
      require "ostruct"
      class Main
        def parse(args)
          return 0 if args.empty?
          OpenStruct.new({name: "lee"})
        end
      end
      object = Main.new.parse(["--name", "lee"])
      object[:name] = "bob"
      raise unless object.name == "bob"
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "OpenStruct#inspect lists the members it has when it is called" do
    result = ze0(<<~'RUBY')
      require "ostruct"
      o = OpenStruct.new
      o.x = 1
      puts o.inspect
      o.y = "hi"
      puts o.inspect
      o2 = OpenStruct.new(a: 1, b: 2)
      puts o2.inspect
      # stored result keeps its snapshot (no dangling / later-mutation bleed)
      o3 = OpenStruct.new(a: 1)
      s = o3.inspect
      o3.b = 2
      puts s
      puts o3.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      #<OpenStruct x=1>
      #<OpenStruct x=1, y="hi">
      #<OpenStruct a=1, b=2>
      #<OpenStruct a=1>
      #<OpenStruct a=1, b=2>
    OUT
  end

  it "a frozen OpenStruct refuses a new member by either spelling" do
    result = ze0(<<~'RUBY')
      require "ostruct"
      o = OpenStruct.new(a: 1)
      p o.frozen?
      o.b = 2
      p o.b
      o.freeze
      p o.frozen?
      begin
        o.c = 3
        puts "no raise (member)"
      rescue FrozenError
        puts "member frozen"
      end
      begin
        o[:d] = 4
        puts "no raise (index)"
      rescue FrozenError
        puts "index frozen"
      end
      p o.a
      p o.b
    RUBY

    _(result).must_answer <<~'OUT'
      false
      2
      true
      member frozen
      index frozen
      1
      2
    OUT
  end

  it "a member built from a nil default reads back nil" do
    result = ze0(<<~'RUBY')
      require "ostruct"

      class Config
        attr_reader :flags
        def int(*opts, default: nil) = (@flags ||= []) << Flag.new(opts, default:)
      end

      class Flag
        attr_reader :default, :switches
        def initialize(switches, default: nil)
          @default, @switches = default, switches
        end

        def key = switches.last.sub(/^-+/, "").tr("-", "_").to_sym
      end

      class Main
        attr_reader :config
        def initialize = @config = Config.new
        def parse(argv) = OpenStruct.new(Parser.new.parse(config, argv)).freeze
      end

      class Parser
        def parse(config, argv)
          res = {}
          config.flags.each { res[_1.key] = _1.default }
          res
        end
      end

      def parse(argv)
        Main.new.tap { yield _1.config if block_given? }.parse(argv)
      end

      options = parse(["-i", "xx"]) do |o|
        o.int "-m", "--max-time"
        o.int "--retry", default: 3
      end

      raise "FAIL" if !options.max_time.nil?

      class F2
        attr_reader :d
        def initialize(d = nil) = @d = d
      end
      r2 = {}
      r2[:a] = F2.new.d
      r2[:b] = F2.new(3).d
      p r2[:a].nil?
      p r2
    RUBY

    _(result).must_answer "true\n{a: nil, b: 3}\n"
  end

  it "an aliased reader works as a Symbol block through map and select" do
    result = ze0(<<~'RUBY')
      require "ostruct"

      class Item
        attr_reader :required
        def initialize = (@required = true)
        alias_method :required?, :required
      end

      OpenStruct.new
      raise "FAIL" unless [Item.new].select(&:required?).length == 1
      puts "ok"

      class Point
        attr_reader :x
        def initialize(x) = (@x = x)
        alias_method :horizontal, :x
      end

      pts = [Point.new(3), Point.new(0)]
      p pts.map(&:horizontal)
      p pts.select(&:horizontal).length
    RUBY

    _(result).must_answer <<~'OUT'
      ok
      [3, 0]
      2
    OUT
  end

  it "a case over a regexp constant parses switches into a frozen OpenStruct" do
    result = ze0(<<~'RUBY')
      require "ostruct"
      class Config
        attr_reader :flags, :lookup

        def initialize
          @flags, @lookup = [], {}
        end

        def int(*opts) = add_flag(Flag.new(:int, opts))
        def str(*opts) = add_flag(Flag.new(:str, opts))
        def flag(switch) = lookup[switch]
        def add_flag(flag)
          flags << flag
          lookup[flag.key] = flag
          flag.switches.each { lookup[_1] = flag }
        end
      end

      class Flag
        SWITCH_RE = /\A-(\w|-\w[\w-]*)\z/
        attr_reader :kind, :switches
        def initialize(kind, opts)
          @kind, @switches = kind, opts
        end

        def parse(switch, param)
          case kind
          when :float then Float(param)
          when :int then Integer(param, 10)
          when :str then param
          when :sym then param.to_sym
          end
        end

        # def bool? = kind == :bool
        def key = @key ||= switch.sub(/^-+/, "").tr("-", "_").to_sym
        def switch = switches.last
      end

      module Slap
        def self.parse(argv = ARGV)
          Main.new.tap { yield _1.config if block_given? }.parse(argv)
        end

        class Main
          attr_reader :config
          def initialize
            @config = Config.new
          end

          def parse(argv)
            options = Parser.new(config).parse(argv)
            OpenStruct.new(options).freeze
          end
        end
      end

      class Parser
        attr_reader :config, :options, :queue
        def initialize(config)
          @config = config
        end

        def parse(argv)
          @options, @queue = {}, argv
          operands = []
          while (item = queue.shift)
            case item
            when Flag::SWITCH_RE then parse_switch(item, Regexp.last_match)
            when "", /\A[^-]/ then operands << item
            end
          end
          options[:_args] = operands
          options
        end

        def parse_switch(item, match)
          switch = "-#{match[1]}"
          flag = config.flag(switch)
          options[flag.key] = flag.parse(switch, queue.shift)
        end
      end

      options = Slap.parse(["--name", "Lee", "--count", "2", "--", "file"]) do |o|
        o.str "--name"
        o.int "--count"
      end

      raise "FAIL" unless options[:name] == "Lee"
      raise "FAIL" unless options[:count] == 2
      raise "FAIL" unless options[:_args] == ["file"]
    RUBY

    _(result).must_answer ""
  end

  it "an OpenStruct member named uniq or size shadows the method of that name" do
    result = ze0(<<~'RUBY')
      require "ostruct"

      class Flag
        attr_reader :switches
        def initialize(opts)
          @switches = opts
          raise ArgumentError, "duplicate switch" unless switches.uniq.length == switches.length
        end
      end

      class Config
        def str(*opts) = Flag.new(opts)
      end

      c = Config.new
      p c.str("-a", "--alpha").switches
      p c.str("-b").switches.uniq
      r = (c.str("-x", "-x").switches rescue $!.class); p r
      o = OpenStruct.new(uniq: "member", size: 7)
      p o.uniq
      p o.size
    RUBY

    _(result).must_answer <<~'OUT'
      ["-a", "--alpha"]
      ["-b"]
      ArgumentError
      "member"
      7
    OUT
  end
end
