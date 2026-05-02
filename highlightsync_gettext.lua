-- This module is adapted from assistant.koplugin/assistant_gettext.lua
-- which is in turn based on koreader frontend/gettext.lua
--
--[[--
A pure Lua implementation of a gettext subset for highlightsync.koplugin.
--]]

local logger = require("logger")

local GetText = {
    context = {},
    translation = {},
    current_lang = "C",
    dirname = "l10n",
    textdomain = "koreader",
    plural_default = "n != 1",
}

local GetText_mt = {
    __index = {}
}

GetText.wrapUntranslated_nowrap = function(text) return text end
GetText.wrapUntranslated = GetText.wrapUntranslated_nowrap

function GetText_mt.__call(gettext, msgid)
    return gettext.translation[msgid] and gettext.translation[msgid][0] or gettext.translation[msgid] or gettext.wrapUntranslated(msgid)
end

local function c_escape(what_full, what)
    if what == "\n" then return ""
    elseif what == "a" then return "\a"
    elseif what == "b" then return "\b"
    elseif what == "f" then return "\f"
    elseif what == "n" then return "\n"
    elseif what == "r" then return "\r"
    elseif what == "t" then return "\t"
    elseif what == "v" then return "\v"
    elseif what == "0" then return "\0"
    else
        return what_full
    end
end

local function logicalCtoLua(logical_str)
    logical_str = logical_str:gsub("&&", "and")
    logical_str = logical_str:gsub("!=", "~=")
    logical_str = logical_str:gsub("||", "or")
    return logical_str
end

local function getDefaultPlural(n)
    if n ~= 1 then
        return 1
    else
        return 0
    end
end

local function getPluralFunc(pl_tests, nplurals, plural_default)
    local plural_func_str = "return function(n) if "

    if #pl_tests > 1 then
        for i = 1, #pl_tests do
            local pl_test = pl_tests[i]
            pl_test = logicalCtoLua(pl_test)

            if i > 1 and tonumber(pl_test) == nil then
                pl_test = " elseif "..pl_test
            end
            if tonumber(pl_test) ~= nil then
                pl_test = " else return "..pl_test
            end
            pl_test = pl_test:gsub("?", " then return")

            plural_func_str = plural_func_str..pl_test
        end
        plural_func_str = plural_func_str.." end end"
    else
        local pl_test = pl_tests[1]
        if pl_test == plural_default then
            return getDefaultPlural
        end
        if tonumber(pl_test) ~= nil then
            plural_func_str = "return function(n) return "..pl_test.." end"
        else
            pl_test = logicalCtoLua(pl_test)
            plural_func_str = "return function(n) if "..pl_test.." then return 1 else return 0 end end"
        end
    end
    logger.dbg("gettext: plural function", plural_func_str)
    return loadstring(plural_func_str)()
end

local function addTranslation(msgctxt, msgid, msgstr, n)
    local unescaped_string = string.gsub(msgstr, "(\\(.))", c_escape)
    if msgctxt and msgctxt ~= "" then
        if not GetText.context[msgctxt] then
            GetText.context[msgctxt] = {}
        end
        if n then
            if not GetText.context[msgctxt][msgid] then
                GetText.context[msgctxt][msgid] = {}
            end
            GetText.context[msgctxt][msgid][n] = unescaped_string ~= "" and unescaped_string or nil
        else
            GetText.context[msgctxt][msgid] = unescaped_string ~= "" and unescaped_string or nil
        end
    else
        if n then
            if not GetText.translation[msgid] then
                GetText.translation[msgid] = {}
            end
            GetText.translation[msgid][n] = unescaped_string ~= "" and unescaped_string or nil
        else
            GetText.translation[msgid] = unescaped_string ~= "" and unescaped_string or nil
        end
    end
end

