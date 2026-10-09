obs = obslua

-- Main Match Layout
source_video = ""
source_home_text = ""
source_away_text = ""
source_main_scoreboard = ""
delay_ms = 1000
hide_delay_ms = 3000

-- Half-Time Layout
source_ht_video = ""
source_ht_home_text = ""
source_ht_away_text = ""
ht_delay_ms = 1000             
ht_text_hide_delay_ms = 4000   
ht_hide_delay_ms = 5000        

-- Match Timer Layout
source_timer_text = ""
timer_active = false
timer_start_minutes = 0
timer_orig_time = 0
timer_cur_time = 0
timer_cur_ns = 0

function find_scene_item(scene, name)
    local found_item = nil
    local items = obs.obs_scene_enum_items(scene)
    if items ~= nil then
        for _, item in ipairs(items) do
            local source = obs.obs_sceneitem_get_source(item)
            if obs.obs_source_get_name(source) == name then
                found_item = item
                break
            elseif obs.obs_source_is_group(source) then
                local group_scene = obs.obs_group_from_source(source)
                found_item = find_scene_item(group_scene, name)
                if found_item ~= nil then break end
            end
        end
        obs.sceneitem_list_release(items)
    end
    return found_item
end

function sync_text_source(source_from_name, source_to_name)
    local from_source = obs.obs_get_source_by_name(source_from_name)
    local to_source = obs.obs_get_source_by_name(source_to_name)
    
    if from_source ~= nil and to_source ~= nil then
        local from_settings = obs.obs_source_get_settings(from_source)
        local current_text = obs.obs_data_get_string(from_settings, "text")
        
        local to_settings = obs.obs_source_get_settings(to_source)
        obs.obs_data_set_string(to_settings, "text", current_text)
        obs.obs_source_update(to_source, to_settings)
        
        obs.obs_data_release(from_settings)
        obs.obs_data_release(to_settings)
    end
    
    if from_source ~= nil then obs.obs_source_release(from_source) end
    if to_source ~= nil then obs.obs_source_release(to_source) end
end

-- ==========================================
-- TIMER FUNCTIONS
-- ==========================================
function update_timer_display(ns_value)
    local source = obs.obs_get_source_by_name(source_timer_text)
    if source ~= nil then
        local total_ns = ns_value + (timer_start_minutes * 60 * 1000000000)
        local ms = math.floor(total_ns / 1000000)
        local total_sec = math.floor(ms / 1000)
        local m = math.floor(total_sec / 60)
        local s = total_sec % 60
        
        local text = string.format("%02d:%02d", m, s)
        
        local settings = obs.obs_data_create()
        obs.obs_data_set_string(settings, "text", text)
        obs.obs_source_update(source, settings)
        
        obs.obs_data_release(settings)
        obs.obs_source_release(source)
    end
end

function script_tick(sec)
    if not timer_active then return end
    local delta = obs.os_gettime_ns() - timer_orig_time
    timer_cur_ns = timer_cur_time + delta
    update_timer_display(timer_cur_ns)
end

function toggle_timer()
    if timer_active then
        timer_active = false
        timer_cur_time = timer_cur_ns
    else
        timer_active = true
        timer_orig_time = obs.os_gettime_ns()
    end
end

function reset_timer()
    timer_active = false
    timer_cur_time = 0
    timer_cur_ns = 0
    update_timer_display(0)
end

-- ==========================================
-- GOAL SEQUENCE
-- ==========================================
function start_sequence(target_text_source)
    local current_scene = obs.obs_frontend_get_current_scene()
    if current_scene ~= nil then
        local scene = obs.obs_scene_from_source(current_scene)
        local video_item = find_scene_item(scene, source_video)
        if video_item ~= nil then
            obs.obs_sceneitem_set_visible(video_item, true)
        end
        obs.obs_source_release(current_scene)
    end
    
    local v_source = obs.obs_get_source_by_name(source_video)
    if v_source ~= nil then
        obs.obs_source_media_restart(v_source)
        obs.obs_source_release(v_source)
    end
    
    local update_callback
    update_callback = function()
        obs.timer_remove(update_callback)
        local text_source = obs.obs_get_source_by_name(target_text_source)
        if text_source ~= nil then
            local settings = obs.obs_source_get_settings(text_source)
            local current_str = obs.obs_data_get_string(settings, "text")
            local num_str = string.match(current_str, "%d+")
            local current_score = 0
            if num_str ~= nil then current_score = tonumber(num_str) end
            
            local new_score = current_score + 1
            local new_str = tostring(new_score)
            if num_str ~= nil then
                new_str = string.gsub(current_str, num_str, tostring(new_score), 1)
            end
            
            obs.obs_data_set_string(settings, "text", new_str)
            obs.obs_source_update(text_source, settings)
            obs.obs_data_release(settings)
            obs.obs_source_release(text_source)
        end
    end
    
    obs.timer_add(update_callback, delay_ms)
    obs.timer_add(hide_video_source, delay_ms + hide_delay_ms)
