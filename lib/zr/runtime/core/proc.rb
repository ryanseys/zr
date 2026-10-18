# frozen_string_literal: true

# Proc and Method: composition and currying, written over `call`.
class Proc
  # The scope the block was written in.
  def binding = Primitive.zr_proc_binding(self)

  # `lambda: true` reports a plain positional as :req and `false` as
  # :opt; nil takes the view this proc has of its own.
  def parameters(lambda: nil)
    lenient = lambda.nil? ? !self.lambda? : !lambda
    Primitive.zr_proc_param_rows(self, lenient)
  end

  def to_proc = self

  # A copy of the Proc whose body, and the blocks and methods that it
  # writes, run with the refinements of `mods` in use; the receiver is
  # left as it is. No module gives the receiver itself.
  # proc_refined: a copy of the block whose body runs with the
  # refinements of `mods`. ruby copies the block's code at the copy's
  # first call (`refined_copy`) and keeps one copy for each block; a Proc
  # whose block is itself such a copy is never memoized, so its refined
  # Proc is copied now.
  def refined(*mods)
    return self if mods.empty?

    copied = Primitive.zr_hidden_get(self, :__refined__) && !Primitive.zr_hidden_get(self, :__copy__).nil?
    Warning.performance("Proc#refined on a Proc whose block was already copied by Proc#refined is not memoized") if copied
    refined = Primitive.zr_proc_refine_m(self, mods)
    Primitive.zr_state_set(refined, :__copy__, Primitive.zr_ruby2_marked_p(refined)) if copied
    refined
  end

  # The copy of each block that its refined Procs run: the refinements it
  # was made with, and whether the block was a ruby2_keywords one then
  # (rb_iseq_dup_with_independent_caches keeps the flag).
  REFINED_MEMO = {}
  private_constant :REFINED_MEMO

  # refinement_memo_lookup, at the first call of a refined Proc: the memo
  # of its block holds its copy when the same refinements made it with
  # the same ruby2_keywords flag; else ruby copies the block again, warns,
  # and the memo holds the new copy.
  private def refined_copy
    Primitive.attr! :hidden
    block = Primitive.zr_iseq_meta_word(self)
    recipe = Primitive.zr_proc_refinements(self)
    marked = Primitive.zr_ruby2_marked_p(self)
    if (memo = REFINED_MEMO[block])
      if same_refinements?(memo[0], recipe)
        return Primitive.zr_state_set(self, :__copy__, marked) if memo[1] == marked

        Warning.performance("Proc#refined re-copies the block because the ruby2_keywords flag changed after the copy was memoized")
      else
        Warning.performance("Proc#refined called with different modules for the same block disables memoization")
      end
    end
    REFINED_MEMO[block] = [recipe, marked]
    Primitive.zr_state_set(self, :__copy__, marked)
  end

  private def same_refinements?(memoized, recipe)
    Primitive.attr! :hidden
    memoized.size == recipe.size && memoized.each_index.all? { |i| memoized[i].equal?(recipe[i]) }
  end

  # Where the block's code starts and ends, or nil for a Proc that the
  # runtime made (rb_proc_source_range).
  def source_range = Ruby::SourceRange.send(:of, Primitive.zr_proc_span(self))

  def syntax_tree
    RubyVM::InstructionSequence.of(self)&.syntax_tree
  end

  # Only a proc with a rest and no keywords or post parameters can
  # take keywords in its rest; any other shape causes a warning.
  def ruby2_keywords
    kinds = parameters.map(&:first)
    rest_at = kinds.index(:rest)
    if rest_at.nil? || kinds.include?(:key) || kinds.include?(:keyreq) || kinds.include?(:keyrest) || kinds.include?(:nokey) || kinds[(rest_at + 1)..].include?(:req)
      Primitive.zr_warn_here_m("Skipping set of ruby2_keywords flag for proc (proc accepts keywords or post arguments or proc does not accept argument splat)")
      return self
    end
    # A refined Proc keeps the mark itself (zr_refined_block): its block
    # and the other Procs of that block do not get it.
    return Primitive.zr_ruby2_mark_proc(self) unless Primitive.zr_hidden_get(self, :__refined__)

    Primitive.zr_state_set(self, :__ruby2__, true)
    self
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
  # proc_curry reads the arity as a C int (NUM2INT).
  def curry(arity = nil)
    arity = IO.send(:c_int, arity) unless arity.nil?
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
               when :nokey, :noblock then +"nil"
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
      when :noblock then out << "&nil"
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

  # Where the def's code starts and ends, also for a core method that
  # CRuby writes in Ruby; nil for a C or attribute method.
  def source_range = Ruby::SourceRange.send(:of, Primitive.zr_method_span(self))

  def syntax_tree
    RubyVM::InstructionSequence.of(self)&.syntax_tree
  end
end

class UnboundMethod
  def source_range = Ruby::SourceRange.send(:of, Primitive.zr_method_span(self))

  def syntax_tree
    RubyVM::InstructionSequence.of(self)&.syntax_tree
  end
end
