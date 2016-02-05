#MDDatasets: Measure binary signals
#-------------------------------------------------------------------------------
#=NOTE:
 - Many functions make use of "cross" functions.
 - Naming assumes x-values are "time".
=#


#==Helper functions
===============================================================================#

function _buildckvector(ctx::ASCIIString, tstart::Real, tstop::Real, tsample::Real)
	if isinf(tstart)
		msg = "$ctx: Must specify finite clock start time."
		throw(ArgumentError(msg))
	end

	return collect(tstart:tsample:tstop)
end


#==Main functions
===============================================================================#

#measdelay: Measure delay between crossing events of two signals:
#-------------------------------------------------------------------------------
function measdelay(dref::DataF1, dmain::DataF1; nmax::Integer=0,
	tstart_ref::Real=-Inf, tstart_main::Real=-Inf,
	xing1::CrossType=CrossType(), xing2::CrossType=CrossType())

	xref = xcross(dref, nmax=nmax, tstart=tstart_ref, allow=xing1)
	xmain = xcross(dmain, nmax=nmax, tstart=tstart_main, allow=xing2)
	npts = min(length(xref), length(xmain))
	delay = xmain.y[1:npts] - xref.y[1:npts]
	x = xref.x[1:npts]
	return DataF1(x, delay)
end
function measdelay(::DS{:event}, dref::DataF1, dmain::DataF1, args...; kwargs...)
	d = measdelay(dref, dmain, args...;kwargs...)
	return DataF1(collect(1:length(d.x)), d.y)
end

#measck2q: Measure clock-to-Q delay
#-------------------------------------------------------------------------------

#=_measck2q: Core algorithm to measure clock-to-Q delay
Inputs
   delaymin: Minimum circuit delay used to align clock & q edges
=#
function _measck2q(xingck::Vector, xingq::Vector, delaymin::Real)
	xq = copy(xingq) - delaymin
	qlen = length(xq) #Maximum # of q-events
	x = copy(xingq) #Allocate space for delay starts
	Δ = copy(xingq) #Allocate space for delays
	cklen = length(xingck)
	npts = 0
	stop = false


	if qlen < 1 || cklen < 2 #Need to know if q is between 2 ck events
		xt = eltype(x)
		return DataF1(Vector{xt}(), Vector{xt}())
	end

	iq = 1
	ick = 1
	xqi = xq[iq]
	xcki = xingck[ick]
	xcki1 = xingck[ick+1]
	while xcki > xqi #Find first q event after first ck event.
		iq += 1
		xqi = xq[iq]
	end

	while iq <= qlen
		xqi = xq[iq]
		#Find clock triggering q event:
		while xcki1 <= xqi
			ick +=1
			if ick < cklen
				xcki = xingck[ick]
				xcki1 = xingck[ick+1]
			else #Not sure if this xqi corresponds to xcki
				stop = true
				break
			end
		end
		if stop; break; end

		#Compute delay (re-insert removed minimum delay):
		npts += 1
		x[npts] = xcki
		Δ[npts] = xqi - xcki + delaymin

		#Consider next q transition:
		iq += 1
	end

	return DataF1(x[1:npts], Δ[1:npts])
end

#=Measure clock-to-Q delay with non-ideal clock.
Inputs
   delaymin: Minimum circuit delay used to align clock & q edges
             Needed when delay is larger than time between ck events.
=#
function measck2q(ck::DataF1, q::DataF1; delaymin::Real=0,
	tstart_ck::Real=-Inf, tstart_q::Real=-Inf,
	xing_ck::CrossType=CrossType(), xing_q::CrossType=CrossType())

	xingck = xcross(ck, tstart=tstart_ck, allow=xing_ck)
	xingq = xcross(q, tstart=tstart_q, allow=xing_q)
	return _measck2q(xingck.x, xingq.x, delaymin)
end
#Measure clock-to-Q delay an ideal sampling clock (tsample).
function measck2q(q::DataF1, tsample::Real; delaymin::Real=0,
	tstart_ck::Real=-Inf, tstart_q::Real=-Inf,
	xing_q::CrossType=CrossType())

	xingck = _buildckvector("measck2q", tstart_ck, (q.x[end]+tsample), tsample)
	xingq = xcross(q, tstart=tstart_q, allow=xing_q)
	return _measck2q(xingck, xingq.x, delaymin)
end

function _getskewstats(Δr::DataMD, Δf::DataMD)
	μΔr = mean(Δr)
	μΔf = mean(Δf)
	μΔ = (μΔr + μΔf) / 2
	Δmax = max(maximum(Δr), maximum(Δf))
	Δmin = min(minimum(Δr), minimum(Δf))

	#Use ASCII symbols to avoid issues with UTF8:
	return Dict{Symbol, DataMD}(
		:mean_delrise => μΔr,
		:min_delrise => minimum(Δr),
		:max_delrise => maximum(Δr),
		:mean_delfall => μΔf,
		:min_delfall => minimum(Δf),
		:max_delfall => maximum(Δf),
		:mean_del => μΔ,
		:mean_skew => μΔf-μΔr,
		:max_skew => Δmax - Δmin,
		:std_delrise => std(Δr),
		:std_delfall => std(Δf),
	)
end

#Measure delay skew between a signal and its reference
#returns various statistics.
function measskew(ref::DataMD, sig::DataMD;
	tstart_ref=-Inf, tstart_sig=-Inf)
	xrise = CrossType(:rise)
	xfall = CrossType(:fall)

	Δr = measdelay(ref, sig, tstart_ref=tstart_ref, tstart_main=tstart_sig,
		xing1=xrise, xing2=xrise)
	Δf = measdelay(ref, sig, tstart_ref=tstart_ref, tstart_main=tstart_sig,
		xing1=xfall, xing2=xfall)
	return _getskewstats(Δr, Δf)
end

#Last line
