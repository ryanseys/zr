# frozen_string_literal: true

# The `Ruby` namespace represents the running ruby. `Ruby::Box` is a
# separate world inside the program: its own toplevel constants, its own
# globals, and its own patches to the shared classes. A box reads the
# shared world as the runtime had it when the program started, never
# with the program's later writes.
module Ruby
  VERSION = RUBY_VERSION
  ENGINE = RUBY_ENGINE
  ENGINE_VERSION = RUBY_ENGINE_VERSION
  PLATFORM = RUBY_PLATFORM
  PATCHLEVEL = RUBY_PATCHLEVEL
  RELEASE_DATE = RUBY_RELEASE_DATE
  REVISION = RUBY_REVISION
  COPYRIGHT = RUBY_COPYRIGHT
  DESCRIPTION = RUBY_DESCRIPTION

  # Ruby::Prism, the parser of the running ruby, as ruby's autoload. A
  # program that uses it includes ruby/prism (Hir::Build.ruby_prism).
  Primitive.zr_autoload_computed(self, :Prism, "ruby/prism", nil, false, nil)

  # Where a piece of code starts and ends (Proc#source_range and
  # Method#source_range): its path, its real path when it comes from a
  # file, and its first and last line and byte column. Only the core makes
  # one, as rb_source_range_new does.
  class SourceRange
    Primitive.zr_undef_alloc(self)
    class << self
      undef_method :new
    end

    # The range of a span that the kernel gives: [path, whether it comes
    # from a file, line, column, end line, end column], or nil for none.
    def self.of(span)
      Primitive.attr! :hidden
      return nil if span.nil?

      range = Primitive.zr_class_build(self)
      absolute = span[1] ? Kernel.send(:real_path_of, span[0]) : nil
      Primitive.zr_hidden_set(range, :__range__, [span[0], absolute, span[2], span[3], span[4], span[5]].freeze)
      range
    end
    private_class_method :of

    def path = Primitive.zr_hidden_get(self, :__range__)[0]
    def absolute_path = Primitive.zr_hidden_get(self, :__range__)[1]
    def start_line = Primitive.zr_hidden_get(self, :__range__)[2]
    def start_column = Primitive.zr_hidden_get(self, :__range__)[3]
    def end_line = Primitive.zr_hidden_get(self, :__range__)[4]
    def end_column = Primitive.zr_hidden_get(self, :__range__)[5]

    def inspect
      path, absolute, line, column, last, last_column = Primitive.zr_hidden_get(self, :__range__)
      "#<Ruby::SourceRange #{absolute || path}:(#{line},#{column})-(#{last},#{last_column})>"
    end
  end

  class Box < Module
    # A loaded feature, which a box counts for itself.
    class Entry; end

    # box.c's Loader: require, require_relative and load, each a private
    # method and a singleton method that marks the frame as a box's load
    # and passes the call on to Kernel's. Object includes it when boxes
    # are enabled.
    module Loader
      def self.require(...) = super
      def self.require_relative(...) = super
      def self.load(...) = super

      private

      def require(...) = super
      def require_relative(...) = super
      def load(...) = super
    end

    def self.enabled? = !ENV["RUBY_BOX"].nil?

    # The box the running code belongs to. Ruby counts the box the
    # program itself runs in as one, so main is a box too.
    def self.current = Primitive.zr_box_reach || (enabled? ? main : nil)

    def initialize
      raise RuntimeError, +"Ruby::Box is disabled" unless Box.enabled?

      (Primitive.zr_hidden_get(Box, :boxes) || Primitive.zr_hidden_set(Box, :boxes, [])) << self
      @slot = Primitive.zr_box_slot
      Primitive.zr_box_register(Box)
      @shadows = {}
      @loaded = {}
      @globals = {}
      Primitive.zr_box_master_gvars.each { |key, value| @globals[key] = value }
      @load_path = []
      @globals[Primitive.zr_box_gvar_key(:$LOAD_PATH)] = @load_path
      @globals[Primitive.zr_box_gvar_key(:$LOADED_FEATURES)] = []
      object = Class.new(Object)
      Primitive.zr_box_name(object, -"Object")
      @shadows[Object] = object
      Primitive.zr_box_bind(Object, @slot, object)
      object.include(self)
      @main = object.allocate
      @main = object.allocate
      @cref = Primitive.zr_eval_cref_under(self, nil)
    end

    def eval(source) = run(::Zr::Eval.current.compile(source, "eval", 1, []), nil)

    def load_path = @load_path

    def require(feature) = load_feature(feature.to_s, true)

    def require_relative(feature)
      here = File.dirname(caller_locations(1, 1).first.path)
      load_feature(File.expand_path(feature.to_s, here), true)
    end

    def load(feature) = load_feature(feature.to_s, false)

    def inspect = @shown || "#<Ruby::Box:#{@slot + 4},user,optional>"

    private

    Primitive.attr! :hidden

    # The class that this box sees in place of a shared one: its own, with
    # the shared class under it, so the box reads what it does not patch
    # from there. A shared MODULE's replacement goes into every shadow
    # whose chain already includes the module.
    def __shadow__(shared)
      found = @shadows[shared]
      return found if found

      made = mint(shared)
      return shared unless made

      @shadows[shared] = made
      Primitive.zr_box_name(made, shared.name)
      Primitive.zr_box_bind(shared, @slot, made)
      if shared.instance_of?(Module)
        @shadows.each { |origin, view| view.include(made) if !origin.equal?(shared) && origin.include?(shared) }
      end
      made
    end

    # A shadow of a class inherits from it. A module has nothing to
    # inherit from, so the shadow INCLUDES it, which reaches the
    # module's methods and its constants the same way.
    def mint(shared)
      return Class.new(shared) if shared.is_a?(Class)

      made = Module.new
      made.include(shared)
      made
    rescue StandardError
      nil
    end

    # The snippet runs IN the box: what it defines, what it reads and
    # what it writes are the box's own until the call is over.
    def run(code, _path)
      Primitive.attr! :hidden
      Primitive.zr_box_stamp(code[4], self)
      Primitive.zr_box_compiled(code[1])
      Primitive.zr_eval_run(code, @main, @cref, nil, nil)
    end

    # A file the box reads and runs for itself, so a feature main has
    # already loaded runs again here.
    def load_feature(feature, once)
      path = resolve(feature)
      raise LoadError, "cannot load such file -- #{feature}" unless path
      return false if once && @loaded[path]

      @loaded[path] = true
      @globals[Primitive.zr_box_gvar_key(:$LOADED_FEATURES)] << path
      run(::Zr::Eval.current.compile(File.read(path), path, 1, []), path)
      true
    end

    def resolve(feature)
      return feature if Primitive.zr_path_kind(feature) == 2

      name = feature.end_with?(".rb") ? feature : "#{feature}.rb"
      return name if Primitive.zr_path_kind(name) == 2

      @load_path.each do |root|
        found = File.join(root, name)
        return found if Primitive.zr_path_kind(found) == 2
      end
      nil
    end
  end
end

# The boxes that ruby makes for itself contain the entries that identify
# them, and those entries exist only where the gate is open.
if Ruby::Box.enabled?
  class Ruby::Box
    def main? = @kind == :main
    def root? = @kind == :root
    def master? = @kind == :master

    def self.main = @main ||= reserved(:main, 3, "user,main")
    def self.root = @root ||= reserved(:root, 2, "root")
    def self.master = @master ||= reserved(:master, 1, "master")

    # Module's singleton class has no allocate, so a box takes Class's.
    def self.reserved(kind, id, tail)
      box = Class.instance_method(:allocate).bind_call(self)
      Primitive.zr_hidden_set(box, :kind, kind)
      Primitive.zr_hidden_set(box, :shown, "#<Ruby::Box:#{id},#{tail}>")
      box
    end
    private_class_method :reserved
  end

  class Object
    include Ruby::Box::Loader
  end
end
