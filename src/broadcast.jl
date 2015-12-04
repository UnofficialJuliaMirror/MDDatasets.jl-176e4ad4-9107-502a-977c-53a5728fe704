#MDDatasets broadcast support
#-------------------------------------------------------------------------------

import Base: broadcast

#==Nomenclature:
A 1-argument function is one where 1 argument in particular dictates the
dimensonality of the operation.

A 2-argument function is one where 2 arguments dictate the dimensionality of
the operation.
==#

#==Type definitions
===============================================================================#
abstract CastType
#Identifies a function cast with 1 argument of TCAST:
immutable CastType1{TCAST, POS} <: CastType; end
#Identifies a reducing function cast with 1 argument of TCAST, returning collection(Number):
immutable CastTypeRed1{TCAST, POS} <: CastType; end
#Identifies a function cast with 2 argument of TCAST1/2:
immutable CastType2{TCAST1, POS1, TCAST2, POS2} <: CastType; end
#Identifies a reducing function cast with 2 argument of TCAST1/2, returning collection(Number):
immutable CastTypeRed2{TCAST1, POS1, TCAST2, POS2} <: CastType; end #Reducing function (DataF1->Number)

#Constructors:
CastType{T}(::Type{T}, pos::Int) = CastType1{T, pos}()
CastType{T1,T2}(::Type{T1}, pos1::Int, ::Type{T2}, pos2::Int) =
	CastType2{T1, pos1, T2, pos2}()

CastTypeRed{T}(::Type{T}, pos::Int) = CastTypeRed1{T, pos}()
CastTypeRed{T1,T2}(::Type{T1}, pos1::Int, ::Type{T2}, pos2::Int) =
	CastTypeRed2{T1, pos1, T2, pos2}()



type CoordinateMap
	outidx::Vector{Int} #List of indices (of output coordinate)
	outlen::Int #Number of indices in output coordinate
end
CoordinateMap(inlen::Int, outlen::Int) =
	CoordinateMap(Vector{Int}(inlen), outlen)


#==Constants
===============================================================================#
#Cast on function capable of operating directly on base types (Number):
const CAST_BASEOP1 = CastType(Number, 1)
const CAST_BASEOPRED1 = CastTypeRed(Number, 1)

#Cast on function capable of operating directly on base types (Number, Number):
const CAST_BASEOP2 = CastType(Number, 1, Number, 2)

#Cast on function capable of operating only on DataF1:
const CAST_MD1 = CastType(DataF1, 1)
const CAST_MDRED1 = CastTypeRed(DataF1, 1)

#Cast on function capable of operating only on DataF1:
const CAST_MD2 = CastType(DataF1, 1, DataF1, 2)
const CAST_MDRED2 = CastTypeRed(DataF1, 1, DataF1, 2)


#==Error generators
===============================================================================#

function error_mismatchedsweep(basesweep::Vector{PSweep}, subsweep::Vector{PSweep})
	msg = "Mismatched sweeps:\n\nSweep1:\n$basesweep\n\nSweep2:\n$subsweep"
	return ArgumentError(msg)
end

#==Helper functions
===============================================================================#

function assertuniqueids(s::Vector{PSweep})
	n = length(s)
	for i in 1:n
		for j in (i+1):n
			if s[i] == s[j]
				throw(ArgumentError("Sweep id not unique: \"$(s[i])\""))
			end
		end
	end
end

#Find "base" sweep (most complex data configuration to broadcast up to)
#-------------------------------------------------------------------------------
function basesweep(s1::Vector{PSweep}, s2::Vector{PSweep})
	return length(s1)>length(s2)? s1: s2
end
basesweep(s::Vector{PSweep}, d::DataHR) = basesweep(s,d.sweeps)
basesweep(s::Vector{PSweep}, d::DataF1) = s
basesweep(s::Vector{PSweep}, d::Number) = s
basesweep{T<:Number}(s::Vector{PSweep}, v::Vector{T}) = s
basesweep(d1::DataHR, d2::DataHR) = basesweep(d1.sweeps,d2.sweeps)
basesweep(d1::DataHR, d2) = basesweep(d1.sweeps,d2)
basesweep(d1, d2::DataHR) = basesweep(d2.sweeps,d2)

#Functions to map coordinates when broadcasting up a DataHR dataset
#-------------------------------------------------------------------------------
function getmap(basesweep::Vector{PSweep}, subsweep::Vector{PSweep})
	assertuniqueids(basesweep)
	result = CoordinateMap(length(basesweep), length(subsweep))
	found = zeros(Bool, length(subsweep))
	for i in 1:length(basesweep)
		idx = findfirst((x)->(x.id==basesweep[i].id), subsweep)
		result.outidx[i] = idx
		if idx>1
			if basesweep[i].v != subsweep[idx].v
				msg = "Mismatched sweeps:\n$basesweep\n$subsweep"
				throw(error_mismatchedsweep(basesweep, subsweep))
			end
			found[idx] = true
		end
	end
	if !all(found); throw(error_mismatchedsweep(basesweep, subsweep)); end
	return result
