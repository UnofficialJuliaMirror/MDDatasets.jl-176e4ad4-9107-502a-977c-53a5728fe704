#Test DataHR manipulations
#-------------------------------------------------------------------------------

using MDDatasets

#No real test code yet... just run demos:

println("\nTest constructors:")
@show d1 = DataF1([1,2,3], [4,5,6])
sweeplist = PSweep[
	PSweep("v1", [1,2])
	PSweep("v2", [4,5])
]
sweeplist2 = PSweep[
	PSweep("v1", [1,2])
	PSweep("v4", [4,5])
]
sweeplist3 = PSweep[
	PSweep("v1", [1,2])
	PSweep("v2", [3,4])
]
@show dhr = DataHR(sweeplist,DataF1[d1 d1; d1 d1])
dhr2 = DataHR(sweeplist2,DataF1[d1 d1; d1 d1])
dhr3 = DataHR(sweeplist3,DataF1[d1 d1; d1 d1])

println("\nTest broadcast operations on DataHR:")
dhr+dhr
try dhr+dhr2
catch e; println(e.msg)
end
try dhr+dhr3
catch e; println(e.msg)
end

println("\nTest basic operations on DataF1:")
d1 = DataF1(1:10.0)
d2 = xshift(d1, 4.5) + 12
d3 = d1 + 12
d4 = DataF1(d1.x, d1.y[end:-1:1])
d9 = xshift(d1, 100)

@show d1
@show d2
@show d3

r1 = d1+d2
r2 = d1+d3
#r3 = d1+d4

@show r1
@show r2
@show length(d1), length(d2), length(d3), length(r1), length(r2)

println("\nTest clip() function:")
@show d3
@show clip(d3, xmin=1.5, xmax=5.5)
@show d1
@show clip(d1, xmin=1.5, xmax=5.5)
@show clip(d1, xmin=2, xmax=5)
@show clip(d1, xmin=1, xmax=9)
@show clip(d1, 3:10)
@show clip(d1, xmin=3)
@show clip(d1, xmax=8.5)


#For cross function testing, mostly
y = [0,0,0,0,1,-3,4,5,6,7,-10,-5,0,0,0,-5,-10,10,-3,1,-4,0,0,0,0,0,0]
d10=DataF1(collect(1:length(y)), y)

println("\nTest cross functions:")
xingsall = CrossType(:all)
xingsrise = CrossType(:rise)
xingsfall = CrossType(:fall)

@show d10.y
@show xcross(d10, allow=xingsall).y
@show xcross(d10).y
@show xcross(d10, allow=xingsrise).y
@show xcross(d10, allow=xingsfall).y
@show xcross1(d10, n=1)
@show xcross(d10-.5).y
@show xcross1(d10-.5, n=2)

@show d10.y-.5
@show ycross(d10, .5, allow=xingsall).x
@show ycross(d10, .5, allow=xingsall).y
@show ycross(d10, .5).y
@show ycross(d10, .5, allow=xingsrise).y
@show ycross(d10, .5, allow=xingsfall).y

@show ycross1(d10, .5, n=3)

println("\nTest meas() interface:")
@show meas(:xcross, d10, allow=xingsrise).x
@show meas(:xcross, Event, d10, allow=xingsrise).x

#==
println("\nTest value():")
#Could be made into real test:
for i in 1:length(d10.x)
	@show d10.y[i], value(d10, x=i)
end
==#


:Test_Complete