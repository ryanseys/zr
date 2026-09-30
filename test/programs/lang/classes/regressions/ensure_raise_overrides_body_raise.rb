# Ruby semantics: when both the body and the ensure clause raise,
# the ensure-raise wins — the original body exception is replaced
# by the ensure exception as it propagates.

class T_ensure_raise_overrides_body_raise_C
  def f
    begin
      raise "original"
    ensure
      raise "from-ensure"
    end
  end
end

begin
  T_ensure_raise_overrides_body_raise_C.new.f
rescue => e
  puts e
end
