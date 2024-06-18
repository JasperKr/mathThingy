local PI2 = math.pi * 2
local IPI2 = 1 / PI2
local IPI = 1 / math.pi
local PI05 = math.pi * 0.5
local ffi = require("ffi")

mathT = {}

require("vec")
require("matrices")
require("quaternions")
require("tables")
table.clear = require("table.clear")

local tempObjectHandlers = {}

--- Creates a new temporary object handler
---@param constructor function
---@param set function
---@param amount? integer
---@param ... unknown
---@return function
local function newTempObjectHandler(constructor, set, amount, ...)
    amount = amount or 50

    local self = {
        tempObjects = {},
        index = 0,
        loopAmount = amount - 1,
        setNew = set,
    }

    self.get = function(...)
        self.index = self.index % self.loopAmount + 1
        self.setNew(self.tempObjects[self.index], ...)
        return self.tempObjects[self.index]
    end

    for i = 1, amount do
        table.insert(self.tempObjects, constructor(...))
    end
    table.insert(tempObjectHandlers, self)
    return self.get
end

mathT.TempVec2 = newTempObjectHandler(vec2, function(value, x, y)
    if type(x) == "table" then
        value.x = x[1]; value.y = x[2]
    elseif type(x) == "cdata" then
        value.x = x.x; value.y = x.y
    else
        value.x = x or 0; value.y = y or 0
    end
end, nil, 0, 0)

mathT.TempVec3 = newTempObjectHandler(vec3, function(value, x, y, z)
    if type(x) == "table" then
        value.x = x[1]; value.y = x[2]; value.z = x[3]
    elseif type(x) == "cdata" then
        value.x = x.x; value.y = x.y; value.z = x.z
    else
        value.x = x or 0; value.y = y or 0; value.z = z or 0
    end
end, nil, 0, 0, 0)

mathT.TempVec4 = newTempObjectHandler(vec4, function(value, x, y, z, w)
    if type(x) == "table" then
        value.x = x[1]; value.y = x[2]; value.z = x[3]; value.w = x[4]
    elseif type(x) == "cdata" then
        value.x = x.x; value.y = x.y; value.z = x.z; value.w = x.w
    else
        value.x = x or 0; value.y = y or 0; value.z = z or 0; value.w = w or 0
    end
end, nil, 0, 0, 0, 0)

local vectorTypes = { -- cache types so we dont have to call vec4().CType every time
    vec4 = vec4().CType,
    vec3 = vec3().CType,
    vec2 = vec2().CType,
    quaternion = quaternion().CType,
}

function mathT.clamp(v, min, max)
    return math.min(math.max(v, min), max)
end

function mathT.round(x, i)
    i = i or 0
    i = 10 ^ i
    return math.floor(x * i + 0.5) / i
end

function mathT.saturate(x)
    return math.min(math.max(x, 0.0), 1.0)
end

---@alias Rhodium.physicsMaterial {density:number, restitution: number, friction:number}

function mathT.aabb(aMinX, aMinY, aMinZ, aMaxX, aMaxY, aMaxZ, bMinX, bMinY, bMinZ, bMaxX, bMaxY, bMaxZ)
    local x_condition = (aMinX - bMaxX) * (bMinX - aMaxX)
    local y_condition = (aMaxY - bMinY) * (bMaxY - aMinY)
    local z_condition = (aMaxZ - bMinZ) * (bMaxZ - aMinZ)
    return math.min(x_condition, y_condition, z_condition) > 0
end

