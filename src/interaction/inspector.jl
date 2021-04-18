# checklist:
#=
- scatter 2D :) (ignores zoom scaling)
- scatter 3D :) (ignores zoom scaling)
- LScene Axis :(
- lines 2D :)
- lines 3D :)
- meshscatter 2D :) 
- meshscatter 3D :) (bad text position - maybe static?)
- linesegments 3D :) 
- linesegments 2D :)
- heatmap :)
- barplot :)
- mesh :) (bad text position - maybe static?)
=#


### indicator data -> string
########################################

position2string(p::Point2f0) = @sprintf("x: %0.6f\ny: %0.6f", p[1], p[2])
position2string(p::Point3f0) = @sprintf("x: %0.6f\ny: %0.6f\nz: %0.6f", p[1], p[2], p[3])

function bbox2string(bbox::Rect3D)
    p = origin(bbox)
    w = widths(bbox)
    @sprintf(
        "Bounding Box:\nx: (%0.3f, %0.3f)\ny: (%0.3f, %0.3f)\nz: (%0.3f, %0.3f)",
        p[1], w[1], p[2], w[2], p[3], w[3]
    )
end


### dealing with markersize and rotations
########################################

to_scale(f::AbstractFloat, idx) = Vec3f0(f)
to_scale(v::Vec2f0, idx) = Vec3f0(v[1], v[2], 1)
to_scale(v::Vec3f0, idx) = v
to_scale(v::Vector, idx) = to_scale(v[idx], idx)

to_rotation(x, idx) = x
to_rotation(x::Vector, idx) = x[idx]


### Selecting a point on a nearby line
########################################

function closest_point_on_line(p0::Point2f0, p1::Point2f0, r::Point2f0)
    # This only works in 2D
    AP = P .- A; AB = B .- A
    A .+ AB * dot(AP, AB) / dot(AB, AB)
end

function view_ray(scene)
    inv_projview = inv(camera(scene).projectionview[])
    view_ray(inv_projview, events(scene).mouseposition[], pixelarea(scene)[])
end
function view_ray(inv_view_proj, mpos, area::Rect2D)
    # This figures out the camera view direction from the projectionview matrix (?)
    # and computes a ray from a near and a far point.
    # Based on ComputeCameraRay from ImGuizmo
    mp = 2f0 .* (mpos .- minimum(area)) ./ widths(area) .- 1f0
    v = inv_view_proj * Vec4f0(0, 0, -10, 1)
    reversed = v[3] < v[4]
    near = reversed ? 1f0 - 1e-6 : 0f0
    far = reversed ? 0f0 : 1f0 - 1e-6

    origin = inv_view_proj * Vec4f0(mp[1], mp[2], near, 1f0)
    origin = origin[SOneTo(3)] ./ origin[4]

    p = inv_view_proj * Vec4f0(mp[1], mp[2], far, 1f0)
    p = p[SOneTo(3)] ./ p[4]

    dir = normalize(p - origin)
    return origin, dir
end


# These work in 2D and 3D
function closest_point_on_line(A, B, origin, dir)
    closest_point_on_line(
        to_ndim(Point3f0, A, 0),
        to_ndim(Point3f0, B, 0),
        to_ndim(Point3f0, origin, 0),
        to_ndim(Vec3f0, dir, 0)
    )
end
function closest_point_on_line(A::Point3f0, B::Point3f0, origin::Point3f0, dir::Vec3f0)
    # See:
    # https://en.wikipedia.org/wiki/Line%E2%80%93plane_intersection
    u_AB = normalize(B .- A)
    u_dir = normalize(dir)
    u_perp = normalize(cross(u_dir, u_AB))
    # e_RD, e_perp defines a plane with normal n
    n = normalize(cross(u_dir, u_perp))
    t = dot(origin .- A, n) / dot(u_AB, n)
    A .+ t * u_AB
end


### Heatmap positions/indices
########################################

