#MDDatasets base types & core functions
#-------------------------------------------------------------------------------


#==High-level types
===============================================================================#
abstract DataMD #Multi-dimensional data
abstract LeafDS <: DataMD #Leaf dataset


#==Helper types (TODO: move to somewhere else?)
===============================================================================#

#Parameter sweep
type PSweep{T}
	id::AbstractString
	v::Vector{T}
#TODO: ensure increasing order?
end

#Explicitly tells multi-dispatch engine a value is meant to be an index:
immutable Index
	v::Int
end
Index(idx::AbstractFloat) = Index(round(Int,idx)) #Convenient
value(x::Index) = x.v

#TODO: Deprecate DataScalar?? - and LeafDS?
#immutable DataScalar{T<:Number} <: LeafDS
#	v::T
#end

immutable Point2D{TX<:Number, TY<:Number}
	x::TX
	y::TY
end


#==Leaf data elements
===============================================================================#
#==Supported scalar data types: use concrete types
   -Should make it easier for users to add functions
	-Fewer cases to think about
TODO:
   -Is this a good idea?
   -Would using DataScalar wrapper be better?==#
typealias DataFloat Float64
typealias DataInt Int64 #For indices, etc
typealias DataComplex Complex{Float64}

#Data2D, y(x): optimized for processing on y-data
#(All y-data points are stored contiguously)
type Data2D{TX<:Number, TY<:Number} <: LeafDS
	x::Vector{TX}
	y::Vector{TY}
#==TODO: find a way to assert lengths:
	function Data2D{TX<:Number, TY<:Number}(x::Vector{TX}, y::Vector{TY})
		@assert(length(x)==length(y), "Invalid Data2D: x & y lengths do not match")
		return new(x,y)
	end
==#
end
#Data2D{TX<:Number, TY<:Number}(::Type{TX}, ::Type{TY}) = Data2D(TX[], TY[]) #Empty dataset

#Build a Data2D object from a x-value range (make y=x):
function Data2D(x::Range)
	@assert(step(x)>0, "Data must be ordered with increasing x")
	Data2D(collect(x), collect(x))
end

#==Multi-dimensional data
===============================================================================#
#Types f data to be supported by large multi-dimensional datasets:
#typealias MDDataElem Union{Data2D,DataFloat,DataInt,DataComplex}

#Asserts whether a type is allowed as an element of a DataMD container:
elemallowed{T}(::Type{DataMD}, ::Type{T}) = false #By default
elemallowed(::Type{DataMD}, ::Type{DataFloat}) = true
elemallowed(::Type{DataMD}, ::Type{DataInt}) = true
elemallowed(::Type{DataMD}, ::Type{DataComplex}) = true
elemallowed(::Type{DataMD}, ::Type{Data2D}) = true