local function printTableInternal(t, floor, names, loopedTables)
    io.write(("  "):rep(#names) .. (names[#names] and names[#names] .. ": " or "") .. "{\n")
    for i, v in pairs(t) do
        if type(v) == "table" then
            if loopedTables[v] then
                io.write(("  "):rep(#names + 1) .. i .. " = Reference to " .. loopedTables[v] .. "\n")
                goto continue
            end
            if v == t or v == _G then
                io.write(("  "):rep(#names + 1) .. i .. " = Reference to self\n")
                goto continue
            end
            if not next(v) then
                io.write(("  "):rep(#names + 1) .. i .. " = {}\n")
                goto continue
            end
            table.insert(names, i)
            loopedTables[v] = table.concat(names, ".")
            printTableInternal(v, floor, names, loopedTables)
            table.remove(names, #names)
        else
            if floor then
                if type(v) == "number" then
                    io.write(("  "):rep(#names + 1) .. i .. " = " .. mathT.round(v) .. "\n")
                else
                    io.write(("  "):rep(#names + 1) .. i .. " = " .. v .. "\n")
                end
            else
                io.write(("  "):rep(#names + 1) .. tostring(i) .. " = " .. tostring(v) .. "\n")
            end
        end
        ::continue::
    end
    io.write(("  "):rep(#names) .. "}\n")
end

local function toTableVal(x)
    if type(x) == "string" then
        return "\"" .. x .. "\""
    else
        return tostring(x)
    end
end

local function TableToStringInternal(t, finalString, names, loopedTables)
    finalString = finalString ..
        ("  "):rep(#names) .. (names[#names] and "[" .. toTableVal(names[#names]) .. "] = " or "") .. "{\n"
    for i, v in pairs(t) do
        if type(v) == "table" then
            if loopedTables[v] then
                finalString = finalString ..
                    ("  "):rep(#names + 1) .. "[" .. toTableVal(i) .. "] = \"Reference to " .. loopedTables[v] .. "\"\n"
                goto continue
            end
            if v == t or v == _G then
                finalString = finalString ..
                    ("  "):rep(#names + 1) .. "[" .. toTableVal(i) .. "] = \"Reference to self\"\n"
                goto continue
            end
            if not next(v) then
                finalString = finalString .. ("  "):rep(#names + 1) .. "[" .. toTableVal(i) .. "] = {}\n"
                goto continue
            end
            table.insert(names, i)
            loopedTables[v] = table.concat(names, ".")
            finalString = TableToStringInternal(v, finalString, names, loopedTables)
            table.remove(names, #names)
        else
            if type(v) == "userdata" or type(v) == "function" or type(v) == "thread" then
                finalString = finalString .. ("  "):rep(#names + 1) .. i .. " = \"" .. type(v) .. "\"\n"
            elseif type(i) == "string" then
                finalString = finalString .. ("  "):rep(#names + 1) .. i .. " = " .. toTableVal(v) .. "\n"
            else
                finalString = finalString ..
                    ("  "):rep(#names + 1) .. "[" .. toTableVal(i) .. "] = " .. toTableVal(v) .. "\n"
            end
        end
        ::continue::
    end
    finalString = finalString .. ("  "):rep(#names) .. "}\n"
    return finalString
end

function mathT.tableToString(t)
    local names = {}
    if type(t) == "table" then
        return TableToStringInternal(t, "", names, {})
    else
        return tostring(t)
    end
end

function mathT.printTable(t, floor)
    local names = {}
    if type(t) == "table" then
        printTableInternal(t, floor, names, {})
    else
        io.write(tostring(t) .. "\n")
    end
end

function mathT.copyTable(t)
    if type(t) == "table" then
        local t2 = {}
        for i, v in pairs(t) do
            if type(v) == "table" then
                t2[i] = mathT.copyTable(v)
            else
                t2[i] = v
            end
        end
        return t2
    else
        return t
    end
end

function mathT.sign(number)
    return (number > 0 and 1 or (number == 0 and 0 or -1))
end

--[[
    // compute normal
    vec3 capNormal( in vec3 pos, in vec3 a, in vec3 b, in float r )
    {
        vec3  ba = b - a;
        vec3  pa = pos - a;
        float h = clamp(dot(pa,ba)/dot(ba,ba),0.0,1.0);
        return (pa - h*ba)/r;
    }
]]


--- returns the normal of a capsule at a point
---@param x number
---@param y number
---@param z number
---@param aX number
---@param aY number
---@param aZ number
---@param bX number
---@param bY number
---@param bZ number
---@return number
---@return number
---@return number
function mathT.capsuleNormal(x, y, z, aX, aY, aZ, bX, bY, bZ)
    local baX, baY, baZ = bX - aX, bY - aY, bZ - aZ
    local paX, paY, paZ = x - aX, y - aY, z - aZ
    local h = mathT.clamp(
        mathT.dot(baX, baY, baZ, paX, paY, paZ) / mathT.dot(baX, baY, baZ, baX, baY, baZ), 0.0,
        1.0)
    return mathT.normalize3(paX - h * baX, paY - h * baY, paZ - h * baZ)
end

function mathT.calculateSphereTangent(nx, ny, nz)
    -- Check if the normal is parallel to the up vector
    local tx, ty, tz = mathT.cross(nx, ny, nz, 0, 1, 0)
    if tx * tx + ty * ty + tz * tz < 1e-5 then
        return 1, 0, 0
    else
        return mathT.normalize3(tx, ty, tz)
    end
end

--- mix between two values
---@param i number
---@param v number
---@param w number
---@return number
function mathT.mix(i, v, w)
    return (1 - i) * v + i * w
end

function mathT.cross(x1, y1, z1, x2, y2, z2)
    return y1 * z2 - z1 * y2, z1 * x2 - x1 * z2, x1 * y2 - y1 * x2
end

function mathT.dot(x1, y1, z1, x2, y2, z2)
    return x1 * x2 + y1 * y2 + z1 * z2
end

function mathT.dot2(x1, y1, x2, y2)
    return x1 * x2 + y1 * y2
end

function mathT.dot3(x1, y1, z1, x2, y2, z2)
    return x1 * x2 + y1 * y2 + z1 * z2
end

function mathT.dot4(x1, y1, z1, w1, x2, y2, z2, w2)
    return x1 * x2 + y1 * y2 + z1 * z2 + w1 * w2
end

function mathT.lerp(angle, target, turnrate)
    local dist = target - angle
    dist = (dist + math.pi) % PI2 - math.pi
    local step = turnrate * love.timer.getDelta()
    if math.abs(dist) <= step then
        angle = target
    else
        if dist < 0 then
            step = -step
        end
        angle = angle + step
    end
    return angle
end

function mathT.smoothLerp(angle, target, turnrate)
    local dist = target - angle
    dist = (dist + math.pi) % (math.pi * 2) - math.pi
    local step = turnrate * love.timer.getDelta()
    return angle + step * dist
end

function mathT.pointAABBDistance(min, max, position)
    local q = vec3(math.max(0, math.max(min.x - position.x, position.x - max.x)),
        math.max(0, math.max(min.y - position.y, position.y - max.y)),
        math.max(0, math.max(min.z - position.z, position.z - max.z)))

    local outsideDist = q:length()

    local isInside = position.x >= min.x and position.x <= max.x and position.y >= min.y and position.y <= max.y and
        position.z >= min.z and position.z <= max.z

    if isInside then
        return 0
    else
        return outsideDist
    end
end

function mathT.pointAABBDistanceSqr(min, max, position)
    local q = vec3(math.max(0, math.max(min.x - position.x, position.x - max.x)),
        math.max(0, math.max(min.y - position.y, position.y - max.y)),
        math.max(0, math.max(min.z - position.z, position.z - max.z)))

    local outsideDist = q:lengthSqr()

    local isInside = position.x >= min.x and position.x <= max.x and position.y >= min.y and position.y <= max.y and
        position.z >= min.z and position.z <= max.z

    if isInside then
        return 0
    else
        return outsideDist
    end
end

--- switch between functions, select with i
---@param i number
---@param ... function
function mathT.switch(i, ...)
    local t = { ... }
    t[i]()
end

function mathT.point_line_distance(p, v1, v2)
    local AB = v2 - v1
    return (AB:cross(p - v1)):length() / AB:length()
end

do -- define rotation conversions
    -- Other to matrix:

    ---@return matrix4x4 m
    function mathT.eulerToMatrix(pitch, yaw, roll)
        -- this function assumes pitch is about the z-axis rather than the x-axis (??)
        -- so i swapped pitch and roll
        local ch = math.cos(yaw)
        local sh = math.sin(yaw)
        local ca = math.cos(roll)
        local sa = math.sin(roll)
        local cb = math.cos(pitch)
        local sb = math.sin(pitch)

        local m = mat4()
        m[1][1] = ch * ca
        m[1][2] = sh * sb - ch * sa * cb
        m[1][3] = ch * sa * sb + sh * cb
        m[2][1] = sa
        m[2][2] = ca * cb
        m[2][3] = -ca * sb
        m[3][1] = -sh * ca
        m[3][2] = sh * sa * cb + ch * sb
        m[3][3] = -sh * sa * sb + ch * cb

        return m
    end

    ---@return matrix4x4 m
    function mathT.quaternionToMatrix(q)
        local m = mat4()
        m[1][1] = (q.x * q.x - q.y * q.y - q.z * q.z + q.w * q.w)
        m[2][2] = (-q.x * q.x + q.y * q.y - q.z * q.z + q.w * q.w)
        m[3][3] = (-q.x * q.x - q.y * q.y + q.z * q.z + q.w * q.w)

        m[2][1] = 2.0 * (q.x * q.y + q.z * q.w)
        m[1][2] = 2.0 * (q.x * q.y - q.z * q.w)

        m[3][1] = 2.0 * (q.x * q.z - q.y * q.w)
        m[1][3] = 2.0 * (q.x * q.z + q.y * q.w)
        m[3][2] = 2.0 * (q.y * q.z + q.x * q.w)
        m[2][3] = 2.0 * (q.y * q.z - q.x * q.w)

        return m
    end

    -- Other to Quaternion:

    ---@return quaternion quat
    function mathT.eulerToQuaternion(pitch, yaw, roll)
        if type(pitch) == "table" or not pitch or not yaw or not roll then
            error("mathT.eulerToQuaternion: invalid input")
        end
        pitch = pitch * 0.5
        yaw = yaw * 0.5
        roll = roll * 0.5

        local c1 = math.cos(yaw)
        local s1 = math.sin(yaw)

        local c2 = math.cos(roll)
        local s2 = math.sin(roll)

        local c3 = math.cos(pitch)
        local s3 = math.sin(pitch)

        local c1c2 = c1 * c2
        local s1s2 = s1 * s2
        local w = c1c2 * c3 - s1s2 * s3
        local x = c1c2 * s3 + s1s2 * c3
        local y = s1 * c2 * c3 + c1 * s2 * s3
        local z = c1 * s2 * c3 - s1 * c2 * s3
        return quaternion(x, y, z, w)
    end

    ---@return quaternion quat
    function mathT.matrixToQuaternion(m)
        local a = m:transpose()
        local trace = a[1][1] + a[2][2] + a[3][3]
        local q = quaternion()

        if trace > 0 then
            local s = 0.5 / math.sqrt(trace + 1.0)
            q.w = 0.25 / s
            q.x = (a[3][2] - a[2][3]) * s
            q.y = (a[1][3] - a[3][1]) * s
            q.z = (a[2][1] - a[1][2]) * s
        elseif a[1][1] > a[2][2] and a[1][1] > a[3][3] then
            local s = 2.0 * math.sqrt(1.0 + a[1][1] - a[2][2] - a[3][3])
            q.w = (a[3][2] - a[2][3]) / s
            q.x = 0.25 * s
            q.y = (a[1][2] + a[2][1]) / s
            q.z = (a[1][3] + a[3][1]) / s
        elseif a[2][2] > a[3][3] then
            local s = 2.0 * math.sqrt(1.0 + a[2][2] - a[1][1] - a[3][3])
            q.w = (a[1][3] - a[3][1]) / s
            q.x = (a[1][2] + a[2][1]) / s
            q.y = 0.25 * s
            q.z = (a[2][3] + a[3][2]) / s
        else
            local s = 2.0 * math.sqrt(1.0 + a[3][3] - a[1][1] - a[2][2])
            q.w = (a[2][1] - a[1][2]) / s
            q.x = (a[1][3] + a[3][1]) / s
            q.y = (a[2][3] + a[3][2]) / s
            q.z = 0.25 * s
        end

        return q
    end

    -- Other to euler:

    ---@return number pitch
    ---@return number yaw
    ---@return number roll
    function mathT.quaternionToEuler(q)
        local test = q.x * q.y + q.z * q.w
        local heading, attitude, bank

        if test > 0.499 then -- singularity at north pole
            heading = 2 * math.atan2(q.x, q.w)
            attitude = math.pi / 2
            bank = 0
        elseif test < -0.499 then -- singularity at south pole
            heading = -2 * math.atan2(q.x, q.w)
            attitude = -math.pi / 2
            bank = 0
        else
            local sqx = q.x * q.x
            local sqy = q.y * q.y
            local sqz = q.z * q.z
            heading = math.atan2(2 * q.y * q.w - 2 * q.x * q.z, 1 - 2 * sqy - 2 * sqz)
            attitude = math.asin(2 * test)
            bank = math.atan2(2 * q.x * q.w - 2 * q.y * q.z, 1 - 2 * sqx - 2 * sqz)
        end
        -- this function assumes pitch is about the z-axis rather than the x-axis (??)
        return bank, heading, attitude
    end

    ---@return number pitch
    ---@return number yaw
    ---@return number roll
    function mathT.matrixToEuler(m)
        -- Assuming the angles are in radians.
        local heading, attitude, bank
        if m[2][1] > 0.998 then -- singularity at north pole
            heading = math.atan2(m[1][3], m[3][3])
            attitude = math.pi / 2
            bank = 0
        elseif m[2][1] < -0.998 then -- singularity at south pole
            heading = math.atan2(m[1][3], m[3][3])
            attitude = -math.pi / 2
            bank = 0
        else
            heading = math.atan2(-m[3][1], m[1][1])
            bank = math.atan2(-m[2][3], m[2][2])
            attitude = math.asin(m[2][1])
        end

        -- this function assumes pitch is about the z-axis rather than the x-axis (??)
        return bank, heading, attitude
    end
end

--- creates a new translation matrix
---@param position vec3
---@return matrix4x4
function mathT.newTranslationMatrix(position)
    local m = mat4()
    m[4][1] = position.x
    m[4][2] = position.y
    m[4][3] = position.z
    return m
end

---@param matrix matrix4x4
---@return table
function mathT.frustumFromMatrix(matrix)
    local frustum = {}

    frustum[1] = vec4(
        matrix[1][4] + matrix[1][1],
        matrix[2][4] + matrix[2][1],
        matrix[3][4] + matrix[3][1],
        matrix[4][4] + matrix[4][1]
    )

    frustum[2] = vec4(
        matrix[1][4] - matrix[1][1],
        matrix[2][4] - matrix[2][1],
        matrix[3][4] - matrix[3][1],
        matrix[4][4] - matrix[4][1]
    )

    frustum[3] = vec4(
        matrix[1][4] - matrix[1][2],
        matrix[2][4] - matrix[2][2],
        matrix[3][4] - matrix[3][2],
        matrix[4][4] - matrix[4][2]
    )

    frustum[4] = vec4(
        matrix[1][4] + matrix[1][2],
        matrix[2][4] + matrix[2][2],
        matrix[3][4] + matrix[3][2],
        matrix[4][4] + matrix[4][2]
    )

    frustum[5] = vec4(
        matrix[1][4] + matrix[1][3],
        matrix[2][4] + matrix[2][3],
        matrix[3][4] + matrix[3][3],
        matrix[4][4] + matrix[4][3]
    )

    frustum[6] = vec4(
        matrix[1][4] - matrix[1][3],
        matrix[2][4] - matrix[2][3],
        matrix[3][4] - matrix[3][3],
        matrix[4][4] - matrix[4][3]
    )

    return {
        frustum = frustum,
    }
end

function mathT.frustumAABB(fru, x, y, z, x1, y1, z1)
    local dot = mathT.dot
    for i = 1, 6 do
        local frustum = fru.frustum[i]
        local fx, fy, fz, fw = frustum:get()
        if dot(fx, fy, fz, x, y, z) + fw < 0.0
            and dot(fx, fy, fz, x1, y, z) + fw < 0.0
            and dot(fx, fy, fz, x, y1, z) + fw < 0.0
            and dot(fx, fy, fz, x1, y1, z) + fw < 0.0
            and dot(fx, fy, fz, x, y, z1) + fw < 0.0
            and dot(fx, fy, fz, x1, y, z1) + fw < 0.0
            and dot(fx, fy, fz, x, y1, z1) + fw < 0.0
            and dot(fx, fy, fz, x1, y1, z1) + fw < 0.0 then
            return false
        end
    end

    --local out
    --out=0; for i = 1,8 do out = out + ((fru.corners[i][1] > x1) and 1 or 0) end; if out == 8 then return false end
    --out=0; for i = 1,8 do out = out + ((fru.corners[i][1] < x) and 1 or 0) end; if out == 8 then return false end
    --out=0; for i = 1,8 do out = out + ((fru.corners[i][2] > y1) and 1 or 0) end; if out == 8 then return false end
    --out=0; for i = 1,8 do out = out + ((fru.corners[i][2] < y) and 1 or 0) end; if out == 8 then return false end
    --out=0; for i = 1,8 do out = out + ((fru.corners[i][3] > z1) and 1 or 0) end; if out == 8 then return false end
    --out=0; for i = 1,8 do out = out + ((fru.corners[i][3] < z) and 1 or 0) end; if out == 8 then return false end

    return true
end

function mathT.length(...)
    local val = { ... }
    if type(val[1]) == "table" then
        if val[1][1] == nil then
            local x, y, z, w = val[1].x or 0, val[1].y or 0, val[1].z or 0, val[1].w or 0
            return math.sqrt(x * x + y * y + z * z + w * w)
        else
            local v = 0
            for _, w in ipairs(val[1]) do v = v + w * w end
            return math.sqrt(v)
        end
    else
        local v = 0
        for _, w in ipairs(val) do v = v + w * w end
        return math.sqrt(v)
    end
end

function mathT.length2(x, y)
    return math.sqrt(x * x + y * y)
end

function mathT.length3(x, y, z)
    return math.sqrt(x * x + y * y + z * z)
end

function mathT.length4(x, y, z, w)
    return math.sqrt(x * x + y * y + z * z + w * w)
end

function mathT.crossVector(v1, v2)
    return vec3(v1.y * v2.z - v1.z * v2.y, v1.z * v2.x - v1.x * v2.z, v1.x * v2.y - v1.y * v2.x)
end

function mathT.dotVector(v1, v2)
    return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
end

--- Rotate a position using a quaternion and vector math
---@param position vec3
---@param quat quaternion
---@return vec3
function mathT.rotatePosition(position, quat)
    local cx = quat.y * position.z - quat.z * position.y + position.x * quat.w
    local cy = quat.z * position.x - quat.x * position.z + position.y * quat.w
    local cz = quat.x * position.y - quat.y * position.x + position.z * quat.w

    return vec3(position.x + 2 * (quat.y * cz - quat.z * cy),
        position.y + 2 * (quat.z * cx - quat.x * cz),
        position.z + 2 * (quat.x * cy - quat.y * cx))
end

--- Rotate a position using normal variables instead of vectors or quaternions
---@param x number -- position x
---@param y number -- position y
---@param z number -- position z
---@param qx number -- quaternion x
---@param qy number -- quaternion y
---@param qz number -- quaternion z
---@param qw number -- quaternion w
---@return number, number, number
function mathT.rotatePositionSeparate(x, y, z, qx, qy, qz, qw)
    local cx = qy * z - qz * y + x * qw
    local cy = qz * x - qx * z + y * qw
    local cz = qx * y - qy * x + z * qw

    return x + 2 * (qy * cz - qz * cy),
        y + 2 * (qz * cx - qx * cz),
        z + 2 * (qx * cy - qy * cx)
end

--- converts vertices and indices to a triangle list
---@param vertices table
---@param indices table<integer>
function mathT.verticesToTriangles(vertices, indices, triangles)
    if #indices % 3 ~= 0 then
        error("mathT.verticesToTriangles: invalid indices")
    end
    triangles = triangles or {}
    for i = 1, #indices do
        table.insert(triangles, vertices[indices[i]])
    end
    return triangles
end

function mathT.rotatePositions(...)
    local t = { ... }
    local q = t[#t]
    local vertices = {}
    for i = 1, #t - 1 do
        table.insert(vertices, mathT.rotatePosition(t[i], q))
    end
    return vertices
end

--- Rotate positions using normal variables instead of vectors or quaternions (12x faster than mathT.rotatePosition)
function mathT.rotatePositionsSeparate(...)
    local t = { ... }
    local qx, qy, qz, qw = t[#t][1], t[#t][2], t[#t][3], t[#t][4]
    local vertices = {}
    for i = 1, #t - 1 do
        local x, y, z = t[i][1], t[i][2], t[i][3]
        local cx = qy * z - qz * y + x * qw
        local cy = qz * x - qx * z + y * qw
        local cz = qx * y - qy * x + z * qw

        table.insert(vertices, {
            x + 2 * (qy * cz - qz * cy),
            y + 2 * (qz * cx - qx * cz),
            z + 2 * (qx * cy - qy * cx)
        })
    end
    return vertices
end

--- Rotate positions using normal variables instead of vectors or quaternions (12x faster than mathT.rotatePosition)
function mathT.rotateTablePositionsSeparate(vertices, qx, qy, qz, qw)
    local newPoints = {}
    for i = 1, #vertices do
        local x, y, z = vertices[i][1], vertices[i][2], vertices[i][3]
        local cx = qy * z - qz * y + x * qw
        local cy = qz * x - qx * z + y * qw
        local cz = qx * y - qy * x + z * qw

        table.insert(newPoints, {
            x + 2 * (qy * cz - qz * cy),
            y + 2 * (qz * cx - qx * cz),
            z + 2 * (qx * cy - qy * cx)
        })
    end
    return newPoints
end

--- calculates the triangle normal of a triangle
---@param p1 table point 1
---@param p2 table point 2
---@param p3 table point 3
---@param inverted? boolean invert the normal?
---@return number x
---@return number y
---@return number z
function mathT.triangleNormal(p1, p2, p3, inverted)
    local ux, uy, uz = p2[1] - p1[1], p2[2] - p1[2], p2[3] - p1[3]
    local vx, vy, vz = p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3]
    local x = (uy * vz - uz * vy) * (inverted and -1 or 1)
    local y = (uz * vx - ux * vz) * (inverted and -1 or 1)
    local z = (ux * vy - uy * vx) * (inverted and -1 or 1)
    return mathT.normalize3(x, y, z)
end

function mathT.normalize(...)
    local t = { ... }
    if type(t[1]) == "table" then
        t = t[1]
        local d = 0
        for i = 1, #t do
            d = d + t[i] * t[i]
        end
        local d1 = 1 / math.sqrt(d)
        local t2 = {}
        for i = 1, #t do
            if d == 0 then
                t2[i] = 0
            else
                t2[i] = t[i] * d1
            end
        end
        return unpack(t2)
    else
        local d = 0
        for i = 1, #t do
            d = d + t[i] * t[i]
        end
        local d1 = 1 / math.sqrt(d)
        local t2 = {}
        for i = 1, #t do
            if d == 0 then
                t2[i] = 0
            else
                t2[i] = t[i] * d1
            end
        end
        return unpack(t2)
    end
end

function mathT.normalize2(x, y)
    local d = x * x + y * y
    if d == 0 then
        return 0.0, 0.0
    end
    local d1 = 1 / math.sqrt(d)
    return x * d1, y * d1
end

function mathT.normalize3(x, y, z)
    local d = x * x + y * y + z * z
    if d == 0 then
        return 0.0, 0.0, 0.0
    end
    d = 1 / math.sqrt(d)
    return x * d, y * d, z * d
end

function mathT.normalize4(x, y, z, w)
    local d = x * x + y * y + z * z + w * w
    if d == 0 then
        return 0, 0, 0, 0
    end
    local d1 = 1 / math.sqrt(d)
    return x * d1, y * d1, z * d1, w * d1
end

function mathT.closestPointOnTriangle(a, b, c, point)
    local px, py, pz = point[1], point[2], point[3]

    local abX = b[1] - a[1]
    local abY = b[2] - a[2]
    local abZ = b[3] - a[3]

    local acX = c[1] - a[1]
    local acY = c[2] - a[2]
    local acZ = c[3] - a[3]

    local apX = px - a[1]
    local apY = py - a[2]
    local apZ = pz - a[3]

    local d1 = mathT.dot(abX, abY, abZ, apX, apY, apZ)
    local d2 = mathT.dot(acX, acY, acZ, apX, apY, apZ)
    if d1 <= 0 and d2 <= 0 then
        return vec3(a)
    end

    local bpX = px - b[1]
    local bpY = py - b[2]
    local bpZ = pz - b[3]

    local d3 = mathT.dot(abX, abY, abZ, bpX, bpY, bpZ)
    local d4 = mathT.dot(acX, acY, acZ, bpX, bpY, bpZ)
    if d3 >= 0 and d4 <= d3 then
        return vec3(b)
    end

    local vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0 then
        local v = d1 / (d1 - d3)
        local temp = mathT.TempVec3(abX, abY, abZ) * v
        local point = mathT.TempVec3(a) + temp
        return point
    end

    local cpX = px - c[1]
    local cpY = py - c[2]
    local cpZ = pz - c[3]

    local d5 = mathT.dot(abX, abY, abZ, cpX, cpY, cpZ)
    local d6 = mathT.dot(acX, acY, acZ, cpX, cpY, cpZ)
    if d6 >= 0 and d5 <= d6 then
        return vec3(c)
    end

    local vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0 then
        local w = d2 / (d2 - d6)
        local temp = mathT.TempVec3(acX, acY, acZ) * w
        local point = mathT.TempVec3(a) + temp
        return point
    end

    local va = d3 * d6 - d5 * d4
    if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0 then
        local w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        local vec3C = mathT.TempVec3(c)
        local vec3B = mathT.TempVec3(b)
        local temp = vec3C - vec3B
        local point = vec3B + temp * w
        return point
    end

    local denom = 1 / (va + vb + vc)
    local v = vb * denom
    local w = vc * denom
    local vec3A = mathT.TempVec3(a)
    local vec3AB = mathT.TempVec3(abX, abY, abZ)
    local vec3AC = mathT.TempVec3(acX, acY, acZ)
    local point = vec3A + vec3AB * v + vec3AC * w
    return point
end

--- closest point between two triangles
---@param a table<number, number, number>
---@param b table<number, number, number>
---@param c table<number, number, number>
---@param d table<number, number, number>
---@param e table<number, number, number>
---@param f table<number, number, number>
---@return vec3
function mathT.closestPointToTriangles(a, b, c, d, e, f)
    local closestPointFromTriA
    local closestDistanceToTriB = math.huge
    for index, vert in ipairs({ a, b, c }) do
        local point = mathT.closestPointOnTriangle(d, e, f, vert)
        local dist = (point - vert):lengthSqr()
        if dist < closestDistanceToTriB then
            closestDistanceToTriB = dist
            closestPointFromTriA = point -- or point
        end
    end
    local closestPointOnTriA = mathT.closestPointOnTriangle(a, b, c, closestPointFromTriA)

    local closestPointFromTriB
    local closestDistanceToTriA = math.huge
    for index, vert in ipairs({ d, e, f }) do
        local point = mathT.closestPointOnTriangle(a, b, c, vert)
        local dist = (point - vert):lengthSqr()
        if dist < closestDistanceToTriA then
            closestDistanceToTriA = dist
            closestPointFromTriB = point -- or point
        end
    end
    local closestPointOnTriB = mathT.closestPointOnTriangle(d, e, f, closestPointFromTriB)

    -- find the triangle that is closest to the avarage contact position
    local averageContactPosition = (closestPointOnTriA + closestPointOnTriB) * 0.5
    local closestTriangleIndex = nil
    local closestDistance = math.huge
    for index, triangle in ipairs({ { a, b, c }, { d, e, f } }) do
        local distance = math.huge
        for vertIndex, vert in ipairs(triangle) do
            local dist = (vert - averageContactPosition):lengthSqr()
            if dist < distance then
                distance = dist
            end
        end
        if distance < closestDistance then
            closestDistance = distance
            closestTriangleIndex = index
        end
    end
    return closestTriangleIndex == 1 and closestPointOnTriA or closestPointOnTriB
end

function mathT.eulerToAxisAngle(pitch, yaw, roll)
    local c1 = math.cos(yaw / 2)
    local s1 = math.sin(yaw / 2)
    local c2 = math.cos(pitch / 2)
    local s2 = math.sin(pitch / 2)
    local c3 = math.cos(roll / 2)
    local s3 = math.sin(roll / 2)
    local c1c2 = c1 * c2
    local s1s2 = s1 * s2
    local w = c1c2 * c3 - s1s2 * s3
    local x = c1c2 * s3 + s1s2 * c3
    local y = s1 * c2 * c3 + c1 * s2 * s3
    local z = c1 * s2 * c3 - s1 * c2 * s3
    local angle = 2 * math.acos(w)
    local norm = 1 / (x * x + y * y + z * z)
    if norm < 0.001 then
        x = 1
        y, z = 0, 0
    else
        norm = math.sqrt(norm);
        x = x * norm
        y = y * norm
        z = z * norm
    end
    return vec4(x, y, z, angle)
end

function mathT.axisAngleToEuler(axisAngle)
    local x, y, z, angle = axisAngle:get()
    local s = math.sin(angle)
    local c = math.cos(angle)
    local t = 1 - c
    if (x * y * t + z * s) > 0.998 then
        yaw = 2 * math.atan2(x * math.sin(angle / 2), math.cos(angle / 2))
        pitch = PI05
        roll = 0
        return pitch, yaw, roll
    end
    if (x * y * t + z * s) < -0.998 then
        yaw = -2 * math.atan2(x * math.sin(angle / 2), math.cos(angle / 2))
        pitch = -PI05
        roll = 0
        return pitch, yaw, roll
    end
    yaw = math.atan2(y * s - x * z * t, 1 - (y * y + z * z) * t)
    pitch = math.asin(x * y * t + z * s)
    roll = math.atan2(x * s - y * z * t, 1 - (x * x + z * z) * t)
    return pitch, yaw, roll
end

function mathT.axisAngleToQuat(axisAngle)
    local angle = axisAngle.w * 0.5
    local sinAngle = math.sin(angle)
    return quaternion(
        axisAngle.x * sinAngle,
        axisAngle.y * sinAngle,
        axisAngle.z * sinAngle,
        math.cos(angle)
    ):normalize()
end

function mathT.quatToAxisAngle(quat)
    local angle = math.acos(quat.w) * 2
    local mul = 1 / math.sqrt(1 - quat.w * quat.w)
    if mul > 1000 then
        return vec4(
            quat.x,
            quat.y,
            quat.z,
            math.cos(angle)
        )
    else
        return vec4(
            quat.x * mul,
            quat.y * mul,
            quat.z * mul,
            math.cos(angle)
        )
    end
end

--- returns the vector type of a variable
---@param x any
---@return "vec2"|"vec3"|"vec4"|"quaternion"|"unknown"
function mathT.type(x)
    local t = type(x)
    if t == "cdata" then
        local ct = ffi.typeof(x)

        if ct == vectorTypes.vec2 then
            return "vec2"
        elseif ct == vectorTypes.vec3 then
            return "vec3"
        elseif ct == vectorTypes.vec4 then
            return "vec4"
        elseif ct == vectorTypes.quaternion then
            return "quaternion"
        else
            return "unknown"
        end
    end
    return "unknown"
end

function mathT.rayTorus(r, tor, position, quat)
    local ray = {}
    do -- reposition the ray to account for the fact that i can't rotate the torus
        ray.position = mathT.rotatePosition(r.position - position, quat)
        ray.direction = mathT.rotatePosition(r.direction, quat)
    end
    local po = 1.0

    local Ra2 = tor.x * tor.x
    local ra2 = tor.y * tor.y

    local m = mathT.dotVector(ray.position, ray.position)
    local n = mathT.dotVector(ray.position, ray.direction)

    local k = (m - ra2 - Ra2) / 2.0
    local k3 = n
    local k2 = n * n + Ra2 * ray.direction.z * ray.direction.z + k
    local k1 = k * n + Ra2 * ray.position.z * ray.direction.z
    local k0 = k * k + Ra2 * ray.position.z * ray.position.z - Ra2 * ra2

    if math.abs(k3 * (k3 * k3 - k2) + k1) < 0.01 then
        po = -1.0
        local tmp = k1
        k1 = k3
        k3 = tmp
        k0 = 1.0 / k0
        k1 = k1 * k0
        k2 = k2 * k0
        k3 = k3 * k0
    end

    local c2 = 2.0 * k2 - 3.0 * k3 * k3
    local c1 = k3 * (k3 * k3 - k2) + k1
    local c0 = k3 * (k3 * (c2 + 2.0 * k2) - 8.0 * k1) + 4.0 * k0


    c2 = c2 / 3.0
    c1 = c1 * 2.0
    c0 = c0 / 3.0

    local Q = c2 * c2 + c0
    local R = c2 * c2 * c2 - 3.0 * c2 * c0 + c1 * c1

    local h = R * R - Q * Q * Q

    if h >= 0.0 then
        h = math.sqrt(h)
        local v = mathT.sign(R + h) * (math.abs(R + h) ^ (1.0 / 3.0))
        local u = mathT.sign(R - h) * (math.abs(R - h) ^ (1.0 / 3.0))
        s = mathT.TempVec3((v + u) + 4.0 * c2, (v - u) * math.sqrt(3.0))
        local y = math.sqrt(0.5 * (s:length() + s[1]))
        local x = 0.5 * s.y / y
        local r = 2.0 * c1 / (x * x + y * y)
        local t1 = x - r - k3
        t1 = (po < 0.0) and 2.0 / t1 or t1
        local t2 = -x - r - k3
        t2 = (po < 0.0) and 2.0 / t2 or t2
        local t = math.huge
        if t1 > 0.0 then t = t1 end
        if t2 > 0.0 then t = math.min(t, t2) end
        return t > 0 and t or nil
    end

    local sQ = math.sqrt(Q)
    local w = sQ * math.cos(math.acos(-R / (sQ * Q)) / 3.0)
    local d2 = -(w + c2)
    if d2 < 0.0 then return nil end
    local d1 = math.sqrt(d2)
    local h1 = math.sqrt(w - 2.0 * c2 + c1 / d1)
    local h2 = math.sqrt(w - 2.0 * c2 - c1 / d1)
    local t1 = -d1 - h1 - k3
    t1 = (po < 0.0) and 2.0 / t1 or t1
    local t2 = -d1 + h1 - k3
    t2 = (po < 0.0) and 2.0 / t2 or t2
    local t3 = d1 - h2 - k3
    t3 = (po < 0.0) and 2.0 / t3 or t3
    local t4 = d1 + h2 - k3
    t4 = (po < 0.0) and 2.0 / t4 or t4
    local t = math.huge
    if t1 > 0.0 then t = t1 end
    if t2 > 0.0 then t = math.min(t, t2) end
    if t3 > 0.0 then t = math.min(t, t3) end
    if t4 > 0.0 then t = math.min(t, t4) end
    return t > 0 and t or nil
end

function mathT.rayCapsule(ray, topX, topY, topZ, baseX, baseY, baseZ, radius)
    local dot = mathT.dot
    local baX, baY, baZ = baseX - topX, baseY - topY, baseZ - topZ
    local oaX, oaY, oaZ = ray.position.x - topX, ray.position.y - topY, ray.position.z - topZ
    local baba = dot(baX, baY, baZ, baX, baY, baZ)
    local bard = dot(baX, baY, baZ, ray.direction.x, ray.direction.y, ray.direction.z)
    local baoa = dot(baX, baY, baZ, oaX, oaY, oaZ)
    local rdoa = dot(ray.direction.x, ray.direction.y, ray.direction.z, oaX, oaY, oaZ)
    local oaoa = dot(oaX, oaY, oaZ, oaX, oaY, oaZ)
    local a = baba - bard * bard
    local b = baba * rdoa - baoa * bard
    local c = baba * oaoa - baoa * baoa - radius * radius * baba
    local h = b * b - a * c
    if h >= 0.0 then
        local t = (-b - math.sqrt(h)) / a
        local y = baoa + t * bard
        if y > 0.0 and y < baba then
            return t
        end
        local oc = y <= 0.0 and vec3(oaX, oaY, oaZ) or
            mathT.TempVec3(ray.position.x - baseX, ray.position.y - baseY, ray.position.z - baseZ)
        b = dot(ray.direction.x, ray.direction.y, ray.direction.z, oc.x, oc.y, oc.z)
        c = dot(oc.x, oc.y, oc.z, oc.x, oc.y, oc.z) - radius * radius
        h = b * b - c
        if h > 0 then
            return -b - math.sqrt(h)
        end
    end
end

function mathT.rayCylinder(ray, topX, topY, topZ, baseX, baseY, baseZ, radius)
    local dot = mathT.dot
    local baX, baY, baZ = baseX - topX, baseY - topY, baseZ - topZ
    local ocX, ocY, ocZ = ray.position.x - topX, ray.position.y - topY, ray.position.z - topZ
    local baba = dot(baX, baY, baZ, baX, baY, baZ)
    local bard = dot(baX, baY, baZ, ray.direction.x, ray.direction.y, ray.direction.z)
    local baoc = dot(baX, baY, baZ, ocX, ocY, ocZ)
    local k2 = baba - bard * bard
    local k1 = baba * dot(ocX, ocY, ocZ, ray.direction.x, ray.direction.y, ray.direction.z) - baoc * bard
    local k0 = baba * dot(ocX, ocY, ocZ, ocX, ocY, ocZ) - baoc * baoc - radius * radius * baba
    local h = k1 * k1 - k2 * k0
    if h < 0 then
        return
    end
    h = math.sqrt(h)
    local t = (-k1 - h) / k2
    local y = baoc + t * bard

    if y > 0 and y < baba then
        return t, (vec3(ocX, ocY, ocZ) + t * ray.direction - vec3(baX, baY, baZ) * y / baba) / radius
    end

    t = (((y < 0) and 0 or baba) - baoc) / bard
    if math.abs(k1 + k2 * t) < h then
        return t, vec3(baX, baY, baZ) * mathT.sign(y) / math.sqrt(baba)
    end
    return
end

function mathT.raySphere(ray, x, y, z, radius)
    local ox, oy, oz = ray.position.x - x, ray.position.y - y, ray.position.z - z
    local dx, dy, dz = ray.direction.x, ray.direction.y, ray.direction.z

    local a = dx * dx + dy * dy + dz * dz
    local b = 2 * (dx * ox + dy * oy + dz * oz)
    local c = ox * ox + oy * oy + oz * oz - radius * radius
    local d = b * b - 4 * a * c

    if (d >= 0) then
        local dist = (-b - math.sqrt(d)) / (2 * a)

        if (dist >= 0) then
            local hitPos = ray.position + ray.direction * dist
            local normal = hitPos - mathT.TempVec3(x, y, z)
            return dist, hitPos, normal:normalize()
        end
    end
end

--- checks if a ray intersects with an AABB
---@param rayX number
---@param rayY number
---@param rayZ number
---@param rayDirX number
---@param rayDirY number
---@param rayDirZ number
---@param minX number box minimum bounds
---@param minY number
---@param minZ number
---@param maxX number box maximum bounds
---@param maxY number
---@param maxZ number
---@return boolean, number, number #hit, distance, depth
function mathT.rayAABB(rayX, rayY, rayZ, rayDirX, rayDirY, rayDirZ, minX, minY, minZ, maxX, maxY, maxZ)
    local t0X, t0Y, t0Z = (minX - rayX) / rayDirX, (minY - rayY) / rayDirY, (minZ - rayZ) / rayDirZ
    local t1X, t1Y, t1Z = (maxX - rayX) / rayDirX, (maxY - rayY) / rayDirY, (maxZ - rayZ) / rayDirZ
    local tminX, tminY, tminZ = math.min(t0X, t1X), math.min(t0Y, t1Y), math.min(t0Z, t1Z)
    local tmaxX, tmaxY, tmaxZ = math.max(t0X, t1X), math.max(t0Y, t1Y), math.max(t0Z, t1Z)

    local tNear = math.max(tminX, tminY, tminZ, 0.0)
    local tFar = math.min(tmaxX, tmaxY, tmaxZ)

    return tFar - tNear > 0, tNear, tFar - tNear
end

--- same as mathT.rayAABB but with 1 / rayDir instead of rayDir
---@param rayX number
---@param rayY number
---@param rayZ number
---@param rayIDirX number
---@param rayIDirY number
---@param rayIDirZ number
---@param minX number box minimum bounds
---@param minY number
---@param minZ number
---@param maxX number box maximum bounds
---@param maxY number
---@param maxZ number
---@return boolean, number, number #hit, distance, depth
function mathT.rayAABBInverse(rayX, rayY, rayZ, rayIDirX, rayIDirY, rayIDirZ, minX, minY, minZ, maxX, maxY, maxZ)
    local t0X, t0Y, t0Z = (minX - rayX) * rayIDirX, (minY - rayY) * rayIDirY, (minZ - rayZ) * rayIDirZ
    local t1X, t1Y, t1Z = (maxX - rayX) * rayIDirX, (maxY - rayY) * rayIDirY, (maxZ - rayZ) * rayIDirZ
    local tminX, tminY, tminZ = math.min(t0X, t1X), math.min(t0Y, t1Y), math.min(t0Z, t1Z)
    local tmaxX, tmaxY, tmaxZ = math.max(t0X, t1X), math.max(t0Y, t1Y), math.max(t0Z, t1Z)

    local tNear = math.max(tminX, tminY, tminZ, 0.0)
    local tFar = math.min(tmaxX, tmaxY, tmaxZ)

    return tFar - tNear > 0, tNear, tFar - tNear
end

function mathT.triangleTangent(p1, p2, p3)
    local edge1X, edge1Y, edge1Z = p2[1] - p1[1], p2[2] - p1[2], p2[3] - p1[3]
    local edge2X, edge2Y, edge2Z = p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3]

    local deltaUV1X, deltaUV1Y = p2[4] - p1[4], p2[5] - p1[5]
    local deltaUV2X, deltaUV2Y = p3[4] - p1[4], p3[5] - p1[5]

    local f = 1.0 / (deltaUV1X * deltaUV2Y - deltaUV2X * deltaUV1Y)

    local tangentX = f * (deltaUV2Y * edge1X - deltaUV1Y * edge2X)
    local tangentY = f * (deltaUV2Y * edge1Y - deltaUV1Y * edge2Y)
    local tangentZ = f * (deltaUV2Y * edge1Z - deltaUV1Y * edge2Z)

    local i = 1 / math.sqrt(tangentX * tangentX + tangentY * tangentY + tangentZ * tangentZ)

    return tangentX * i, tangentY * i, tangentZ * i
end

function mathT.newScaleMatrix(scale)
    local mat = mat4()
    mat[1][1] = scale.x
    mat[2][2] = scale.y
    mat[3][3] = scale.z
    return mat
end

function mathT.scaleFromMatrix(matrix)
    return mathT.length3(matrix[1][1], matrix[1][2], matrix[1][3]),
        mathT.length3(matrix[2][1], matrix[2][2], matrix[2][3]),
        mathT.length3(matrix[3][1], matrix[3][2], matrix[3][3])
end

function mathT.slerp(qa, qb, t)
    local qm = quaternion()
    local cosHalfTheta = qa.w * qb.w + qa.x * qb.x + qa.y * qb.y + qa.z * qb.z
    if math.abs(cosHalfTheta) >= 1.0 then
        qm.w = qa.w
        qm.x = qa.x
        qm.y = qa.y
        qm.z = qa.z
        return qm
    end
    local halfTheta = math.acos(cosHalfTheta)
    local sinHalfTheta = math.sqrt(1.0 - cosHalfTheta * cosHalfTheta)
    if math.abs(sinHalfTheta) < 0.001 then
        qm.w = (qa.w * 0.5 + qb.w * 0.5)
        qm.x = (qa.x * 0.5 + qb.x * 0.5)
        qm.y = (qa.y * 0.5 + qb.y * 0.5)
        qm.z = (qa.z * 0.5 + qb.z * 0.5)
        return qm
    end
    local ratioA = math.sin((1 - t) * halfTheta) / sinHalfTheta
    local ratioB = math.sin(t * halfTheta) / sinHalfTheta
    qm.w = (qa.w * ratioA + qb.w * ratioB)
    qm.x = (qa.x * ratioA + qb.x * ratioB)
    qm.y = (qa.y * ratioA + qb.y * ratioB)
    qm.z = (qa.z * ratioA + qb.z * ratioB)
    return qm
end

function mathT.newTransform(translation, rotation, scale)
    local scaleMatrix = mat4({
        { scale.x, 0,       0,       0 },
        { 0,       scale.y, 0,       0 },
        { 0,       0,       scale.z, 0 },
        { 0,       0,       0,       1 }
    })

    local rotationMatrix = mathT.quaternionToMatrix(rotation)

    local rotationScaleMatrix = rotationMatrix * scaleMatrix

    rotationScaleMatrix[4][1] = translation.x
    rotationScaleMatrix[4][2] = translation.y
    rotationScaleMatrix[4][3] = translation.z

    return rotationScaleMatrix
end
