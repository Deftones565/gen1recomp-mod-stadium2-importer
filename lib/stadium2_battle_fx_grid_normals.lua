-- Normals used by the Stadium 2 wave/grid effects (fragment 79, 0x8415F264).
--
-- The native routine builds up to four corner normals around each grid point.
-- Each corner is a cross product of two edge vectors, normalized before being
-- accumulated, and the accumulated vector is normalized once more.  Keeping
-- the intermediate rounding here is useful when comparing the generated
-- vertex stream with the N64 effect.
local f = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")

local function vec(a, b, c)
    return {f(a), f(b), f(c)}
end

local function sub(a, b)
    return vec(f(a[1] - b[1]), f(a[2] - b[2]), f(a[3] - b[3]))
end

local function cross(a, b)
    return vec(
        f(f(a[2] * b[3]) - f(a[3] * b[2])),
        f(f(a[3] * b[1]) - f(a[1] * b[3])),
        f(f(a[1] * b[2]) - f(a[2] * b[1])))
end

local function normalize(v)
    local length = f(math.sqrt(f(f(f(v[1] * v[1]) + f(v[2] * v[2])) + f(v[3] * v[3]))))
    if length <= 0 then return nil end
    return vec(f(v[1] / length), f(v[2] / length), f(v[3] / length))
end

local function readVertices(input)
    local count
    local points = {}
    if type(input[1]) == "number" then
        count = math.floor(#input / 3)
        for i = 1, count do
            local p = (i - 1) * 3
            points[i] = vec(input[p + 1], input[p + 2], input[p + 3])
        end
    else
        count = #input
        for i = 1, count do
            local p = input[i]
            points[i] = vec(p.x or p[1] or 0, p.y or p[2] or 0, p.z or p[3] or 0)
        end
    end
    return points, count
end

return function(vertices)
    local points, count = readVertices(vertices)
    if count == 0 then return {} end

    -- Family 9's authored grid is 16x16 (the routine's caller supplies 256
    -- points).  Infer the side so this helper remains useful for reduced test
    -- grids while retaining the exact 256 point path.
    local width = math.floor(math.sqrt(count) + 0.5)
    if width < 1 then width = 1 end
    local height = math.floor((count + width - 1) / width)
    local result = {}

    local function at(x, y)
        if x < 1 or x > width or y < 1 or y > height then return nil end
        local index = (y - 1) * width + x
        return index <= count and points[index] or nil
    end

    for y = 1, height do
        for x = 1, width do
            local here = at(x, y)
            local sum = vec(0, 0, 0)

            -- Native ordering is upper/left, upper/right, lower/left,
            -- lower/right, with the fourth contribution subtracted. Preserve
            -- this asymmetry rather than replacing it with averaged triangles.
            local corners = {
                {at(x, y - 1), at(x - 1, y)},
                {at(x, y - 1), at(x + 1, y)},
                {at(x, y + 1), at(x - 1, y)},
                {at(x, y + 1), at(x + 1, y)},
            }
            for i = 1, 4 do
                local p, q = corners[i][1], corners[i][2]
                if here and p and q then
                    local a,b=normalize(sub(p,here)),normalize(sub(q,here))
                    local n = a and b and normalize(cross(a,b))
                    if n then
                        local sign=i==4 and -1 or 1 -- 8415F7DC subtracts the fourth corner
                        sum[1] = f(sum[1] + sign*n[1])
                        sum[2] = f(sum[2] + sign*n[2])
                        sum[3] = f(sum[3] + sign*n[3])
                    end
                end
            end
            local n = normalize(sum) or vec(0, 1, 0)
            local out = (y - 1) * width + x
            result[out * 3 - 2] = n[1]
            result[out * 3 - 1] = n[2]
            result[out * 3] = n[3]
        end
    end
    return result
end
