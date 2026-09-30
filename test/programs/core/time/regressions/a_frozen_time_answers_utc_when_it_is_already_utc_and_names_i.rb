t = Time.at(0).utc.freeze
p t.utc.equal?(t), t.gmtime.equal?(t), t.year, t.inspect
begin; t.localtime; rescue => e; p e.class, e.message; end
l = Time.at(0).localtime("+09:00").freeze
begin; l.localtime("+09:00"); rescue => e; p e.class, e.message; end
begin; l.utc; rescue => e; p e.class, e.message; end
p l.hour, l.to_a.size, l.strftime("%Y")
u = Time.utc(2000, 1, 2).freeze
p u.utc.year, u.getlocal("+01:00").hour, (u + 1).frozen?, u.round.frozen?