function GetText_mt.__index.changeLang(new_lang)
    GetText.context = {}
    GetText.translation = {}
    GetText.current_lang = "C"

    if new_lang == "C" or new_lang == nil or new_lang == ""
       or new_lang:match("^en_US") == "en_US" then 
        return 
    end

    -- Strip encoding suffix if present (e.g., "zh_CN.UTF-8" -> "zh_CN")
    local dot_pos = new_lang:find("%.")
    if dot_pos then
        new_lang = new_lang:sub(1, dot_pos - 1)
    end

    local file = GetText.dirname .. "/" .. new_lang .. "/" .. GetText.textdomain .. ".po"
    local po = io.open(file, "r")

    if not po then
        logger.dbg("highlightsync: cannot open translation file:", file)
        return false
    end
    logger.info("highlightsync: successfully opened translation file:", file)
    print("highlightsync: successfully opened translation file:", file)

    local data = {}
    local fuzzy = false
    local headers
    local what = nil
    while true do
        local line = po:read("*l")
        if line then
            line = line:gsub("\r$", "")
        end
        if line == nil or line == "" then
            if data.msgid and data.msgid_plural and data["msgstr[0]"] then
                for k, v in pairs(data) do
                    local n = tonumber(k:match("msgstr%[([0-9]+)%]"))
                    local msgstr = v

                    if n and msgstr then
                        addTranslation(data.msgctxt, data.msgid, msgstr, n)
                    end
                end
            elseif data.msgid and data.msgstr and data.msgstr ~= "" then
                if not headers and data.msgid == "" then
                    headers = data.msgstr
                    local plural_forms = data.msgstr:match("Plural%-Forms: (.*)")
                    
                    -- Guard against missing Plural-Forms header
                    if not plural_forms then
                        GetText.getPlural = getDefaultPlural
                    else
                        local nplurals = plural_forms:match("nplurals=([0-9]+);") or 2
                        local plurals = plural_forms:match("plural=%((.*)%);")

                        if plurals == "n == 1) ? 0 : ((n == 2) ? 1 : ((n > 10 && n % 10 == 0) ? 2 : 3)" then
                            plurals = "n == 1 ? 0 : (n == 2) ? 1 : (n > 10 && n % 10 == 0) ? 2 : 3"
                        end
                        if plurals == "n % 10 == 0 || n % 100 >= 11 && n % 100 <= 19) ? 0 : ((n % 10 == 1 && n % 100 != 11) ? 1 : 2" then
                            plurals = "n % 10 == 0 || n % 100 >= 11 && n % 100 <= 19 ? 0 : (n % 10 == 1 && n % 100 != 11) ? 1 : 2"
                        end
                        if plurals == "n == 1) ? 0 : ((n == 0 || n != 1 && n % 100 >= 1 && n % 100 <= 19) ? 1 : 2" then
                            plurals = "n == 1 ? 0 : (n == 0 || n != 1 && n % 100 >= 1 && n % 100 <= 19) ? 1 : 2"
                        end

                        if not plurals then
                            plurals = plural_forms:match("plural=(.*);")
                        end

                        if plurals and plurals:find("[^n!=%%<>&:()|?0-9 ]") then
                            plurals = GetText.plural_default
                        end

                        local pl_tests = {}
                        if plurals then
                            for pl_test in plurals:gmatch("[^:]+") do
                                table.insert(pl_tests, pl_test)
                            end
                        end

                        GetText.getPlural = getPluralFunc(pl_tests, nplurals, GetText.plural_default)
                        if not GetText.getPlural then
                            GetText.getPlural = getDefaultPlural
                        end
                    end
                end

                addTranslation(data.msgctxt, data.msgid, data.msgstr)
            end
            if line == nil then break end
            data = {}
            what = nil
        else
            if not line:match("^#") then
                local w, s = line:match("^%s*([%a_%[%]0-9]+)%s+\"(.*)\"%s*$")
                if w then
                    what = w
                else
                    s = line:match("^%s*\"(.*)\"%s*$")
                end
                if what and s and not fuzzy then
                    -- Single-pass string unescape (more efficient than 3 separate gsub)
                    s = s:gsub("\\([n\"\\\\])", function(c)
                        if c == "n" then return "\n"
                        elseif c == '"' then return '"'
                        else return "\\"
                        end
                    end)
                    data[what] = (data[what] or "") .. s
                elseif what and s == "" and fuzzy then
                    -- Ignore fuzzy entries
                else
                    fuzzy = false
                end
            elseif line:match("#, fuzzy") then
                fuzzy = true
            end
        end
    end
    po:close()
    GetText.current_lang = new_lang
end

GetText_mt.__index.getPlural = getDefaultPlural

function GetText_mt.__index.ngettext(msgid, msgid_plural, n)
    local plural = GetText.getPlural(n)

    if plural == 0 then
        return GetText.translation[msgid] and GetText.translation[msgid][plural] or GetText.wrapUntranslated(msgid)
    else
        return GetText.translation[msgid] and GetText.translation[msgid][plural] or GetText.wrapUntranslated(msgid_plural)
    end
end

function GetText_mt.__index.npgettext(msgctxt, msgid, msgid_plural, n)
    local plural = GetText.getPlural(n)

    if plural == 0 then
        return GetText.context[msgctxt] and GetText.context[msgctxt][msgid] and GetText.context[msgctxt][msgid][plural] or GetText.wrapUntranslated(msgid)
    else
        return GetText.context[msgctxt] and GetText.context[msgctxt][msgid] and GetText.context[msgctxt][msgid][plural] or GetText.wrapUntranslated(msgid_plural)
    end
end

function GetText_mt.__index.pgettext(msgctxt, msgid)
    return GetText.context[msgctxt] and GetText.context[msgctxt][msgid] or GetText.wrapUntranslated(msgid)
end

setmetatable(GetText, GetText_mt)

-- highlightsync.koplugin specific setup
GetText.dirname = require("datastorage"):getDataDir() .. "/plugins/highlightsync.koplugin/l10n"

local function loadCurrentLang()
    local ok, err = pcall(function()
        local lang = require("gettext").current_lang
        if lang:match("^zh_Hans") then
            lang = "zh_CN"
        elseif lang:match("^zh_Hant") then
            lang = "zh_TW"
        end
        GetText.changeLang(lang)
    end)
    if not ok then
        logger.err("highlightsync: ERROR in loadCurrentLang:", err)
    end
end

loadCurrentLang()

return GetText