end

-- ==========================================
-- BREAK SEQUENCE
-- ==========================================
function trigger_break_sequence()
    obs.script_log(obs.LOG_INFO, "--- HALF TIME SEQUENCE INITIATED ---")
    local current_scene = obs.obs_frontend_get_current_scene()
    if current_scene ~= nil then
        local scene = obs.obs_scene_from_source(current_scene)
        
        local main_board_item = find_scene_item(scene, source_main_scoreboard)
        if main_board_item ~= nil then
            obs.obs_sceneitem_set_visible(main_board_item, false)
        end
        
        local ht_video_item = find_scene_item(scene, source_ht_video)
        if ht_video_item ~= nil then
            obs.obs_sceneitem_set_visible(ht_video_item, true)
        end
        obs.obs_source_release(current_scene)
    end
    
    local ht_v_source = obs.obs_get_source_by_name(source_ht_video)
    if ht_v_source ~= nil then
        obs.obs_source_media_restart(ht_v_source)
        obs.obs_source_release(ht_v_source)
    end
    
    -- Phase 1: Reveal Text
    local ht_text_reveal_callback
    ht_text_reveal_callback = function()
        obs.timer_remove(ht_text_reveal_callback)
        obs.script_log(obs.LOG_INFO, "Half-time text REVEALED at " .. tostring(ht_delay_ms) .. "ms")
        sync_text_source(source_home_text, source_ht_home_text)
        sync_text_source(source_away_text, source_ht_away_text)
        
        local inner_scene = obs.obs_frontend_get_current_scene()
        if inner_scene ~= nil then
            local scene = obs.obs_scene_from_source(inner_scene)
            local ht_home_item = find_scene_item(scene, source_ht_home_text)
            if ht_home_item ~= nil then obs.obs_sceneitem_set_visible(ht_home_item, true) end
            
            local ht_away_item = find_scene_item(scene, source_ht_away_text)
            if ht_away_item ~= nil then obs.obs_sceneitem_set_visible(ht_away_item, true) end
            obs.obs_source_release(inner_scene)
        end
    end
    obs.timer_add(ht_text_reveal_callback, ht_delay_ms)

    -- Phase 2: Hide Text
    local ht_text_hide_callback
    ht_text_hide_callback = function()
        obs.timer_remove(ht_text_hide_callback)
        obs.script_log(obs.LOG_INFO, "Half-time text HIDDEN at " .. tostring(ht_text_hide_delay_ms) .. "ms")
        local inner_scene = obs.obs_frontend_get_current_scene()
        if inner_scene ~= nil then
            local scene = obs.obs_scene_from_source(inner_scene)
            local ht_home_item = find_scene_item(scene, source_ht_home_text)
            if ht_home_item ~= nil then obs.obs_sceneitem_set_visible(ht_home_item, false) end
            
            local ht_away_item = find_scene_item(scene, source_ht_away_text)
            if ht_away_item ~= nil then obs.obs_sceneitem_set_visible(ht_away_item, false) end
            obs.obs_source_release(inner_scene)
        end
    end
    obs.timer_add(ht_text_hide_callback, ht_text_hide_delay_ms)
    
    -- Phase 3: Resume Match Layout
    obs.timer_add(hide_break_sequence_and_resume, ht_hide_delay_ms)
end

function hide_break_sequence_and_resume()
    obs.timer_remove(hide_break_sequence_and_resume)
    obs.script_log(obs.LOG_INFO, "Break sequence ENDED at " .. tostring(ht_hide_delay_ms) .. "ms")
    local current_scene = obs.obs_frontend_get_current_scene()
    if current_scene ~= nil then
        local scene = obs.obs_scene_from_source(current_scene)
        
        local ht_video_item = find_scene_item(scene, source_ht_video)
        if ht_video_item ~= nil then obs.obs_sceneitem_set_visible(ht_video_item, false) end
        
        -- Failsafe hide text just in case
        local ht_home_item = find_scene_item(scene, source_ht_home_text)
        if ht_home_item ~= nil then obs.obs_sceneitem_set_visible(ht_home_item, false) end
        local ht_away_item = find_scene_item(scene, source_ht_away_text)
        if ht_away_item ~= nil then obs.obs_sceneitem_set_visible(ht_away_item, false) end
        
        local main_board_item = find_scene_item(scene, source_main_scoreboard)
        if main_board_item ~= nil then
            obs.obs_sceneitem_set_visible(main_board_item, true)
        end
        obs.obs_source_release(current_scene)
    end
end

