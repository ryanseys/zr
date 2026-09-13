# Proc and Method: composition and currying, written over `call`.
class Proc
  # The scope the block was written in.
  def binding = Primitive.zr_proc_binding(self)

  alias === call

  # `lambda: true` reports a plain positional as :req and `false` as
  # :opt; nil takes the view this proc has of its own.
  def parameters(lambda: nil)
    lenient = lambda.nil? ? !self.lambda? : !lambda
    Primitive.zr_proc_param_rows(self, lenient)
  end

  def to_proc = self

  # Only a proc with a rest and no keywords or post parameters can
  # carry keywords in its rest; any other shape is warned about.
  def ruby2_keywords
    kinds = parameters.map(&:first)
    rest_at = kinds.index(:rest)
    if rest_at.nil? || kinds.include?(:key) || kinds.include?(:keyreq) || kinds.include?(:keyrest) || kinds.include?(:nokey) || kinds[(rest_at + 1)..].include?(:req)
      Primitive.zr_warn_here_m("Skipping set of ruby2_keywords flag for proc (proc accepts keywords or post arguments or proc does not accept argument splat)")
      return self
    end
    Primitive.zr_ruby2_mark_proc(self)
  end

  # `f >> g` calls f then g; `f << g` calls g then f. The result is a
  # lambda when the proc whose arguments it takes first is one, or when
  # that is any other callable.
  def >>(other)
    other = Proc.callable(other)
    first = self
    compose(lambda?) { |*args, **kwargs, &block| other.call(first.call(*args, **kwargs, &block)) }
  end

  def <<(other)
    other = Proc.callable(other)
    last = self
    compose(!other.is_a?(Proc) || other.lambda?) { |*args, **kwargs, &block| last.call(other.call(*args, **kwargs, &block)) }
  end

  # A proc that collects arguments over calls until `arity` of them
  # arrived, then calls this one. A lambda's arity is checked here.
  def curry(arity = nil)
    arity = implicit_integer(arity) unless arity.nil?
    required = self.arity >= 0 ? self.arity : -self.arity - 1
    if lambda? && arity
      most = parameters.any? { |kind, _| kind == :rest } ? nil : parameters.count { |kind, _| kind == :req || kind == :opt }
      if arity < required || (most && arity > most)
        raise ArgumentError, "wrong number of arguments (given #{arity}, expected #{Proc.arity_range(self)})"
      end
    end
    curried(arity || required, [])
  end

  def self.callable(other)
    raise TypeError, "callable object is expected" unless other.respond_to?(:call)

    other
  end

  # `2..3`, `2+` or `2` as a lambda's arity reads in an error.
  def self.arity_range(pr)
    params = pr.parameters
    required = params.count { |kind, _| kind == :req }
    return "#{required}+" if params.any? { |kind, _| kind == :rest }

    optional = params.count { |kind, _| kind == :opt }
    optional.zero? ? required.to_s : "#{required}..#{required + optional}"
  end

  private

  def compose(as_lambda, &body)
    Primitive.zr_proc_anonymous(as_lambda ? Primitive.zr_proc_lambda(body) : proc(&body))
  end

  def curried(arity, collected)
    original = self
    body = proc do |*args, &blk|
      all = collected + args
      all.size >= arity ? original.call(*all, &blk) : original.send(:curried, arity, all)
    end
    Primitive.zr_proc_anonymous(lambda? ? Primitive.zr_proc_lambda(body) : body)
  end
end

class Method
  def hash = [owner, name, receiver.object_id].hash

  # The box the method was defined in, while boxes are on: its own box for
  # a method a program wrote, the master box for one ruby itself carries.
  def box
    return nil unless Ruby::Box.enabled?

    Primitive.zr_method_box_m(self) || (source_location ? Ruby::Box.main : Ruby::Box.master)
  end

  def >>(other)
    other = Proc.callable(other)
    first = self
    Primitive.zr_proc_anonymous(lambda { |*args, **kwargs, &block| other.call(first.call(*args, **kwargs, &block)) })
  end

  def <<(other)
    other = Proc.callable(other)
    last = self
    Primitive.zr_proc_anonymous(lambda { |*args, **kwargs, &block| last.call(other.call(*args, **kwargs, &block)) })
  end

  def curry(arity = nil) = to_proc.curry(arity)
end
