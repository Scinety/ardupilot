local PARAM_TABLE_KEY    = 26
local PARAM_TABLE_PREFIX = "WQ_"
local port               = serial:find_serial(0)
assert(port, 'No scripting serial port found!')
-- ============================================
-- 参数化配置
-- ============================================
local function add_param(name, idx, default_value)
    assert(param:add_param(PARAM_TABLE_KEY, idx, name, default_value),
        string.format("WQ: could not add param %s", name))
end
assert(param:add_table(PARAM_TABLE_KEY, PARAM_TABLE_PREFIX, 30), "WQ: could not add param table")
-- 基本参数
add_param('BAUD',     0, 9600)
add_param('INTERVAL', 1, 2000)
add_param('TIMEOUT',  2, 5000)
add_param('LOG_EN',   3, 1)      -- 启用SD卡日志
-- 报警阈值参数
add_param('PH_MIN',   4, 6.0)
add_param('PH_MAX',   5, 9.0)
add_param('O2_MIN',   6, 5.0)
add_param('TEMP_MAX', 7, 40.0)
add_param('NTU_MAX',  8, 500.0)
add_param('NH3_MAX',  9, 1.5)
-- 读取配置
local SENSOR_BAUD      = param:get(PARAM_TABLE_PREFIX .. 'BAUD')
local SEND_INTERVAL_MS = param:get(PARAM_TABLE_PREFIX .. 'INTERVAL')
local SENSOR_TIMEOUT   = param:get(PARAM_TABLE_PREFIX .. 'TIMEOUT')
local LOG_ENABLED      = param:get(PARAM_TABLE_PREFIX .. 'LOG_EN') > 0
port:begin(uint32_t(SENSOR_BAUD))
port:set_flow_control(0)
-- ============================================
-- 传感器定义
-- ============================================
local SENSORS = {
    [0x01] = 'COD',
    [0x02] = 'NH3',
    [0x03] = 'O2',
    [0x04] = 'NTU',
    [0x05] = 'COND',
    [0x06] = 'PH',
    [0x07] = 'ORP',
    [0x08] = 'CHLO',
    [0x09] = 'ALGE',
    [0x0A] = 'OIL',
}
-- 用于表头排序
local SENSOR_ORDER = {'COD', 'NH3', 'O2', 'NTU', 'COND', 'PH', 'ORP', 'CHLO', 'ALGE', 'OIL'}
-- 扩展参数名称（包括子参数）
local ALL_COLUMNS = {'time', 'lat', 'lon'}
-- 从SENSOR_ORDER和RESPONSES中收集所有可能的参数名
local PARAM_NAMES = {
    'COD', 'TOC', 'NH3', 'O2', 'SAT', 'NTU', 'COND',
    'PH', 'ORP', 'CHLO', 'ALGE', 'OIL', 'TEMP', 'MV'
}