end
function remap(_map::CoordinateMap, coord::Vector{Int})
	result = Vector{Int}(_map.outlen)
	for i in 1:length(coord)
		idx = _map.outidx[i]
		if idx > 0; result[idx] = coord[i]; end
	end
	return result
end


#==Broadcasting data up-to a given sweep dimension
===============================================================================#
function broadcast{T<:Number}(s::Vector{PSweep}, d::T)
	result = DataHR{T}(s)
	for i in 1:length(result.subsets)
		result.subsets[i] = d
	end
	return result
end
function broadcast(s::Vector{PSweep}, d::DataF1)
	result = DataHR{DataF1}(s)
	for i in 1:length(result.subsets)
		result.subsets[i] = d
	end
	return result
end
function broadcast{T}(s::Vector{PSweep}, d::DataHR{T})
	if s == d.sweeps; return d; end
	_map = getmap(s, d.sweeps)
	result = DataHR{T}(s)
	for coord in subscripts(result)
		result.subsets[coord...] = d.subsets[remap(_map, coord)...]
	end
	return result
end

#==Broadcast function call on multi-dimensional data
===============================================================================#
#Broadcast data up to base sweep of two first arguments, then call fn
function _broadcast{T}(::Type{T}, s::Vector{PSweep}, fn::Function, args...; kwargs...)
	bargs = Vector{Any}(length(args)) #Broadcasted version of args
	for i in 1:length(args)
		if typeof(args[i])<:DataMD
			bargs[i] = broadcast(s, args[i])
		else
			bargs[i] = args[i]
		end
	end
	bkwargs = Vector{Any}(length(kwargs)) #Broadcasted version of kwargs
	for i in 1:length(kwargs)
		(k,v) = kwargs[i]
		if typeof(v)<:DataMD
			bkwargs[i] = tuple(k, broadcast(s, v))
		else
			bkwargs[i] = kwargs[i]
		end
	end
	result = DataHR{T}(s) #Create empty result
	for i in 1:length(result.subsets)
		curargs = Vector{Any}(length(bargs))
		for j in 1:length(bargs)
			if typeof(bargs[j]) <: DataHR
				curargs[j] = bargs[j].subsets[i]
			else
				curargs[j] = bargs[j]
			end
		end
		curkwargs = Vector{Any}(length(bkwargs))
		for j in 1:length(bkwargs)
			(k,v) = bkwargs[j]
			if typeof(v) <: DataHR
				curkwargs[j] = tuple(k, v.subsets[i])
			else
				curkwargs[j] = bkwargs[j]
			end
		end
		result.subsets[i] = fn(curargs...; curkwargs...)
	end
	return result
end

#Find base sweep for a 1-argument broadcast
#-------------------------------------------------------------------------------
function fnbasesweep(fn::Function, d)
	msg = "No signature found for $fn($t, ...)"
	throw(ArgumentError(msg))
end
fnbasesweep{T}(fn::Function, d::DataHR{T}) = d.sweeps

#Ensure collection is composed of DataF1 (ex: DataHR{DataF1}):
#Collapses outer-most dimension of DataHR{Number} to a DataHR{DataF1} value, if necessary
#-------------------------------------------------------------------------------
ensure_coll_DataF1(fn::Function, d) = d #Plain data is ok.
ensure_coll_DataF1(fn::Function, d::DataHR) = DataHR{DataF1}(d)

#Broadcast functions capable of operating directly on 1 base type (Number):
#-------------------------------------------------------------------------------
#DataHR{DataF1/Number}
broadcast{T}(::CastType1{Number,1}, fn::Function, d::DataHR{T}, args...; kwargs...) =
	_broadcast(T, fnbasesweep(fn, d), fn, d, args...; kwargs...)
#Data reducing (DataHR{DataF1/Number})
broadcast{T<:Number}(::CastTypeRed1{Number,1}, fn::Function, d::DataHR{T}, args...; kwargs...) =
	_broadcast(T, fnbasesweep(fn, d), fn, d, args...; kwargs...)
function broadcast(::CastTypeRed1{Number,1}, fn::Function, d::DataHR{DataF1}, args...; kwargs...)
	TR = promote_type(findytypes(d.subsets)...) #TODO: Better way?
	_broadcast(TR, fnbasesweep(fn, d), fn, d, args...; kwargs...)
end

#Broadcast functions capable of operating only on a dataF1 value:
#-------------------------------------------------------------------------------
#DataF1
function broadcast(::CastType1{DataF1,1}, fn::Function, d, args...; kwargs...)
	d = ensure_coll_DataF1(fn, d) #Collapse DataHR{Number}  => DataHR{DataF1}
	_broadcast(DataF1, fnbasesweep(fn, d), fn, d, args...; kwargs...)
