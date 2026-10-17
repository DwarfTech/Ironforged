-- Ironforged: compact, length-prefixed serializer.
-- Strings carry their byte length, so no escaping is needed and any text round-trips exactly.
local ADDON, ns = ...
ns = ns or {}

local Ser = {}
ns.Ser = Ser

local type, tostring, tonumber, pairs = type, tostring, tonumber, pairs
local format, sub, find, concat = string.format, string.sub, string.find, table.concat

local MAX_DEPTH = 12

local function encodeNumber(n)
  if n == math.floor(n) and n > -1e15 and n < 1e15 then
    return format("%d", n)
  end
  return format("%.17g", n)
end

local function write(v, out, depth)
  if depth > MAX_DEPTH then error("serializer: nesting too deep") end
  local t = type(v)
  if t == "string" then
    out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("serializer: bad number") end
    out[#out + 1] = "n" .. encodeNumber(v) .. ";"
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif t == "table" then
    out[#out + 1] = "{"
    for k, val in pairs(v) do
      local kt = type(k)
      if (kt == "string" or kt == "number") and type(val) ~= "function" and type(val) ~= "userdata" then
        write(k, out, depth + 1)
        write(val, out, depth + 1)
      end
    end
    out[#out + 1] = "}"
  else
    error("serializer: cannot encode " .. t)
  end
end

function Ser.Encode(v)
  local out = {}
  write(v, out, 0)
  return concat(out)
end

local function read(s, pos, depth)
  if depth > MAX_DEPTH then error("deserializer: nesting too deep") end
  local c = sub(s, pos, pos)
  if c == "s" then
    local colon = find(s, ":", pos + 1, true)
    if not colon then error("deserializer: bad string") end
    local len = tonumber(sub(s, pos + 1, colon - 1))
    if not len or len < 0 then error("deserializer: bad length") end
    local stop = colon + len
    if stop > #s then error("deserializer: truncated string") end
    return sub(s, colon + 1, stop), stop + 1
  elseif c == "n" then
    local semi = find(s, ";", pos + 1, true)
    if not semi then error("deserializer: bad number") end
    local n = tonumber(sub(s, pos + 1, semi - 1))
    if not n then error("deserializer: bad number") end
    return n, semi + 1
  elseif c == "T" then
    return true, pos + 1
  elseif c == "F" then
    return false, pos + 1
  elseif c == "{" then
    local tbl = {}
    pos = pos + 1
    while true do
      if pos > #s then error("deserializer: unterminated table") end
      if sub(s, pos, pos) == "}" then return tbl, pos + 1 end
      local k, v
      k, pos = read(s, pos, depth + 1)
      v, pos = read(s, pos, depth + 1)
      if type(k) == "table" then error("deserializer: table key") end
      tbl[k] = v
    end
  end
  error("deserializer: unexpected '" .. tostring(c) .. "'")
end

-- Returns value or nil, err. Never throws.
function Ser.Decode(s)
  if type(s) ~= "string" or s == "" then return nil, "empty" end
  local ok, v, pos = pcall(read, s, 1, 0)
  if not ok then return nil, v end
  if pos ~= #s + 1 then return nil, "trailing data" end
  return v
end

-- Optional compression via the client's C_EncodingUtil (Deflate + Base64).
-- Falls back to the raw encoding if the API is missing or errors.
local function hasCodec()
  local E = _G.C_EncodingUtil
  return E and E.CompressString and E.DecompressString and E.EncodeBase64 and E.DecodeBase64
end

function Ser.Pack(v)
  local raw = Ser.Encode(v)
  if #raw > 300 and hasCodec() then
    local ok, packed = pcall(function()
      local E = C_EncodingUtil
      local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
      return E.EncodeBase64(E.CompressString(raw, method))
    end)
    if ok and type(packed) == "string" and #packed + 1 < #raw then
      return "Z" .. packed
    end
  end
  return "R" .. raw
end

function Ser.Unpack(s)
  if type(s) ~= "string" or #s < 2 then return nil, "empty" end
  local flag, body = sub(s, 1, 1), sub(s, 2)
  if flag == "R" then
    return Ser.Decode(body)
  elseif flag == "Z" then
    if not hasCodec() then return nil, "no codec" end
    local ok, raw = pcall(function()
      local E = C_EncodingUtil
      local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
      return E.DecompressString(E.DecodeBase64(body), method)
    end)
    if not ok or type(raw) ~= "string" then return nil, "decompress failed" end
    return Ser.Decode(raw)
  end
  return nil, "unknown format"
end
