#MDDatasets DataLL defninitions
#-------------------------------------------------------------------------------

#==Main types
===============================================================================#

#Hyper-rectangle -representation of data:
#-------------------------------------------------------------------------------
type DataHR{T} <: DataMD
	sweeps::Vector{PSweep}
	elem::Array{T}

	function DataHR{TA,N}(sweeps::Vector{PSweep}, elem::Array{TA,N})
		if !elemallowed(DataMD, eltype(elem))
			msg = "Can only create DataHR{T} for T ∈ {DataF1, DataFloat, DataInt, DataComplex}"
			throw(ArgumentError(msg))
		elseif ndims(DataHR, sweeps) != N
			throw(ArgumentError("Number of sweeps must match dimensionality of elem"))
		end
		return new(sweeps, elem)
	end
end

#Shorthand (because default (non-parameterized) constructor was overwritten):
DataHR{T,N}(sweeps::Vector{PSweep}, a::Array{T,N}) = DataHR{T}(sweeps, a)

#Construct DataHR from Vector{PSweep}:
call{T}(::Type{DataHR{T}}, sweeps::Vector{PSweep}) = DataHR{T}(sweeps, Array{T}(size(DataHR, sweeps)...))

#Construct DataHR{DataF1} from DataHR{Number}
#Collapse inner-most sweep (last dimension), by default:
#TODO: use convert(...) instead?
function call{T<:Number}(::Type{DataHR{DataF1}}, d::DataHR{T})
	sweeps = d.sweeps[1:end-1]
	x = d.sweeps[end].v
	result = DataHR{DataF1}(sweeps) #Construct empty results
	_sub = length(d.sweeps)>1?collect(subscripts(result)):[tuple()]
	for inds in _sub
		y = d.elem[inds...,:]
		result.elem[inds...] = DataF1(x, reshape(y, length(y)))
	end
	return result
end

#Relay function, so people can blindly convert to DataHR{DataF1} using any DataHR:
call(::Type{DataHR{DataF1}}, d::DataHR{DataF1}) = d


#==Type promotions
===============================================================================#
Base.promote_rule{T1<:DataHR, T2<:Number}(::Type{T1}, ::Type{T2}) = DataHR


#==Accessor functions
===============================================================================#
#Compute the size of a DataHR array from a Vector{PSweep}:
function Base.size(::Type{DataHR}, sweeps::Vector{PSweep})
	dims = Int[]
	for s in sweeps
		push!(dims, length(s.v))
	end
	if 0 == length(dims) #Without sweeps, you can still have a single subset
		push!(dims, 1)
	end
	return tuple(dims...)
end

#Returns the dimension corresponding to the given string:
function dimension(::Type{DataHR}, sweeps::Vector{PSweep}, id::AbstractString)
	dim = findfirst((s)->(id==s.id), sweeps)
	@assert(dim>0, "Sweep not found: $id.")
	return dim
end
dimension(d::DataHR, id::AbstractString) = dimension(DataHR, d.sweeps, id)

#Returns an element subscripts iterator for a DataHR corresponding to Vector{PSweep}.
function subscripts(::Type{DataHR}, sweeps::Vector{PSweep})
	sz = size(DataHR, sweeps)
	return SubscriptIterator(sz, prod(sz))
end
subscripts(d::DataHR) = subscripts(d.elem)

#Dimensionality of DataHR array:
Base.ndims(::Type{DataHR}, sweeps::Vector{PSweep}) = max(1, length(sweeps))
Base.ndims(d::DataHR) = ndims(DataHR, d.sweeps)

#Obtain sweep info
#-------------------------------------------------------------------------------
sweeps(d::DataHR) = d.sweeps
sweep(d::DataHR, dim::Int) = d.sweeps[dim].v
sweep(d::DataHR, dim::AbstractString) = d.sweeps[dim].v

#Returns parameter sweep coordinates corresponding to given subscript:
function coordinates(d::DataHR, subscr::Tuple=0)
	result = []
	if length(d.sweeps) > 0
		for i in 1:length(subscr)
			push!(result, sweep(d, i)[subscr[i]])
		end
	end
	return result
end


#==Data generation
===============================================================================#
#Generate a DataHR object containing the value of a given swept parameter:
function parameter(::Type{DataHR}, sweeps::Vector{PSweep}, sweepno::Int)
	sw = sweeps[sweepno].v #Sweep of interest
	T = eltype(sw)
	result = DataHR{T}(sweeps)
	for inds in subscripts(result)
		result.elem[inds...] = sw[inds[sweepno]]
	end
	return result
end
parameter(::Type{DataHR}, sweeps::Vector{PSweep}, id::AbstractString) =
	parameter(DataHR, sweeps, dimension(DataHR, sweeps, id))
parameter(d::DataHR, id::AbstractString) = parameter(DataHR, d.sweeps, id)


#==Dataset reductions
===============================================================================#

#Like sub(A, inds...), but with DataHR:
function getsubarray{T}(d::DataHR{T}, inds...)
	sweeps = PSweep[]
	idx = 1
	for rng in inds
		sw = d.sweeps[idx]

		#Only provide a sweep if user selects a range of more than one element:
		addsweep = Colon == typeof(rng) || length(rng)>1
		if addsweep
			push!(sweeps, PSweep(sw.id, sw.v[rng]))
		end
		idx +=1
	end
	return DataHR{T}(sweeps, reshape(sub(d.elem, inds...), size(DataHR, sweeps)))
end

#sub(DataHR, inds...), using key/value pairs:
function getsubarraykw{T}(d::DataHR{T}; kwargs...)
	sweeps = PSweep[]
	indlist = Vector{Int}[]
	for sweep in d.sweeps
		keepsweep = true
		arg = getkwarg(kwargs, symbol(sweep.id))
		if arg != nothing
			inds = indices(sweep, arg)
			push!(indlist, inds)
			if length(inds) > 1
				keepsweep = false
				push!(sweeps, PSweep(sweep.id, sweep.v[inds...]))
			end
		else #Keep sweep untouched:
			push!(indlist, 1:length(sweep.v))
			push!(sweeps, sweep)
		end
	end
	return DataHR{T}(sweeps, reshape(sub(d.elem, indlist...), size(DataHR, sweeps)))
end

function Base.sub{T}(d::DataHR{T}, args...; kwargs...)
	if length(kwargs) > 0
		return getsubarraykw(d, args...; kwargs...)
	else
		return getsubarray(d, args...)
	end
end


#==User-friendly show functions
===============================================================================#
#Also changes string():
Base.print(io::IO, ::Type{DataHR{DataF1}}) = print(io, "DataHR{DataF1}")
Base.print(io::IO, ::Type{DataHR{DataFloat}}) = print(io, "DataHR{DataFloat}")
Base.print(io::IO, ::Type{DataHR{DataInt}}) = print(io, "DataHR{DataInt}")
Base.print(io::IO, ::Type{DataHR{DataComplex}}) = print(io, "DataHR{DataComplex}")

function Base.show(io::IO, ds::DataHR)
	szstr = string(size(ds.elem))
	typestr = string(typeof(ds))
	print(io, "$typestr$szstr[\n")
	for inds in subscripts(ds)
		if isdefined(ds.elem, inds...)
			subset = ds.elem[inds...]
			print(io, " $inds: "); show(io, subset); println(io)
		else
			println(io, " $inds: UNDEFINED")
		end
	end
	print(io, "]\n")
end

function Base.show{T<:Number}(io::IO, ds::DataHR{T})
	szstr = string(size(ds.elem))
	typestr = string(typeof(ds))
	print(io, "$typestr$szstr:\n")
	print(io, ds.elem)
end

#Last line