pos2index(x, r, N) = clamp(ceil(Int, N * (x - minimum(r)) / (maximum(r) - minimum(r))), 1, N)
index2pos(i, r, N) = minimum(r) + (maximum(r) - minimum(r)) * (i) / (N)


### Getting text bounding boxes to draw backgrounds
########################################

function Bbox_from_glyphlayout(gl)
    bbox = FRect3D(
        gl.origins[1] .+ Vec3f0(origin(gl.bboxes[1])..., 0), 
        Vec3f0(widths(gl.bboxes[1])..., 0)
    )
    for (o, bb) in zip(gl.origins[2:end], gl.bboxes[2:end])
        bbox2 = FRect3D(o .+ Vec3f0(origin(bb)..., 0), Vec3f0(widths(bb)..., 0))
        bbox = union(bbox, bbox2)
    end
    bbox
end

#=
function text2worldbbox(p::Text)
    if p._glyphlayout[] isa Vector
        @info "TODO"
    else
        if cameracontrols(p.parent) isa PixelCamera
            # This will probably end up being what we use...
            map(p._glyphlayout, p.position) do gl, pos
                FRect2D(Bbox_from_glyphlayout(gl)) + Vec2f0(pos[1], pos[2])
            end
        else 
            map(p._glyphlayout, p.position, camera(p.parent).projectionview, pixelarea(p.parent)) do gl, pos, pv, area
                px_pos = AbstractPlotting.project(pv, Vec2f0(widths(area)), to_ndim(Point3f0, pos, 0))
                px_bbox = Bbox_from_glyphlayout(gl) + to_ndim(Vec3f0, px_pos, 0)
                px_bbox = px_bbox - Vec3f0(0.5widths(area)..., 0)
                px_bbox = FRect3D(
                    2 .* origin(px_bbox) ./ Vec3f0(widths(area)..., 1),
                    2 .* widths(px_bbox) ./ Vec3f0(widths(area)..., 1)
                )
                ps = unique(coordinates(px_bbox))
                inv_pv = inv(pv)
                world_ps = map(ps) do p
                    proj = inv_pv * Vec4f0(p..., 1)
                    proj[SOneTo(3)] / proj[4]
                end
                minx, maxx = extrema(getindex.(world_ps, (1,)))
                miny, maxy = extrema(getindex.(world_ps, (2,)))
                minz, maxz = extrema(getindex.(world_ps, (3,)))
                world_bbox = FRect3D(Point3f0(minx, miny, minz), Vec3f0(maxx-minx, maxy-miny, maxz-minz))
                world_bbox
            end
        end
    end
end
function text2pixelbbox(p::Text)
    if p._glyphlayout[] isa Vector
        @info "TODO"
    else
        map(Bbox_from_glyphlayout, p._glyphlayout)
    end
end
=#


## Shifted projection
########################################

function shift_project(scene, pos)
    project(
        camera(scene).projectionview[],
        Vec2f0(widths(pixelarea(scene)[])),
        pos
    ) .+ Vec2f0(origin(pixelarea(scene)[]))
end



################################################################################
### Base pixel-space plot for Indicator
################################################################################


# TODO
# Could probably use some more attributes
@recipe(_Inspector, x) do scene
    Attributes(
        # Text
        display_text = " ",
        text_position = Point2f0(0),
        text_align = (:left, :bottom),

        # Background
        background_color = :orange,
        outline_color = :lightblue,

        # pixel BBox/indicator
        color = :red,
        bbox2D = FRect2D(Vec2f0(0,0), Vec2f0(1,1)),
        px_bbox_visible = true,
        bbox3D = FRect3D(Vec3f0(0,0,0), Vec3f0(1,1,1)),
        bbox_visible = true,

        # general
        position = Point3f0(0),
        proj_position = Point2f0(0),
        root_px_projection = Mat4f0(1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1),
        model = Mat4f0(1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1),
        depth = 1e3,
        visible = true
    )
end

