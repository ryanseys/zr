# floor/ceil/truncate WITH a precision keep the fraction: 157/50 is
# 3.14, so floor(1)=3.1=(31/10), ceil(1)=3.2=(16/5), truncate(1)=(31/10)
# (checked against ruby 4.0.7).

r = Rational(157, 50)
p r.round(2)
p r.round(-1)
p r.round
p r.floor(1)
p r.ceil(1)
p r.truncate(1)
p Rational(-7, 2).round
