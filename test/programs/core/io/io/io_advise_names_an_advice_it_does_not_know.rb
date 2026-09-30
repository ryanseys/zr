File.open(__FILE__) do |f|
  begin
    f.advise(:bogus)
  rescue NotImplementedError => e
    p [e.class, e.message]
  end
  p f.advise(:sequential)
  p f.advise(:normal, 0, 0)
end
