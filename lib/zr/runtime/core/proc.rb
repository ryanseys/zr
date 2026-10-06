# frozen_string_literal: true

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
  # take keywords in its rest; any other shape causes a warning.
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
      least, most = Proc.min_max_arity(self)
      if arity < least || (most && arity > most)
        raise ArgumentError, "wrong number of arguments (given #{arity}, expected #{Proc.arity_range(self)})"
      end
    end
    curried(arity || required, [])
  end

  # rb_proc_min_max_arity: the required count (and one for required
  # keywords), and the most (and one for any keywords), nil when a rest
  # takes any number.
  def self.min_max_arity(pr)
    Primitive.attr! :hidden
    params = pr.parameters
    required = params.count { |kind, _| kind == :req }
    least = required + (params.any? { |kind, _| kind == :keyreq } ? 1 : 0)
    return [least, nil] if params.any? { |kind, _| kind == :rest }

    keywords = params.any? { |kind, _| kind == :key || kind == :keyreq || kind == :keyrest } ? 1 : 0
    [least, required + params.count { |kind, _| kind == :opt } + keywords]
  end

  def self.callable(other)
    Primitive.attr! :hidden
    raise TypeError, +"callable object is expected" unless other.respond_to?(:call)

    other
  end

  # `2..3`, `2+` or `2` as a lambda's arity reads in an error.
  def self.arity_range(pr)
    Primitive.attr! :hidden
    least, most = min_max_arity(pr)
    return "#{least}+" if most.nil?

    least == most ? least.to_s : "#{least}..#{most}"
  end

  private

  def compose(as_lambda, &body)
    Primitive.attr! :hidden
    Primitive.zr_proc_anonymous(as_lambda ? Primitive.zr_proc_lambda(body) : proc(&body))
  end

  def curried(arity, collected)
    Primitive.attr! :hidden
    original = self
    body = proc do |*args, &blk|
      all = collected + args
      next original.call(*all, &blk) if all.size >= arity

      # curry: a block given before the last argument is dropped.
      Primitive.zr_warn_here_m("given block not used") if blk
      original.send(:curried, arity, all)
    end
    Primitive.zr_proc_anonymous(lambda? ? Primitive.zr_proc_lambda(body) : body)
  end
end

class Method
  # method_inspect: the parameter list that inspect shows, from what
  # `parameters` gives, for a method with no compiled table of its own.
  def self.params_shown(params)
    Primitive.attr! :hidden
    forwarding = params == [[:rest, :*], [:keyrest, :**], [:block, :&]]
    out = +"("
    params.each_index do |i|
      kind, name = params[i]
      name ||= case kind
               when :req, :opt then +"_"
               when :rest, :keyrest then +""
               when :block then +"block"
               when :nokey then +"nil"
               end
      case kind
      when :req then out << name.to_s
      when :opt then out << "#{name}=..."
      when :keyreq then out << "#{name}:"
      when :key then out << "#{name}: ..."
      when :rest then out << (name == :* ? (forwarding ? "..." : "*") : "*#{name}")
      when :keyrest
        if name != :**
          out << "**#{name}"
        elsif i.positive?
          out.delete_suffix!(", ")
        else
          out << "**"
        end
      when :block
        if name != :&
          out << "&#{name}"
        elsif forwarding
          out.delete_suffix!(", ")
        else
          out << "..."
        end
      when :nokey then out << "**nil"
      end
      out << ", " if i < params.size - 1
    end
    out << ")"
  end

  # The box where the method was defined, while boxes are on: its own box
  # for a method a program wrote, the master box for one that ruby includes.
  def box
    return nil unless Ruby::Box.enabled?

    Primitive.zr_method_box_m(self) || (source_location ? Ruby::Box.main : Ruby::Box.master)
  end

  def >>(other)
    other = Proc.callable(other)
    first = self
    Primitive.zr_proc_anonymous(lambda { |*args, **kwargs, &block| other.call(first.call(*args, **kwargs, &block)) })
  end

  # As Proc#<<: the composition is a lambda unless `other` is a proc.
  def <<(other) = to_proc << other

  def curry(arity = nil) = to_proc.curry(arity)
end
