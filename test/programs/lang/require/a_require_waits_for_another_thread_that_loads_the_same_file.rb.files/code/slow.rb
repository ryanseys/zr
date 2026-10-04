$rec << :pre
Thread.current[:in] = true
if (t = Thread.current[:wait_for])
  Thread.pass until t.backtrace && t.backtrace.any? { |c| c.include?("require") } && t.stop?
end
raise "boom" if Thread.current[:boom]
$rec << :post
