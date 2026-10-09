obs = obslua

source_video = ""
hide_delay_ms = 5000

-- Helper to find the video layer even if it's inside a Group
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

function trigger_video()
    -- 1. Unhide the selected video
    local current_scene = obs.obs_frontend_get_current_scene()
    if current_scene ~= nil then
        local scene = obs.obs_scene_from_source(current_scene)
        local video_item = find_scene_item(scene, source_video)
        if video_item ~= nil then
            obs.obs_sceneitem_set_visible(video_item, true)
        end
        obs.obs_source_release(current_scene)
    end
    
    -- 2. Force the video to restart from 0:00
    local v_source = obs.obs_get_source_by_name(source_video)
    if v_source ~= nil then
        obs.obs_source_media_restart(v_source)
        obs.obs_source_release(v_source)
    end
    
    -- 3. Reset the hide timer and start the countdown
    obs.timer_remove(hide_video) 
    obs.timer_add(hide_video, hide_delay_ms)
end

function hide_video()
    obs.timer_remove(hide_video)
    local current_scene = obs.obs_frontend_get_current_scene()
    if current_scene ~= nil then
        local scene = obs.obs_scene_from_source(current_scene)
        local video_item = find_scene_item(scene, source_video)
        if video_item ~= nil then
            obs.obs_sceneitem_set_visible(video_item, false)
        end
        obs.obs_source_release(current_scene)
    end
end

-- SCRIPT UI
function script_properties()
    local props = obs.obs_properties_create()
    
    -- Dropdown to choose the active video
    local p_video = obs.obs_properties_add_list(props, "video_src", "Select Video to Play", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            local name = obs.obs_source_get_name(source)
            obs.obs_property_list_add_string(p_video, name, name)
        end
    end
    obs.source_list_release(sources)
    
    obs.obs_properties_add_int(props, "hide_delay", "Keep Video Open (ms)", 500, 60000, 500)
    
    obs.obs_properties_add_button(props, "trigger_btn", "▶️ PLAY SELECTED VIDEO", trigger_video)
    
    return props
end

function script_update(settings)
    source_video = obs.obs_data_get_string(settings, "video_src")
    hide_delay_ms = obs.obs_data_get_int(settings, "hide_delay")
end