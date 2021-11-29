using Gridap.Arrays
using SparseArrays

# TODO: under construction for longest side in non-uniform mesh
function sort_elem_for_labeling(node::Vector, elem::Matrix)
    #@show node[elem[:,3],1]-node[elem[:,2],1].^2
    #+[node[elem[:,3],2]-node[elem[:,2],2]].ˆ2
    #edgelength[:,2]=[node[elem[:,1],1]-node[elem[:,3],1]].^2
    #+[node[elem[:,1],2]-node[elem[:,3],2]].ˆ2
    #edgelength[:,3]=[node[elem[:,3],1]-node[elem[:,2],1]].^2
    #+[node[elem[:,3],2]-node[elem[:,2],2]].ˆ2
    #(temp,I)=max(edgelength,[],2)
    #elem[[I==2],[1 2 3]]=elem[[I==2], [2 3 1]]
    #elem[[I==3],[1 2 3]]=elem[[I==3], [3 1 2]]
end

function setup_markers(NT, NE, node, elem, d2p, dualedge, θ)
    # No estimator for now
    η = fill(1, NT)
    @show total = sum(η)
    @show ix = sortperm(-η)
    current = 0
    @show NE
    marker = zeros(Int32, NE,1)
    @show d2p
    @show dualedge
    for t = 1:NT
        @show t
        if (current > θ*total)
            break
        end
        index=1
        ct=ix[t]
        while (index==1)
            #@show elem[ct,2],elem[ct,3]
            @show base = d2p[elem[ct,2],elem[ct,3]]
            if marker[base]>0
                @show marker[base]
                index=0
            else
                current = current + η[ct];
                N = size(node,1)+1;
                marker[d2p[elem[ct,2],elem[ct,3]]] = N;
                node = [node; get_midpoint(node[elem[ct,[2 3],:]])]
                @show elem[ct,3],elem[ct,2]
                @show ct = dualedge[elem[ct,2],elem[ct,3]]
                if ct==0
                    index=0
                end
            end
        end
    end
    @show node
    @show marker
end

function divide(elem,t,p)
    #elem[size(elem,1)+1,:]=[p[4],p[3],p[1]]
    elem = [elem; [p[4] p[3] p[1]]]
    elem[t,:]=[p[4] p[1] p[2]]
    elem
end

function refine(NE, d2p, elem)
    # TODO: for now everything marked for refinement
    marker = fill(1, NE)
    for t=1:2
        @show t
        @show elem
        base=d2p[elem[t,2],elem[t,3]]
        if (marker[base]>0)
            p = vcat(elem[t,:], marker[base])
            elem=divide(elem,t,p)
            left=d2p[p[1],p[2]]; right=d2p[p[3],p[1]]
            if (marker[right]>0)
                elem=divide(elem,size(elem,1), [p[4],p[3],p[1],marker[right]])
            end
            if (marker[left]>0)
                elem=divide(elem,t,[p[4],p[1],p[2],marker[left]])
            end
        end
    end
end

function build_edges(elem::Matrix{T}) where {T <: Integer}
    edge = [elem[:,[1,2]]; elem[:,[1,3]]; elem[:,[2,3]]]
    unique(sort!(edge, dims=2), dims=1)
end

function build_directed_dualedge(elem::Matrix{Ti}, N::T, NT::T) where {Ti, T <: Integer}
    dualedge = spzeros(Int64, N, N)
    for t=1:NT
        dualedge[elem[t,1],elem[t,2]]=t
        dualedge[elem[t,2],elem[t,3]]=t
        dualedge[elem[t,3],elem[t,1]]=t
    end
    #@show nnz(dualedge)
    dualedge
end

function dual_to_primal(edge::Matrix{Ti}, NE::T, N::T) where {Ti, T <: Integer}
    d2p = spzeros(Int64, N, N)
    for k=1:NE
        i=edge[k,1]
        j=edge[k,2]
        d2p[i,j]=k
        d2p[j,i]=k
    end
    d2p
end