function plot!(plot::_Inspector)
    @extract plot (
        display_text, text_position, text_align,
        background_color, outline_color,
        bbox2D, px_bbox_visible,
        bbox3D, bbox_visible,
        color,
        position, proj_position, 
        root_px_projection, model, 
        depth, visible
    )
    _text = text!(plot, display_text, 
        position = text_position, visible = visible, align = text_align,
        show_axis = false
    )

    id = Mat4f0(1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1)
    bbox = map(_text._glyphlayout, _text.position) do gl, pos
        FRect2D(Bbox_from_glyphlayout(gl)) + Vec2f0(pos[1], pos[2])
    end

    background = mesh!(
        plot, bbox, color = background_color, shading = false, 
        visible = visible, show_axis = false,
        projection = root_px_projection, view = id, projectionview = root_px_projection
    )
    outline = wireframe!(
        plot, bbox,
        color = outline_color, shading = false, visible = visible,
        show_axis = false,
        projection = root_px_projection, view = id, projectionview = root_px_projection
    )
    
    px_bbox = wireframe!(
        plot, bbox2D,
        color = color, linewidth = 2, # model = model,
        visible = px_bbox_visible, show_axis = false,
        projection = root_px_projection, view = id, projectionview = root_px_projection
    )

    # To make sure inspector plots end up in front
    on(depth) do d
        # This is a translate to, not translate by
        translate!(background, Vec3f0(0,0,d))
        translate!(outline,    Vec3f0(0,0,d+1))
        translate!(_text,      Vec3f0(0,0,d+2))
        translate!(px_bbox,    Vec3f0(0,0,d))
    end
    depth[] = depth[]
    nothing
end


################################################################################
### Interactive selection via DataInspector
################################################################################



# TODO destructor?
mutable struct DataInspector
    # need some static reference
    root::Scene

    # Adjust to hover
    hovered_scene::Union{Nothing, Scene}
    temp_plots::Vector{AbstractPlot}

    # plot to attach to hovered scene
    plot::_Inspector

    whitelist::Vector{AbstractPlot}
    blacklist::Vector{AbstractPlot}
end


"""
    DataInspector(figure; blacklist = fig.scene.plots, kwargs...)
    DataInspector(axis; whitelist = axis.scene.plots, kwargs...)
    DataInspector(scene; kwargs...)

...
"""
function DataInspector(fig::Figure; blacklist = fig.scene.plots, kwargs...)
    DataInspector(fig.scene; blacklist = blacklist, kwargs...)
end

function DataInspector(ax; whitelist = ax.scene.plots, kwargs...)
    DataInspector(ax.scene; whitelist = whitelist, kwargs...)
end

# TODO
# - It would be good if we didn't need to flatten. Maybe recursively go up all
#   the way, then check if a plot is rejected and move down a level if it is or
#   attempt to show if not. If show fails also move down a level, else break.
function DataInspector(
        scene::Scene; 
        whitelist = AbstractPlot[], blacklist = AbstractPlot[], range = 10,
        kwargs...
    )
    parent = root(scene)
    @assert origin(pixelarea(parent)[]) == Vec2f0(0)

    plot = _inspector!(parent, 1, show_axis=false; kwargs...)
    plot.root_px_projection[] = camera(parent).pixel_space[]
    push!(blacklist, plot)
    blacklist = flatten_plots(blacklist)
    
    inspector = DataInspector(parent, scene, AbstractPlot[], plot, whitelist, blacklist)

    e = events(parent)
    onany(e.mouseposition, e.scroll) do mp, _
        # This is super cheap
        is_mouseinside(parent) || return false

        picks = pick_sorted(parent, mp, range)
        should_clear = true
        for (plt, idx) in picks
            @info idx, typeof(plt)
            if (plt !== nothing) && !(plt in inspector.blacklist) && 
                (isempty(inspector.whitelist) || (plt in inspector.whitelist))
                show_data(inspector, plt, idx)
                should_clear = false
                break
            end
        end

        if should_clear
            plot.visible[] = false
            plot.bbox_visible[] = false
            plot.px_bbox_visible[] = false
        end
    end

    inspector