#Hyper-rectangle -representation of data:
#-------------------------------------------------------------------------------
#==IMPORTANT:
   -Want DataHR to support ONLY select concrete types & leaf types
	-Want to support leaf types like Data2D in GENERIC fashion
    (support Data2D[] ONLY - not specific versions of Data2D{X,Y} ==#
#==NOTE:
   -Do not restrict DataHR{T} parameter T until constructor.  This allows for
    a nicer error message.
      #ie: type DataHR{T<:MDDataElem} <: DataMD ==#
type DataHR{T} <: DataMD
	sweeps::Vector{PSweep}
	subsets::Array{T}

	function DataHR{TA,N}(sweeps::Vector{PSweep}, a::Array{TA,N})
		@assert(elemallowed(DataMD, T),
			"Can only create DataHR{T} for T ∈ {Data2D, DataFloat, DataInt, DataComplex}")
		@assert(length(sweeps)==N, "Number of sweeps must match dimensionality of subsets"i)
		return new(sweeps, a)
	end
end

#Shorthand (because default (non-parameterized) constructor was overwritten):
DataHR{T,N}(sweeps::Vector{PSweep}, a::Array{T,N}) = DataHR{T}(sweeps, a)

#Construct DataHR from Vector{PSweep}:
call{T}(::Type{DataHR{T}}, sweeps::Vector{PSweep}) = DataHR{T}(sweeps, Array{T}(arraysize(sweeps)...))


#==Useful assertions
===============================================================================#
#TODO: ASSERT SORTED

#Will have to remove this as a requirement
function assertsamex(d1::Data2D, d2::Data2D)
	@assert(d1.x==d2.x, "Operation currently only supported for the same x-data.")
end

#WARNING: relatively expensive
function assertincreasingx(d::Data2D)
	@assert(isincreasing(d.x), "Data2D.x must be in increasing order.")
end

#Validate data lengths:
function validatelengths(d::Data2D)
	@assert(length(d.x)==length(d.y), "Invalid Data2D: x & y lengths do not match.")
end

#Perform simple checks to validate data integrity
function validate(d::Data2D)
	validatelengths(d)
	assertincreasingx(d)
end


#==Add basic functionality to datasets
===============================================================================#
Base.copy(d::Data2D) = Data2D(d.x, copy(d.y))

subsets(ds::DataHR) = ds.subsets
subsets{T<:LeafDS}(ds::T) = [ds]
subscripts(d::DataHR) = [ind2sub(d.subsets,i) for i in 1:length(d.subsets)]
sweeps(d::DataHR) = d.sweeps
Base.names(list::Vector{PSweep}) = [s.id for s in list]

parameter(d::DataHR, dim::Int, idx::Int=0) = d.sweeps[dim].v[idx]
parameter(d::DataHR, dim::Int, coord::Tuple=0) = parameter(d, dim, coord[dim])
function parameter(d::DataHR, id::AbstractString, idx::Int=0)
	dim = findfirst((s)->(id==s.id), d.sweeps)
	@assert(dim>0, "Sweep not found: $id.")
	return parameter(d, dim, idx)
end
function parameter(d::DataHR, id::AbstractString, coord::Tuple=0)
	dim = findfirst((s)->(id==s.id), d.sweeps)
	@assert(dim>0, "Sweep not found: $id.")
	return parameter(d, dim, coord[dim])
end
function parameter(d::DataHR, coord::Tuple=0)
	result = []
	for i in 1:length(coord)
		push!(result, parameter(d, i, coord[i]))
	end
	return result
end


#==Useful functions
===============================================================================#

#Compute the size of an array from a Vector{PSweep}:
function arraysize(list::Vector{PSweep})
	dims = Int[]
	for s in list
		push!(dims, length(s.v))
	end
	return tuple(dims...)
end

#Obtain a Point2D structure from a Data2D dataset, at a given index.
Point2D(d::Data2D, i::Int) = Point2D(d.x[i], d.y[i])

#Interpolate between two points.
function interpolate{TX<:Number, TY<:Number}(p1::Point2D{TX,TY}, p2::Point2D{TX,TY}; x::Number=0)
	m = (p2.y-p1.y) / (p2.x-p1.x)
	return m*(x-p1.x)+p1.y
end

#Interpolate value of a Data2D dataset for a given x:
#NOTE:
#    -Uses linear interpolation
#    -Assumes value is zero when out of bounds
#    -TODO: binary search
function value(d::Data2D; x::Number=0)
	validate(d) #Expensive, but might avoid headaches
	y = 0
	pos = 0
	for i in 1:length(d)
		if d.x >= x
			pos = i
			break
		end
	end
	if pos > 1
		y = interpolate(Point2D(d, pos-1), Point2D(d, pos), x=x)
	elseif 1 == pos && x == d.x[1]
		y = d.x[1]
	end
	return y
end


function applydisjoint{TX<:Number, TY1<:Number, TY2<:Number}(fn::Function, d1::Data2D{TX,TY1}, d2::Data2D{TX,TY2})
	@assert(false, "Currently no support for disjoint datasets")
end

#Apply a function of two scalars to two Data2D objects:
#NOTE:
#   -Uses linear interpolation
#   -Do not use "map", because this is more complex than one-to-one mapping
#   -Assumes ordered x-values
function apply{TX<:Number, TY1<:Number, TY2<:Number}(fn::Function, d1::Data2D{TX,TY1}, d2::Data2D{TX,TY2})
	validate(d1); validate(d2); #Expensive, but might avoid headaches
	zero1 = zero(TY1); zero2 = zero(TY2)
	npts = length(d1)+length(d2)+1 #Allocate for worse case
	x = zeros(TX, npts)
	y = zeros(promote_type(TY1,TY2),npts)
	_x1 = d1.x[1]; _x2 = d2.x[1] #First x-values of d1 & d2
	x1_ = d1.x[end]; x2_ = d2.x[end] #Last x-values of d1 & d2

	if _x1 > x2_ || _x2 > x1_
		return applydisjoint(fn, d1, d2)
	end

	i = 1; i1 = 1; i2 = 1
	_x12 = max(_x1, _x2) #First intersecting point
	x[1] = min(_x1, _x2) #First point

	while x[i] < _x2 #Only d1 has values (assume d2 is 0)
		y[i] = fn(d1.y[i1], zero2)
		i += 1; i1 += 1
		x[i] = d1.x[i1]
	end
	while x[i] < _x1 #Only d2 has values (assume d1 is 0)
		y[i] = fn(zero1, d2.y[i2])
		i += 1; i2 += 1
		x[i] = d2.x[i2]
	end
	x[i] = _x12
	x12_ = min(x1_, x2_) #Last intersecting point
	p1 = p1next = Point2D(d1, i1)
	p2 = p2next = Point2D(d2, i2)
	if i1 > 1; p1 = Point2D(d1, i1-1); end
	if i2 > 1; p2 = Point2D(d2, i2-1); end
	while x[i] < x12_ #Intersecting section of x
		local y1, y2
		if p1next.x == x[i]
			y1 = p1next.y
			i1 += 1
			p1 = p1next; p1next = Point2D(d1, i1)
		else
			y1 = interpolate(p1, p1next, x=x[i])
		end
		if p2next.x == x[i]
			y2 = p2next.y
			i2 += 1
			p2 = p2next; p2next = Point2D(d2, i2)
		else
			y2 = interpolate(p2, p2next, x=x[i])
		end
		y[i] = fn(y1, y2)
		i+=1
		x[i] = min(p1next.x, p2next.x)
	end
	#End of intersecting section:
		y1 = interpolate(p1, p1next, x=x[i])
		y2 = interpolate(p2, p2next, x=x[i])
		y[i] = fn(y1, y2)
	while x[i] < x1_ #Only d1 has values left (assume d2 is 0)
		i += 1
		x[i] = d1.x[i1]
		y[i] = fn(d1.y[i1], zero2)
		i1 += 1
	end
	while x[i] < x2_ #Only d2 has values left (assume d1 is 0)
		i += 1
		x[i] = d2.x[i2]
		y[i] = fn(zero1, d2.y[i2])
		i2 += 1
	end
	npts = i

	return Data2D(resize!(x, npts), resize!(y, npts))
end


#==Base "vector"-like operations
===============================================================================#
function Base.length(d::Data2D)
	validatelengths(d) #Should be sufficiently inexpensive
	return length(d.x)
end

#Last line
