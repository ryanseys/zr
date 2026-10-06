# A Proc's hash follows its equality: Procs from different Symbols, or
# from one block over different scopes, hash apart; a copy hashes alike.
p 1000.times.map { |i| :"test#{i}".to_proc.hash }.uniq.size >= 500
p 1000.times.map { proc {}.hash }.uniq.size >= 500
p 1000.times.map { {}.to_proc.hash }.uniq.size >= 500
pr = proc { 1 }
p pr.hash == pr.dup.hash, pr == pr.dup
p :upcase.to_proc.hash == :upcase.to_proc.hash