end


function update_hovered!(inspector::DataInspector, scene)
    if scene != inspector.hovered_scene
        if !isempty(inspector.temp_plots) && (inspector.hovered_scene !== nothing)
            for p in inspector.temp_plots
                delete!(inspector.hovered_scene, p)
                for prim in flatten_plots(p)
                    delete!(inspector.blacklist, p)
                end
            end
            empty!(inspector.temp_plots)
        end
        inspector.hovered_scene = scene
    end
end

function update_positions!(inspector, scene, pos)
    a = inspector.plot.attributes
    proj_pos = shift_project(scene, to_ndim(Point3f0, pos, 0))
    a.position[] = pos
    a.proj_position[] = proj_pos
    return proj_pos
end


# TODO: better 3D scaling
function show_data(inspector::DataInspector, plot::Scatter, idx)
    @info "Scatter"
    a = inspector.plot.attributes
    scene = parent_scene(plot)
    update_hovered!(inspector, scene)

    proj_pos = update_positions!(inspector, scene, plot[1][][idx])
    ms = plot.markersize[]

    a.text_position[] = proj_pos .+ Vec2f0(5)
    a.display_text[] = position2string(plot[1][][idx])
    a.bbox2D[] = FRect2D(proj_pos .- 0.5 .* ms .- Vec2f0(5), Vec2f0(ms) .+ Vec2f0(10))
    a.px_bbox_visible[] = true
    a.bbox_visible[] = false
    a.visible[] = true

    return true
end

    
function show_data(inspector::DataInspector, plot::MeshScatter, idx)
    @info "MeshScatter"
    a = inspector.plot.attributes
    scene = parent_scene(plot)
    update_hovered!(inspector, scene)
        
    proj_pos = update_positions!(inspector, scene, plot[1][][idx])
    bbox = Rect{3, Float32}(plot.marker[])

    a.model[] = transformationmatrix(
        plot[1][][idx],
        to_scale(plot.markersize[], idx), 
        to_rotation(plot.rotations[], idx)
    )

    if isempty(inspector.temp_plots)
        p = wireframe!(
            scene, a.bbox3D, model = a.model, 
            color = a.color, visible = a.bbox_visible, show_axis = false,
        )
        push!(inspector.temp_plots, p)
        append!(inspector.blacklist, flatten_plots(p))
    end

    a.text_position[] = proj_pos .+ Vec2f0(5)
    a.display_text[] = position2string(plot[1][][idx])
    a.bbox3D[] = bbox
    a.px_bbox_visible[] = false
    a.bbox_visible[] = true
    a.visible[] = true
    
    return true
end

# TODO
# this needs some clamping?
function show_data(inspector::DataInspector, plot::Union{Lines, LineSegments}, idx)
    @info "Lines, LineSegments"
    a = inspector.plot.attributes
    if plot.parent.parent isa BarPlot
        return show_data(inspector, plot.parent.parent, div(idx-1, 6)+1)
    end
        
    scene = parent_scene(plot)
    update_hovered!(inspector, scene)

    # cast ray from cursor into screen, find closest point to line
    p0, p1 = plot[1][][idx-1:idx]
    origin, dir = view_ray(scene)
    pos = closest_point_on_line(p0, p1, origin, dir)
    lw = plot.linewidth[]
    
    proj_pos = update_positions!(inspector, scene, pos)

    a.text_position[] = proj_pos .+ Vec2f0(5)
    a.display_text[] = position2string(pos)
    a.bbox2D[] = FRect2D(proj_pos .- 0.5 .* lw .- Vec2f0(5), Vec2f0(lw) .+ Vec2f0(10))
    a.px_bbox_visible[] = true
    a.bbox_visible[] = false
    a.visible[] = true

    return true
end