for _, name in ipairs(PARAM_NAMES) do
    ALL_COLUMNS[#ALL_COLUMNS + 1] = name
end

local COMMANDS = {
    { 0x01, 0x03, 0x26, 0x00, 0x00, 0x08, 0x4F, 0x44 },
    { 0x01, 0x03, 0x12, 0x00, 0x00, 0x02, 0xC1, 0x73 },
    { 0x02, 0x03, 0x28, 0x00, 0x00, 0x02, 0xCD, 0x98 },
    { 0x02, 0x03, 0x26, 0x00, 0x00, 0x04, 0x4F, 0x72 },
    { 0x03, 0x03, 0x26, 0x00, 0x00, 0x06, 0xCF, 0x62 },
    { 0x04, 0x03, 0x26, 0x00, 0x00, 0x04, 0x4F, 0x14 },
    { 0x05, 0x03, 0x26, 0x00, 0x00, 0x04, 0x4E, 0xC5 },
    { 0x06, 0x03, 0x26, 0x00, 0x00, 0x04, 0x4E, 0xF6 },
    { 0x06, 0x03, 0x24, 0x00, 0x00, 0x02, 0xCF, 0x4C },
    { 0x07, 0x03, 0x26, 0x00, 0x00, 0x04, 0x4F, 0x27 },
    { 0x07, 0x03, 0x24, 0x00, 0x00, 0x02, 0xCE, 0x9D },
    { 0x08, 0x03, 0x26, 0x00, 0x00, 0x04, 0x4F, 0xD8 },
    { 0x09, 0x03, 0x26, 0x00, 0x00, 0x04, 0x4E, 0x09 },
    { 0x0A, 0x03, 0x26, 0x00, 0x00, 0x04, 0x4E, 0x3A },
}

local RESPONSES = {
    [0x010310] = { 'TEMP', 'COD', '', 'TOC' },
    [0x010304] = { 'NTU' },
    [0x020304] = { 'NH3' },
    [0x020308] = { '', 'PH' },
    [0x03030C] = { 'TEMP', 'SAT', 'O2' },
    [0x040308] = { 'TEMP', 'NTU' },
    [0x050308] = { 'TEMP', 'COND' },
    [0x060308] = { 'MV', 'PH' },
    [0x060304] = { 'TEMP' },
    [0x070308] = { 'ORP', 'PH' },
    [0x070304] = { 'TEMP' },
    [0x080308] = { 'TEMP', 'CHLO' },
    [0x090308] = { 'TEMP', 'ALGE' },
    [0x0A0308] = { 'TEMP', 'OIL' },
}

-- ============================================
-- 数据验证范围
-- ============================================
local VALID_RANGES = {
    PH   = {min=0, max=14},
    TEMP = {min=-10, max=60},
    O2   = {min=0, max=20},
    SAT  = {min=0, max=200},
    NTU  = {min=0, max=4000},
    COND = {min=0, max=100000},
    ORP  = {min=-500, max=500},
    NH3  = {min=0, max=100},
    COD  = {min=0, max=500},
    TOC  = {min=0, max=500},
    CHLO = {min=0, max=500},
    ALGE = {min=0, max=100000},
    OIL  = {min=0, max=100},
    MV   = {min=-1000, max=1000},
}

-- ============================================
-- 状态变量
-- ============================================
local sensor_status = {}
for id, name in pairs(SENSORS) do
    sensor_status[name] = { online = false, last_seen = 0, error_count = 0 }
end
local last_sensor_activity = 0

-- 当前数据缓存
local current_data = {}

-- SD卡日志相关
local log_file = nil
local log_file_created = false
local gps_locked = false
local last_log_time = 0
local LOG_INTERVAL_MS = 2000  -- 2秒记录一次

-- ============================================
-- 工具函数
-- ============================================
local function slice(tbl, first, last)
    local sliced = {}
    for i = first or 1, last or #tbl do
        sliced[#sliced + 1] = tbl[i]
    end
    return sliced
end

local function modbus_crc(buf)
    local crc = 0xFFFF
    for pos = 1, #buf do
        crc = crc ~ buf[pos]
        for _ = 1, 8 do
            if crc & 0x0001 ~= 0 then
                crc = crc >> 1
                crc = crc ~ 0xA001
            else
                crc = crc >> 1
            end
        end
    end
    return { crc & 0xFF, crc >> 8 }
end

local function check_crc(buf)
    local msg = slice(buf, 1, #buf - 2)
    local crc = modbus_crc(msg)
    return crc[1] == buf[#buf - 1] and crc[2] == buf[#buf]
end

local function pack_int(buf)
    if #buf == 0 then return 0 end
    local i = 0
    for n = 1, #buf do
        i = i << 8 | buf[n]
    end
    return i
end

local function unpack_float(buf)
    if #buf < 4 then return 0 end
    local i = pack_int(buf)
    local s = string.pack('>i4', i)
    return string.unpack('f', s)
end

local function serial_write(cmd)
    for i = 1, #cmd do
        port:write(cmd[i])
    end
end

-- ============================================
-- 数据验证
-- ============================================
local function validate_value(name, value)
    if value ~= value then return false end  -- NaN
    if value == math.huge or value == -math.huge then return false end
    local range = VALID_RANGES[name]
    if range then
        if value < range.min or value > range.max then return false end
    end
    return true
end

-- ============================================
-- 报警检测
-- ============================================
local alert_sent = {}

local function check_alerts(name, value)
    local is_alert = false
    local msg = nil

    if name == 'PH' then
        local ph_min = param:get(PARAM_TABLE_PREFIX .. 'PH_MIN')
        local ph_max = param:get(PARAM_TABLE_PREFIX .. 'PH_MAX')
        if value < ph_min then
            is_alert = true
            msg = string.format('PH过低: %.1f < %.1f', value, ph_min)
        elseif value > ph_max then
            is_alert = true
            msg = string.format('PH过高: %.1f > %.1f', value, ph_max)
        end
    elseif name == 'O2' then
        local o2_min = param:get(PARAM_TABLE_PREFIX .. 'O2_MIN')
        if value < o2_min then
            is_alert = true
            msg = string.format('溶解氧过低: %.1f < %.1f', value, o2_min)
        end
    elseif name == 'TEMP' then
        local temp_max = param:get(PARAM_TABLE_PREFIX .. 'TEMP_MAX')
        if value > temp_max then
            is_alert = true
            msg = string.format('温度过高: %.1f > %.1f', value, temp_max)
        end
    elseif name == 'NTU' then
        local ntu_max = param:get(PARAM_TABLE_PREFIX .. 'NTU_MAX')
        if value > ntu_max then
            is_alert = true
            msg = string.format('浊度过高: %.1f > %.1f', value, ntu_max)
        end
    elseif name == 'NH3' then
        local nh3_max = param:get(PARAM_TABLE_PREFIX .. 'NH3_MAX')
        if value > nh3_max then
            is_alert = true
            msg = string.format('氨氮过高: %.2f > %.2f', value, nh3_max)
        end
    end

    if is_alert and not alert_sent[name] then
        gcs:send_text(2, 'WQ报警: ' .. msg)
        alert_sent[name] = true
    elseif not is_alert then
        alert_sent[name] = nil
    end
end

-- ============================================
-- 传感器状态更新
-- ============================================
local function update_sensor_status(name, success)
    local status = sensor_status[name]
    if not status then return end
    if success then
        status.online = true
        status.last_seen = millis()
        status.error_count = 0
    else
        status.error_count = status.error_count + 1
        if status.error_count > 5 and status.online then
            gcs:send_text(4, 'WQ: ' .. name .. ' 离线')
            status.online = false
        end
    end
end

-- ============================================
-- SD卡文件日志
-- ============================================
local function get_utc_time()
    -- 尝试从GPS获取UTC时间
    local week = gps:time_week()
    local week_ms = gps:time_week_ms()
    
    if week > 0 and week_ms > 0 then
        -- GPS时间可用，转换为UTC
        -- GPS纪元: 1980-01-06 00:00:00 UTC
        -- 计算从GPS纪元到现在的秒数
        local gps_seconds = week * 604800 + week_ms / 1000
        
        -- 转换为Unix时间戳 (GPS纪元到Unix纪元的偏移: 315964800秒)
        local unix_seconds = gps_seconds + 315964800
        
        -- 计算日期
        local days = math.floor(unix_seconds / 86400)
        local remaining = unix_seconds % 86400
        local hours = math.floor(remaining / 3600)
        remaining = remaining % 3600
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        
        -- 计算年月日 (从1970-01-01开始)
        local y = 1970
        local m = 1
        local d = days + 1  -- 从1开始
        
        -- 简化的日期计算
        local days_in_year = 365
        while d > days_in_year do
            d = d - days_in_year
            y = y + 1
            -- 闰年判断
            if (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0) then
                days_in_year = 366
            else
                days_in_year = 365
            end
        end
        
        local days_in_month = {31,28,31,30,31,30,31,31,30,31,30,31}
        if (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0) then
            days_in_month[2] = 29
        end
        
        while d > days_in_month[m] do
            d = d - days_in_month[m]
            m = m + 1
        end
        
        return y, m, d, hours, mins, secs
    end
    
    -- GPS时间不可用，使用RTC或boot时间
    -- 尝试使用rtc:gmtime()
    local ok, rtc_time = pcall(rtc.get, rtc)
    if ok and rtc_time then
        return rtc_time:year(), rtc_time:month(), rtc_time:day(),
               rtc_time:hour(), rtc_time:min(), rtc_time:sec()
    end
    
    -- 最后使用boot时间 (简化处理)
    local boot_secs = math.floor(millis() / 1000)
    local hours = math.floor(boot_secs / 3600) % 24
    local mins = math.floor(boot_secs / 60) % 60
    local secs = boot_secs % 60
    return 2024, 1, 1, hours, mins, secs
end

local function get_log_filename()
    local y, m, d, h, min, s = get_utc_time()
    -- 格式: YYMMDDHHMM.txt (每分钟一个文件)
    local filename = string.format("WQ%02d%02d%02d%02d%02d.txt", y % 100, m, d, h, min)
    return filename
end

local function open_log_file()
    if not LOG_ENABLED then return false end
    
    local filename = get_log_filename()
    local filepath = '/APM/LOG/' .. filename
    
    -- 检查是否需要创建新文件
    if current_log_date ~= filename then
        -- 关闭旧文件
        if log_file then
            log_file:close()
            log_file = nil
        end
        
        -- 打开新文件
        log_file = io.open(filepath, 'a')
        if not log_file then
            gcs:send_text(3, 'WQ: 无法创建日志文件 ' .. filepath)
            return false
        end
        
        -- 写入表头
        local header = table.concat(ALL_COLUMNS, ',')
        log_file:write(header .. '\n')
        log_file:flush()
        
        current_log_date = filename
        gcs:send_text(6, 'WQ: 日志文件 ' .. filename .. ' 已创建')
    end
    
    return true
end

local function write_log_entry()
    if not LOG_ENABLED then return end
    if not open_log_file() then return end
    if not log_file then return end
    
    -- 构建数据行
    local values = {}
    for _, col_name in ipairs(ALL_COLUMNS) do
        if col_name == 'time' then
            -- 时间: 使用UTC时间 HH:MM:SS格式
            local y, m, d, h, min, s = get_utc_time()
            values[#values + 1] = string.format('%02d:%02d:%02d', h, min, s)
        elseif col_name == 'lat' then
            local loc = ahrs:get_position()
            if loc then
                values[#values + 1] = string.format('%.7f', loc:lat())
            else
                values[#values + 1] = '0.0000000'
            end
        elseif col_name == 'lon' then
            local loc = ahrs:get_position()
            if loc then
                values[#values + 1] = string.format('%.7f', loc:lng())
            else
                values[#values + 1] = '0.0000000'
            end
        else
            -- 水质参数
            local val = current_data[col_name]
            if val then
                values[#values + 1] = string.format('%.2f', val)
            else
                values[#values + 1] = ''
            end
        end
    end
    
    local line = table.concat(values, ',')
    log_file:write(line .. '\n')
    log_file:flush()
end

-- ============================================
-- 飞控日志记录
-- ============================================
local log_data = {}
for id, response in pairs(RESPONSES) do
    local sensor_name = SENSORS[id >> 16]
    if not log_data[sensor_name] then
        log_data[sensor_name] = {}
    end
    for _, label in pairs(response) do
        if label ~= '' then
            log_data[sensor_name][label] = 0
        end
    end
end

local function log_write(key, data)
    local labels = 'LAT,LNG'
    local units = 'ff'
    local values = {}
    for label, value in pairs(data[key]) do
        labels = labels .. ',' .. label
        units = units .. 'f'
        values[#values + 1] = value
    end
    local loc = ahrs:get_position() or Location()
    logger:write(key, labels, units, loc:lat(), loc:lng(), table.unpack(values))
end

-- ============================================
-- 数据解析
-- ============================================
local function parse(buf)
    local sensor = SENSORS[buf[1]]
    if not sensor then return false end

    local cmd = slice(buf, 1, 3)
    local fmt = RESPONSES[pack_int(cmd)]
    if fmt then
        local vals = slice(buf, 4, #buf - 2)
        local any_valid = false

        for i, label in ipairs(fmt) do
            if label ~= '' then
                local start = (i - 1) * 4 + 1
                local stop = start + 3
                local bytes = slice(vals, start, stop)
                local f = unpack_float(bytes)

                local valid = validate_value(label, f)
                if valid then
                    if label == 'COND' then
                        f = f * 1000
                    end

                    local display_label = label
                    if label ~= sensor then
                        display_label = sensor .. '_' .. label
                    end

                    -- 更新当前数据缓存
                    current_data[label] = f
                    current_data[sensor] = f  -- 也用传感器名存储
                    
                    log_data[sensor][label] = f
                    gcs:send_named_float(display_label, f)
                    check_alerts(label, f)
                    any_valid = true
                end
            end
        end

        if any_valid then
            update_sensor_status(sensor, true)
            log_write(sensor, log_data)
        end

        return true
    end
    return false
end

-- ============================================
-- 注册启用参数
-- ============================================
for idx, sensor in pairs(SENSORS) do
    add_param(sensor .. '_ENABLE', idx, 0)
end

local enabled_commands = {}
for _, command in pairs(COMMANDS) do
    if param:get(PARAM_TABLE_PREFIX .. SENSORS[command[1]] .. '_ENABLE') > 0 then
        enabled_commands[#enabled_commands + 1] = command
    end
end

local run_interval_ms = math.floor(SEND_INTERVAL_MS / math.max(#enabled_commands, 1))
local command_index = 0

-- ============================================
-- 启动自检
-- ============================================
local function self_test()
    gcs:send_text(6, 'WQ: 启动自检...')

    if not port then
        gcs:send_text(2, 'WQ: 失败 - 无串口')
        return false
    end

    local enabled_count = 0
    local enabled_list = ''
    for idx, sensor in pairs(SENSORS) do
        if param:get(PARAM_TABLE_PREFIX .. sensor .. '_ENABLE') > 0 then
            enabled_count = enabled_count + 1
            enabled_list = enabled_list .. ' ' .. sensor
        end
    end

    if enabled_count == 0 then
        gcs:send_text(4, 'WQ: 警告 - 未启用任何传感器')
    else
        gcs:send_text(6, 'WQ: 已启用:' .. enabled_list)
    end

    gcs:send_text(6, string.format('WQ: 波特率=%d 间隔=%dms 超时=%dms',
        SENSOR_BAUD, SEND_INTERVAL_MS, SENSOR_TIMEOUT))
    
    if LOG_ENABLED then
        gcs:send_text(6, 'WQ: SD卡日志已启用')
    end

    return true
end

-- ============================================
-- 主循环
-- ============================================
function update()
    local read_buffer = {}
    local bytes_read = 0

    -- 读取串口数据
    while (port:available() > 0) do
        local byte = port:read()
        if byte then
            read_buffer[#read_buffer + 1] = byte

            if #read_buffer == 1 and SENSORS[read_buffer[1]] == nil then
                read_buffer = {}
            end

            if #read_buffer >= 9 and (#read_buffer - 5) % 4 == 0 then
                if check_crc(read_buffer) and parse(read_buffer) then
                    read_buffer = {}
                    last_sensor_activity = millis()
                end
            end

            bytes_read = bytes_read + 1
            if bytes_read > 255 then
                return update, run_interval_ms
            end
        end
    end

    -- 超时检测
    if last_sensor_activity > 0 then
        local elapsed = millis() - last_sensor_activity
        if elapsed > SENSOR_TIMEOUT then
            for name, status in pairs(sensor_status) do
                if status.online then
                    gcs:send_text(4, 'WQ: ' .. name .. ' 超时离线')
                    status.online = false
                end
            end
            last_sensor_activity = 0
        end
    end

    -- SD卡日志记录 (每2秒)
    if LOG_ENABLED and (millis() - last_log_time >= LOG_INTERVAL_MS) then
        if next(current_data) then  -- 有数据才记录
            write_log_entry()
            last_log_time = millis()
        end
    end

    -- 发送查询命令
    if #enabled_commands > 0 then
        serial_write(enabled_commands[command_index + 1])
        command_index = (command_index + 1) % #enabled_commands
    end

    return update, run_interval_ms
end

-- ============================================
-- 启动
-- ============================================
if self_test() then
    gcs:send_text(6, 'WQ: 水质监测脚本已启动')
    return update()
else
    gcs:send_text(2, 'WQ: 启动失败')
    return
end
