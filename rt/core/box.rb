# frozen_string_literal: true

# The `Ruby` namespace names the running ruby. `Ruby::Box` is a world
# of its own inside the program: its own toplevel constants, its own
# globals, and its own patches to the classes everybody shares. What a
# box reads of the shared world is what the runtime held when the
# program started, never what the program has written since.
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

  class Box < Module
    # A loaded feature, which a box counts for itself.
    class Entry; end

    # Where a box finds a feature to load.
    module Loader; end

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

    def eval(source) = run(::Ze0::Eval.current.compile(source, "eval", 1, []), nil)

    def load_path = @load_path

    def require(feature) = load_feature(feature.to_s, true)

    def require_relative(feature)
      here = File.dirname(caller_locations(1, 1).first.path)
      load_feature(File.expand_path(feature.to_s, here), true)
    end

    def load(feature) = load_feature(feature.to_s, false)

    def inspect = @shown || "#<Ruby::Box:#{@slot + 4},user,optional>"

    private

    # The class this box sees in place of a shared one: its own, with
    # the shared class underneath, so what the box does not patch it
    # reads from there. A shared MODULE's stand-in goes into every
    # shadow whose chain already holds the module.
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
      run(::Ze0::Eval.current.compile(File.read(path), path, 1, []), path)
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

# The boxes ruby makes for itself carry the rows that name them, and
# those rows exist only where the gate is open.
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
end