function test_against_top(face::Matrix{Ti}, top::GridTopology, d::T) where {Ti, T <: Integer}
    face_vec = [face[i,:] for i in 1:size(face,1)]
    face_top = get_faces(top, d, 0)
    issetequal_bitvec = issetequal.(sort(face_vec), sort(face_top))
    @assert all(issetequal_bitvec)
end

"""
node_coords == node, cell_node_ids == elem in Long Chen's notation
"""
function newest_vertex_bisection(top::GridTopology, node_coords::Vector, cell_node_ids::Matrix)
    N = size(node_coords, 1)
    #@show elem = vcat(cell_node_ids'...)
    elem = cell_node_ids
    NT = size(elem, 1)
    test_against_top(elem, top, 2)
    @show edge = build_edges(elem)
    NE = size(edge, 1)
    dualedge = build_directed_dualedge(elem, N, NT)
    d2p = dual_to_primal(edge, NE, N)
    test_against_top(edge, top, 1)
    # TODO: Mark largest edge
    #sort_elem_for_labeling(node_coords, elem)
    setup_markers(NT, NE, node_coords, elem, d2p, dualedge, 1)
    #refine(NE, d2p, elem)
    node_coords, cell_node_ids
end


function get_midpoint(ngon)
    return sum(ngon)/length(ngon)
end

function Base.atan(v::VectorValue{2, T}) where {T <: AbstractFloat}
    atan(v[2], v[1])
end

function sort_ccw(cell_coords)
    midpoint = get_midpoint(cell_coords)
    offset_coords = cell_coords .- midpoint
    #@show midpoint_zero = get_midpoint(offset_coords)
    sorted_perm = sortperm(offset_coords, by=atan)
    #@show offset_coords[sorted_perm] .+ midpoint
    return sorted_perm
end


function sort_cell_node_ids_ccw(cell_node_ids, node_coords)
    cell_node_ids_ccw = vcat(cell_node_ids'...)
    #@show cell_node_ids_ccw
    for (i, cell) in enumerate(cell_node_ids)
        cell_coords = node_coords[cell]
        perm = sort_ccw(cell_coords)
        cell_node_ids_ccw[i,:] = cell[perm]
    end
    cell_node_ids_ccw
end

# setp 1
function newest_vertex_bisection(grid::Grid, top::GridTopology, cell_mask::AbstractVector{<:Bool})
    #get_faces(top
    #@show cell_coords = get_cell_coordinates(grid)
    node_coords = get_node_coordinates(grid)
    cell_node_ids = get_cell_node_ids(grid)
    cell_node_ids_ccw = sort_cell_node_ids_ccw(cell_node_ids, node_coords)
    # TODO: Modify node__coords and cell_node_ids
    typeof(node_coords)
    newest_vertex_bisection(top, node_coords, cell_node_ids_ccw)
    reffes = get_reffes(grid)
    cell_types = get_cell_type(grid)
    UnstructuredGrid(node_coords, cell_node_ids, reffes, cell_types)
    #@show new_val = VectorValue{2, Float64}(1.5, 1.5, 1.5)
    #new_val = LazyArray([VectorValue(1.5, 1.5), VectorValue(1.2, 2), VectorValue(3.2, 3.1)])
    #@show new_val = lazy_map(get_midpoint, cell_coords[1:2], 0*cell_coords[1:2])
    #@show new_val = lazy_map(get_midpoint, cell_coords[1:2], 0*cell_coords[1:2])
    #cell_coords = lazy_append(cell_coords, new_val)
  # tod
  #ref_grid
end

# step 2
function newest_vertex_bisection(model::DiscreteModel,cell_mask::AbstractVector{<:Bool})
  grid  = get_grid(model)
  top = get_grid_topology(model)
  ref_grid = newest_vertex_bisection(grid, top, cell_mask)
  #ref_topo = GridTopology(grid)
  #labels = get_face_labelling(model)
  #ref_labels = # Compute them from the original labels (This is perhaps the most tedious part)
  #ref_model = DiscreteModel(ref_grid,ref_topo,ref_labels)
  #ref_model
end