end
#Expects DataF1 @ arg #2:
function broadcast(::CastType1{DataF1,2}, fn::Function, dany1, d, args...; kwargs...)
	d = ensure_coll_DataF1(fn, d) #Collapse DataHR{Number}  => DataHR{DataF1}
	_broadcast(DataF1, fnbasesweep(fn, d), fn, dany1, d, args...; kwargs...)
end
#Data reducing (DataF1)
function broadcast(::CastTypeRed1{DataF1,1}, fn::Function, d, args...; kwargs...)
	d = ensure_coll_DataF1(fn, d) #Collapse DataHR{Number}  => DataHR{DataF1}
	TR = promote_type(findytypes(d.subsets)...) #TODO: Better way?
	_broadcast(TR, fnbasesweep(fn, d), fn, d, args...; kwargs...)
end


#Find base sweep for a 2-argument broadcast
#-------------------------------------------------------------------------------
function fnbasesweep(fn::Function, d1, d2)
	local s
	try
		s = basesweep(d1,d2)
	catch
		t1 = typeof(d1); t2 = typeof(d2)
		msg = "No signature found for $fn($t1, $t2, ...)"
		throw(ArgumentError(msg))
	end
end

#Ensure collection is composed of DataF1 (ex: DataHR{DataF1}):
#Collapses outer-most dimension of DataHR{Number} to a DataHR{DataF1} value, if necessary
#-------------------------------------------------------------------------------
function ensure_coll_DataF1(fn::Function, d1, d2)
	try
		d1 = ensure_coll_DataF1(fn, d1)
		d2 = ensure_coll_DataF1(fn, d2)
	catch
		t1 = typeof(d1); t2 = typeof(d2)
		msg = "No signature found for $fn($t1, $t2, ...)"
		throw(ArgumentError(msg))
	end
	return tuple(d1, d2)
end

#Broadcast functions capable of operating directly on base types (Number, Number):
#-------------------------------------------------------------------------------
#DataHR{DataF1/Number} & DataHR{DataF1/Number}:
function broadcast{T1,T2}(::CastType2{Number,1,Number,2}, fn::Function,
	d1::DataHR{T1}, d2::DataHR{T2}, args...; kwargs...)
	_broadcast(promote_type(T1,T2), fnbasesweep(fn, d1, d2), fn, d1, d2, args...; kwargs...)
end
#DataHR{DataF1/Number} & DataF1/Number:
function broadcast{T1,T2<:DF1_Num}(::CastType2{Number,1,Number,2}, fn::Function,
	d1::DataHR{T1}, d2::T2, args...; kwargs...)
	_broadcast(promote_type(T1,T2), fnbasesweep(fn, d1, d2), fn, d1, d2, args...; kwargs...)
end
#DataF1/Number & DataHR{DataF1/Number}:
function broadcast{T1<:DF1_Num,T2}(::CastType2{Number,1,Number,2}, fn::Function,
	d1::T1, d2::DataHR{T2}, args...; kwargs...)
	_broadcast(promote_type(T1,T2), fnbasesweep(fn, d1, d2), fn, d1, d2, args...; kwargs...)
end

#Broadcast functions capable of operating only on a dataF1 value:
#-------------------------------------------------------------------------------
#DataF1, DataF1
function broadcast(::CastType2{DataF1,1,DataF1,2}, fn::Function, d1, d2, args...; kwargs...)
	(d1, d2) = ensure_coll_DataF1(fn, d1, d2) #Collapse DataHR{Number}  => DataHR{DataF1}
	_broadcast(DataF1, fnbasesweep(fn, d1, d2), fn, d1, d2, args...; kwargs...)
end
#DataF1, DataF1 @ arg 2/3:
function broadcast(::CastType2{DataF1,2,DataF1,3}, fn::Function, dany1, d1, d2, args...; kwargs...)
	(d1, d2) = ensure_coll_DataF1(fn, d1, d2) #Collapse DataHR{Number}  => DataHR{DataF1}
	_broadcast(DataF1, fnbasesweep(fn, d1, d2), fn, dany1, d1, d2, args...; kwargs...)
end
#Data reducing (DataF1, DataF1)
function broadcast(::CastTypeRed2{DataF1,1,DataF1,2}, fn::Function, d1, d2, args...; kwargs...)
	(d1, d2) = ensure_coll_DataF1(fn, d1, d2) #Collapse DataHR{Number}  => DataHR{DataF1}
	TR = promote_type(findytypes(d1.subsets)...,findytypes(d1.subsets)...) #TODO: Better way?
	_broadcast(DataF1, fnbasesweep(fn, d1, d2), fn, d1, d2, args...; kwargs...)
end


#Last Line
