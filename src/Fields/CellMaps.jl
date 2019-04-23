module CellMaps

using Numa.Maps
using Numa.Maps: range_size

using Numa.Helpers
using Numa.CellValues
using Numa.CellValues: CachedArray
using Numa.CellValues: setsize!

import Base: iterate
import Base: length
import Base: eltype
import Base: size
import Base: getindex, setindex!

import Numa: evaluate, gradient
import Numa.CellValues: cellsize
# @santiagobadia :  To be put in Numa base

# Iterable cell Maps
"""
Abstract object that traverses a set of cells and at every cell returns a
`Map{S,M,T,N}`
"""
abstract type IterCellMap{S,M,T,N} end
# @santiagobadia : Why don't put the result type R as template parameter,
# as for IndexCellMap ?

function iterate(::IterCellMap{S,M,T,N})::Union{Nothing,Tuple{Map{S,M,T,N},Any}} where {S,M,T,N}
  @abstractmethod
end

function iterate(::IterCellMap{S,M,T,N},state)::Union{Nothing,Tuple{Map{S,M,T,N},Any}} where {S,M,T,N}
  @abstractmethod
end

eltype(::Type{C}) where C <: IterCellMap{S,M,T,N} where {S,M,T,N} = Map{S,M,T,N}
# @santiagobadia :  I think this method must be overriden, better in CellMap?

# Indexable cell Maps

abstract type IndexCellMap{S,M,T,N,R<:Map{S,M,T,N}} <: AbstractVector{R} end

function getindex(::IndexCellMap{S,M,T,N,R}, ::Int)::R where {S,M,T,N,R}
  @abstractmethod
end

lastindex(x::IndexCellMap) = x[length(x)]

# Cell Maps
"""
Abstract object that for a given cell index returns a `Map{S,M,T,N}`
"""
const CellMap{S,M,T,N} = Union{IterCellMap{S,M,T,N},IndexCellMap{S,M,T,N}}
# santiagobadia : Problem if IterCellMap and IndexCellMap not same template types?
# Is this correct? IndexCellMap{S,M,T,N} when IndexCellMap{S,M,T,N,R}?

length(::CellMap)::Int = @abstractmethod

cellsize(::CellMap) = @abstractmethod
# @santiagobadia : What should I put here?

function Base.show(io::IO,self::CellMap)
  for (i, a) in enumerate(self)
    println(io,"$i -> $a")
  end
end
# @santiagobadia : Using the same as CellArray and CellValue

# Concrete structs

"""
Cell-wise map created from a `Map` of concrete type `R`
"""
struct ConstantCellMap{S,M,T,N,R <: Map{S,M,T,N}} <: IndexCellMap{S,M,T,N,R}
  map::R
  num_cells::Int
end

size(this::ConstantCellMap) = (this.num_cells,)

length(this::ConstantCellMap) = this.num_cells

"""
Evaluate a `ConstantCellMap` on a set of points represented with a
`CellArray{S,M}`
"""
function evaluate(self::ConstantCellMap{S,M,T,N,R},
  points::CellArray{S,M}) where {S,M,T,N,R}
  IterConstantCellMapValues(self.map,points)
end

"""
Computes the gradient of a `ConstantCellMap`
"""
function gradient(self::ConstantCellMap)
  gradfield = gradient(self.field)
  ConstantCellMap(gradfield)
end

getindex(this::ConstantCellMap, i::Int) = this.map

firstindex(this::ConstantCellMap) = this.map

lastindex(this::ConstantCellMap) = this.map

# CellMapValues

"""
Object that represents the (lazy) evaluation of a `CellMap{S,M,T,N}` on a set
of points represented with a `CellArray{S,M,T,N}`. The result is a sub-type of
`IterCellArray{T,N}`. Its template parameters are `{S,M,T,N,A,B}`, where `A`
stands for the concrete sub-type of `Map{S,M,T,N}` and `B` stands for the
concrete sub-type of `CellArray{S,M}`
"""
struct IterConstantCellMapValues{S,M,T,N,A<:Map{S,M,T,N},B<:CellArray{S,M}} <: IterCellArray{T,N}
  map::A
  cellpoints::B
end

function cellsize(this::IterConstantCellMapValues)
  return (range_size(this.map)..., cellsize(this.cellpoints)...)
end

@inline function Base.iterate(this::IterConstantCellMapValues{S,M,T,N,A,B}) where {S,M,T,N,A,B}
  R = Base._return_type(evaluate,Tuple{A,B})
  # @santiagobadia : Here is the problem...
  #  a field should be S,0,T,0 and after evaluation, it would take e.g., S,1
  # and return T,1... i.e. T,N+1
  u = Array{T,N}(undef, cellsize(this))
  v = CachedArray(u)
  anext = iterate(this.cellpoints)
  if anext === nothing; return nothing end
  iteratekernel(this,anext,v)
end

@inline function Base.iterate(this::IterConstantCellMapValues{S,M,T,N,A,B},state) where {S,M,T,N,A,B}
  v, astate = state
  anext = iterate(this.cellpoints,astate)
  if anext === nothing; return nothing end
  iteratekernel(this,anext,v)
end

function iteratekernel(this::IterConstantCellMapValues,next,v)
  a, astate = next
  vsize = size(a)
  setsize!(v,vsize)
  evaluate!(this.map,a,v)
  state = (v, astate)
  (v, state)
  # @santiagobadia : I don't understand the last step, I have copied from a
  # similar situation in other part of the code...
end

const ConstantCellMapValues = IterConstantCellMapValues

end #module CellMaps