function trigger_home_goal() start_sequence(source_home_text) end
function trigger_away_goal() start_sequence(source_away_text) end

function hide_video_source()
    obs.timer_remove(hide_video_source)
    local current_scene = obs.obs_frontend_get_current_scene()
    if current_scene ~= nil then
        local scene = obs.obs_scene_from_source(current_scene)
        local video_item = find_scene_item(scene, source_video)
        if video_item ~= nil then obs.obs_sceneitem_set_visible(video_item, false) end
        obs.obs_source_release(current_scene)
    end
end

-- ==========================================
-- SCRIPT UI
-- ==========================================
function script_properties()
    local props = obs.obs_properties_create()
    
    local p_video = obs.obs_properties_add_list(props, "video_src", "Goal Animation Video", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local p_home = obs.obs_properties_add_list(props, "home_src", "Home Score Text", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local p_away = obs.obs_properties_add_list(props, "away_src", "Away Score Text", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local p_main_board = obs.obs_properties_add_list(props, "main_board_src", "Main Scoreboard Group", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    
    local p_ht_video = obs.obs_properties_add_list(props, "ht_video_src", "Half-Time Video Graphic", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local p_ht_home = obs.obs_properties_add_list(props, "ht_home_src", "HT Graphic Home Score", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local p_ht_away = obs.obs_properties_add_list(props, "ht_away_src", "HT Graphic Away Score", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    
    local p_timer = obs.obs_properties_add_list(props, "timer_src", "Match Timer Text Layer", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)

    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            local name = obs.obs_source_get_name(source)
            obs.obs_property_list_add_string(p_video, name, name)
            obs.obs_property_list_add_string(p_home, name, name)
            obs.obs_property_list_add_string(p_away, name, name)
            obs.obs_property_list_add_string(p_main_board, name, name)
            obs.obs_property_list_add_string(p_ht_video, name, name)
            obs.obs_property_list_add_string(p_ht_home, name, name)
            obs.obs_property_list_add_string(p_ht_away, name, name)
            obs.obs_property_list_add_string(p_timer, name, name)
        end
    end
    obs.source_list_release(sources)
    
    obs.obs_properties_add_int(props, "delay", "Goal Text Delay (ms)", 100, 5000, 50)
    obs.obs_properties_add_int(props, "hide_delay", "Keep Goal Video Open (ms)", 500, 10000, 100)
    
    obs.obs_properties_add_int(props, "ht_delay", "HT Text Appear Time (ms)", 0, 15000, 50)
    obs.obs_properties_add_int(props, "ht_text_hide_delay", "HT Text Disappear Time (ms)", 500, 30000, 100)
    obs.obs_properties_add_int(props, "ht_hide_delay", "Keep HT Video Open (ms)", 1000, 30000, 500)
    
    obs.obs_properties_add_int(props, "timer_start_min", "Timer Start Minutes (e.g. 0 or 45)", 0, 120, 1)
    
    obs.obs_properties_add_button(props, "timer_toggle_btn", "⏱️ START / PAUSE TIMER", toggle_timer)
    obs.obs_properties_add_button(props, "timer_reset_btn", "🔄 RESET TIMER", reset_timer)
    obs.obs_properties_add_button(props, "home_btn", "⚽ TRIGGER HOME GOAL", trigger_home_goal)
    obs.obs_properties_add_button(props, "away_btn", "⚽ TRIGGER AWAY GOAL", trigger_away_goal)
    obs.obs_properties_add_button(props, "ht_btn", "⏱️ TRIGGER HALF/FULL TIME", trigger_break_sequence)
    return props
end

function script_update(settings)
    source_video = obs.obs_data_get_string(settings, "video_src")
    source_home_text = obs.obs_data_get_string(settings, "home_src")
    source_away_text = obs.obs_data_get_string(settings, "away_src")
    source_main_scoreboard = obs.obs_data_get_string(settings, "main_board_src")
    
    source_ht_video = obs.obs_data_get_string(settings, "ht_video_src")
    source_ht_home_text = obs.obs_data_get_string(settings, "ht_home_src")
    source_ht_away_text = obs.obs_data_get_string(settings, "ht_away_src")
    
    source_timer_text = obs.obs_data_get_string(settings, "timer_src")
    timer_start_minutes = obs.obs_data_get_int(settings, "timer_start_min")
    
    delay_ms = obs.obs_data_get_int(settings, "delay")
    hide_delay_ms = obs.obs_data_get_int(settings, "hide_delay")
    ht_delay_ms = obs.obs_data_get_int(settings, "ht_delay")
    ht_text_hide_delay_ms = obs.obs_data_get_int(settings, "ht_text_hide_delay")
    ht_hide_delay_ms = obs.obs_data_get_int(settings, "ht_hide_delay")
    
    update_timer_display(timer_cur_ns)
end