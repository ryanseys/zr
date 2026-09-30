# A Rails-style Parameters wrapper changes each key to a Symbol, and
# calls itself for a nested Hash. A factory class method makes an
# instance with a bare `new` and sets a field from the `fetch` of
# the wrapper. The factory returns a local, and the recursive call
# is in an `is_a?(Hash)` arm that this input never takes.

class T_issue207_full_repro_Parameters
  def initialize(hash = {})
    @hash = symbolize_keys(hash)
  end

  def symbolize_keys(input)
    out = {}
    input.each do |k, v|
      sym = k.is_a?(Symbol) ? k : k.to_s.to_sym
      out[sym] = v.is_a?(Hash) ? symbolize_keys(v) : v
    end
    out
  end

  def fetch(key, default = nil)
    sym = key.to_sym
    return @hash[sym] if @hash.key?(sym)
    default
  end
end

class T_issue207_full_repro_ArticleParams
  def title; @title; end
  def title=(value); @title = value; end

  def self.from_raw(params)
    instance = new
    instance.title = params.fetch(:title, "")
    instance
  end
end

p = T_issue207_full_repro_Parameters.new({title: "hello"})
ap = T_issue207_full_repro_ArticleParams.from_raw(p)
puts ap.title
