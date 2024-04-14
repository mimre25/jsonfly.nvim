---@class EntryPosition
---@field line_number number
---@field key_start number
---@field value_start number
--
---@class Entry
---@field key string
---@field value Entry|table|number|string|boolean|nil
---@field position EntryPosition

local M = {}

---@param t table
---@return Entry[]
function M:get_entries_from_lua_json(t)
    local keys = {}

    for k, raw_value in pairs(t) do
        ---@type Entry
        local entry = {
            key = k,
            value = raw_value,
            position = {
                line_number = raw_value.newlines,
                key_start = raw_value.key_start,
                value_start = raw_value.value_start,
            }
        }
        table.insert(keys, entry)

        local v = raw_value.value

        if type(v) == "table" then
            local sub_keys = M:get_entries_from_lua_json(v)

            for _, sub_key in ipairs(sub_keys) do
                ---@type Entry
                local entry = {
                    key = k .. "." .. sub_key.key,
                    value = sub_key,
                    position = sub_key.position,
                }

                table.insert(keys, entry)
            end
        end
    end

    return keys
end

---@param result Symbol
---@return string|number|table|boolean|nil
function M:parse_lsp_value(result)
    if result.kind == 2 then
        local value = {}

        for _, child in ipairs(result.children) do
            value[child.name] = M:parse_lsp_value(child)
        end

        return value
    elseif result.kind == 16 then
        return tonumber(result.detail)
    elseif result.kind == 15 then
        return result.detail
    elseif result.kind == 18 then
        local value = {}

        for i, child in ipairs(result.children) do
            value[i] = M:parse_lsp_value(child)
        end

        return value
    elseif result.kind == 13 then
        return nil
    elseif result.kind == 17 then
        return result.detail == "true"
    end
end


---@class Symbol
---@field name string
---@field kind number 2 = Object, 16 = Number, 15 = String, 18 = Array, 13 = Null, 17 = Boolean
---@field range Range
---@field selectionRange Range
---@field detail string
---@field children Symbol[]
--
---@class Range
---@field start Position
---@field ["end"] Position
--
---@class Position
---@field line number
---@field character number
--
---@param symbols Symbol[]
---@return Entry[]
function M:get_entries_from_lsp_symbols(symbols)
    local keys = {}

    for _, symbol in ipairs(symbols) do
        local key = symbol.name

        ---@type Entry
        local entry = {
            key = key,
            value = M:parse_lsp_value(symbol),
            position = {
                line_number = symbol.range.start.line + 2,
                key_start = symbol.range.start.character + 2,
                -- The LSP doesn't return the start of the value, so we'll just assume it's 3 characters after the key
                -- We assume a default JSON file like:
                -- `"my_key": "my_value"`
                -- Since we get the end of the key, we can just add 4 to get the start of the value
                value_start = symbol.selectionRange["end"].character + 4
            }
        }
        table.insert(keys, entry)

        if symbol.kind == 2 then
            local sub_keys = M:get_entries_from_lsp_symbols(symbol.children)

            for _, sub_key in ipairs(sub_keys) do
                ---@type Entry
                local entry = {
                    key = key .. "." .. sub_key.key,
                    value = sub_key.value,
                    position = sub_key.position,
                }

                table.insert(keys, entry)
            end
        end
    end

    return keys
end

return M