# TODO position indicator better
function show_data(inspector::DataInspector, plot::Mesh, idx)
    @info "Mesh"
    a = inspector.plot.attributes
    if plot.parent.parent.parent isa BarPlot
        return show_data(inspector, plot.parent.parent.parent, div(idx-1, 4)+1)
    end

    scene = parent_scene(plot)
    update_hovered!(inspector, scene)
        
    bbox = boundingbox(plot)
    min, max = extrema(bbox)
    proj_pos = update_positions!(inspector, scene, 0.5 * (max .+ min))

    a.model[] = plot.model[]

    if isempty(inspector.temp_plots)
        p = wireframe!(
            scene, a.bbox3D, model = a.model, 
            color = a.color, visible = a.bbox_visible, show_axis = false,
        )
        push!(inspector.temp_plots, p)
        append!(inspector.blacklist, flatten_plots(p))
    end

    a.text_position[] = proj_pos .+ Vec2f0(5)
    a.display_text[] = bbox2string(bbox)
    a.bbox3D[] = bbox
    a.px_bbox_visible[] = false
    a.bbox_visible[] = true
    a.visible[] = true

    return true
end

# TODO breaks with ax as root
function show_data(inspector::DataInspector, plot::BarPlot, idx)
    @info "BarPlot"
    a = inspector.plot.attributes
    scene = parent_scene(plot)
    update_hovered!(inspector, scene)
        
    proj_pos = update_positions!(inspector, scene, plot[1][][idx])
    a.model[] = plot.model[]
    a.bbox2D[] = plot.plots[1][1][][idx]

    if isempty(inspector.temp_plots)
        p = wireframe!(
            scene, a.bbox2D, model = a.model, 
            color = a.color, visible = a.bbox_visible, show_axis = false,
        )
        translate!(p, Vec3f0(0, 0, a.depth[]))
        push!(inspector.temp_plots, p)
        append!(inspector.blacklist, flatten_plots(p))
    end

    a.text_position[] = proj_pos .+ Vec2f0(5)
    a.display_text[] = position2string(pos)
    a.bbox_visible[] = true
    a.px_bbox_visible[] = false
    a.visible[] = true

    return true
end

function show_data(inspector::DataInspector, plot::Heatmap, idx)
    # This needs to be updated once Heatmaps are centered 
    # Alternatively, could this get a useful index?
    @info "Heatmap"
    a = inspector.plot.attributes
    # idx == 0 :(
    scene = parent_scene(plot)
    update_hovered!(inspector, scene)
            
    mpos = mouseposition(scene)
    i = pos2index(mpos[1], plot[1][], size(plot[3][], 1))
    j = pos2index(mpos[2], plot[2][], size(plot[3][], 2))
    x0 = index2pos(i-1, plot[1][], size(plot[3][], 1))
    y0 = index2pos(j-1, plot[2][], size(plot[3][], 2))
    x1 = index2pos(i, plot[1][], size(plot[3][], 1))
    y1 = index2pos(j, plot[2][], size(plot[3][], 2))
    x = 0.5(x0 + x1); y = 0.5(y0 + y1)
    z = plot[3][][i, j]

    proj_pos = update_positions!(inspector, scene, Point3f0(x, y, 0))
    a.bbox2D[] = FRect2D(Vec2f0(x0, y0), Vec2f0(x1-x0, y1-y0))
    
    if isempty(inspector.temp_plots)
        p = wireframe!(
            scene, a.bbox2D, model = a.model, 
            color = a.color, visible = a.bbox_visible, show_axis = false,
        )
        translate!(p, Vec3f0(0, 0, a.depth[]))
        push!(inspector.temp_plots, p)
        append!(inspector.blacklist, flatten_plots(p))
    end
    
    a.text_position[] = proj_pos .+ Vec2f0(5)
    a.display_text[] = @sprintf("%0.3f @ (%i, %i)", z, i, j)
    a.bbox_visible[] = true
    a.px_bbox_visible[] = false
    a.visible[] = true

    return true
end


function show_data(inspector::DataInspector, plot, idx)
    @info "else"
    inspector.plot.visible[] = false
    inspector.plot.bbox_visible[] = false
    inspector.plot.px_bbox_visible[] = false

    return false
end
