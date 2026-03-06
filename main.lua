-- Plugin State Variables
local is_playing = false
local is_waiting_for_anim = false
local last_frame_num = -1
local ticks_since_last_frame = 0

-- UI Layout Variables
local is_minimized = false
local is_rebuilding = false

local current_audio_file = ""
local current_offset = 550
local current_sync_time = true
local current_trim_start = "0.0"
local current_trim_end = "0.0"

local current_format = "mp4"
local current_v_codec = "libx264"
local current_crf = "18"
local current_pix_fmt = "yuv420p"
local current_preset = "slow"
local current_a_codec = "aac"
local current_bitrate = "320k"
local current_scale = 1
local current_fps = "0"
local current_overwrite = true
local current_create_log = true
local current_preview_mode = "Once"
local last_log_path = ""
local last_video_path = ""

-- FFmpeg Command
local DEFAULT_FF_CMD = "ffmpeg -i $input_anim $trim -vn -i $input_audio -vf \"$vf_chain\" -c:v $v_codec -pix_fmt $pix_fmt -crf $crf -preset $preset -c:a $a_codec -b:a $bitrate -t $anim_duration"
local MUTED_FF_CMD = "ffmpeg -i $input_anim $trim -vf \"$vf_chain\" -c:v $v_codec -pix_fmt $pix_fmt -crf $crf -preset $preset -an -t $anim_duration"

local current_ff_cmd = DEFAULT_FF_CMD

local dlg = nil
local export_dlg = nil

-- Keep user settings safe when open/close windows
local function sync_state()
    if dlg and dlg.data then
        local d = dlg.data
        current_audio_file = d.audio_file or current_audio_file
        current_offset = d.offset or current_offset
        current_sync_time = (d.sync_time ~= nil) and d.sync_time or current_sync_time
        current_trim_start = d.trim_start or current_trim_start
        current_trim_end = d.trim_end or current_trim_end
    end
    if export_dlg and export_dlg.data then
        local ed = export_dlg.data
        current_format = ed.format or current_format
        current_v_codec = ed.v_codec or current_v_codec
        current_crf = ed.crf or current_crf
        current_pix_fmt = ed.pix_fmt or current_pix_fmt
        current_preset = ed.preset or current_preset
        current_a_codec = ed.a_codec or current_a_codec
        current_bitrate = ed.bitrate or current_bitrate
        current_scale = ed.scale or current_scale
        current_fps = ed.fps or current_fps
        current_overwrite = (ed.overwrite ~= nil) and ed.overwrite or current_overwrite
        current_create_log = (ed.create_log ~= nil) and ed.create_log or current_create_log
        current_ff_cmd = ed.ff_cmd or current_ff_cmd
        current_preview_mode = ed.preview_mode or current_preview_mode
    end
end

-- Get the exact second to start the audio
local function get_audio_start_time(frame_num)
    local start_time = tonumber(current_trim_start) or 0.0
    if current_sync_time then
        local sprite = app.activeSprite
        if sprite and frame_num > 1 then
            for i = 1, frame_num - 1 do
                start_time = start_time + sprite.frames[i].duration
            end
        end
    end
    return start_time
end

local function is_installed(cmd)
    local success = os.execute("command -v " .. cmd .. " > /dev/null 2>&1")
    return success == true or success == 0
end

local function stop_audio()
    if is_playing then
        os.execute("pkill -f ASEPRITE_AUDIO_SYNC")
        is_playing = false
    end
    is_waiting_for_anim = false
    if _G.AudioDelayTimer then _G.AudioDelayTimer:stop(); _G.AudioDelayTimer = nil end
end

local function play_audio(filepath, start_time, end_time)
    stop_audio()
    if filepath and filepath ~= "" then
        local end_cmd = ""
        if end_time and tonumber(end_time) > start_time then
            end_cmd = string.format("-t %f", end_time - start_time)
        end
        -- Treating as audio-only for fast live syncing
        local cmd = string.format("ffplay -nodisp -vn -autoexit -ss %f %s '%s' -window_title ASEPRITE_AUDIO_SYNC > /dev/null 2>&1 &", start_time, end_cmd, filepath)
        os.execute(cmd)
        is_playing = true
    end
end

local function launch_in_terminal(command_str)
    local cmd = ""
    local shell_cmd = string.format("bash -c %q", command_str)
    if is_installed("alacritty") then cmd = "alacritty -e " .. shell_cmd .. " &"
    elseif is_installed("xterm") then cmd = "xterm -e " .. shell_cmd .. " &"
    elseif is_installed("konsole") then cmd = "konsole -e " .. shell_cmd .. " &"
    elseif is_installed("xfce4-terminal") then cmd = "xfce4-terminal -e " .. shell_cmd .. " &"
    elseif is_installed("gnome-terminal") then cmd = "gnome-terminal -- " .. shell_cmd .. " &"
    else os.execute(command_str .. " &"); return end
    os.execute(cmd)
end

-- Secondary Window: Export Settings
local function show_export_panel()
    sync_state() 
    local audio_ok = (current_audio_file ~= "" and app.fs.isFile(current_audio_file))
    
    if export_dlg then
        export_dlg:modify{ id="a_codec", enabled = audio_ok }
        export_dlg:modify{ id="bitrate", enabled = audio_ok }
        export_dlg:modify{ id="ff_cmd", text = audio_ok and DEFAULT_FF_CMD or MUTED_FF_CMD }
        export_dlg:show{ wait = false }
        return 
    end

    export_dlg = Dialog{
        title = "Export Settings",
        onclose = function() sync_state(); export_dlg = nil end
    }

    export_dlg:combobox{ id = "format", label = "File type:", option = current_format, options = {"mp4", "mkv", "mov", "avi", "webm"} }
    export_dlg:combobox{ id = "v_codec", label = "Video Codec:", option = current_v_codec, options = {"libx264", "libx265", "libvpx-vp9", "mpeg4", "copy"} }
    export_dlg:combobox{ id = "crf", label = "Quality (CRF):", option = current_crf, options = {"0", "12", "18", "23", "28", "32"} }
    export_dlg:combobox{ id = "pix_fmt", label = "Colors (PixFmt):", option = current_pix_fmt, options = {"yuv420p", "yuv444p", "rgb24"} }
    export_dlg:combobox{ id = "preset", label = "Render Speed:", option = current_preset, options = {"ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"} }
    export_dlg:combobox{ id = "a_codec", label = "Audio Codec:", option = current_a_codec, options = {"aac", "libmp3lame", "libvorbis", "opus", "copy"}, enabled = audio_ok }
    export_dlg:combobox{ id = "bitrate", label = "Audio Bitrate:", option = current_bitrate, options = {"128k", "192k", "256k", "320k"}, enabled = audio_ok }

    export_dlg:entry{ id = "fps", label = "FPS (0=Auto):", text = current_fps }

    export_dlg:slider{ id = "scale", label = "Upscale (1-20x):", min = 1, max = 20, value = current_scale,
        onchange = function()
            local s = app.activeSprite
            local d = export_dlg.data
            if s then export_dlg:modify{ id="res_preview", text=string.format("Final result size: %dx%d", s.width*d.scale, s.height*d.scale) } end
        end
    }
    export_dlg:label{ id = "res_preview", text = "Resolution preview" }

    export_dlg:entry{ id = "ff_cmd", label = "FFmpeg Cmd:", text = audio_ok and DEFAULT_FF_CMD or MUTED_FF_CMD }
    
    export_dlg:button{ text = "Reset to Default Command",
        onclick = function()
            sync_state()
            local ok = (current_audio_file ~= "" and app.fs.isFile(current_audio_file))
            export_dlg:modify{ id = "ff_cmd", text = ok and DEFAULT_FF_CMD or MUTED_FF_CMD }
        end
    }

    export_dlg:check{ id = "overwrite", label = "Settings:", text = "Overwrite existing file (-y)", selected = current_overwrite }
    export_dlg:check{ id = "create_log", text = "Create ffmpeg-log.txt", selected = current_create_log }

    export_dlg:separator{ text = "Watch Mode" }
    export_dlg:combobox{ id = "preview_mode", label = "Preview type:", option = current_preview_mode, options = {"Once", "Loop"} }

    export_dlg:newrow()
    
    export_dlg:button{ id = "btn_export", text = "Export",
        onclick = function()
            sync_state() 
            local data = export_dlg.data
            local sprite = app.activeSprite
            if not sprite then app.alert("No sprite open!"); return end
            if not is_installed("ffmpeg") then app.alert("Install FFmpeg first!"); return end
            
            local audio_ok = (current_audio_file ~= "" and app.fs.isFile(current_audio_file))
            if not audio_ok and not data.ff_cmd:find("-an") then
                app.alert("No audio found! Pick a file or use -an (Mute).")
                return
            end

            local save_dlg = Dialog("Save Your Video")
            save_dlg:file{ id="path", label="Save to:", save=true, filetypes={data.format} }
            save_dlg:button{ id="ok", text="Start Export" }
            save_dlg:show()
            
            if not save_dlg.data.ok or save_dlg.data.path == "" then return end
            
            local final_out = save_dlg.data.path
            local ext = "." .. data.format
            if final_out:sub(-1) == "/" or final_out:sub(-1) == "\\" then final_out = final_out .. "animation_export" .. ext
            elseif not final_out:lower():match(ext:lower() .. "$") then final_out = final_out .. ext end
            
            last_video_path = final_out
            local temp_anim = "/tmp/ase_render.gif"
            sprite:saveCopyAs(temp_anim)

            local anim_duration = 0
            for i = 1, #sprite.frames do anim_duration = anim_duration + sprite.frames[i].duration end

            local trim_val = ""
            local t_start = tonumber(current_trim_start) or 0
            local t_end = tonumber(current_trim_end) or 0
            if t_start > 0 or t_end > 0 then
                trim_val = string.format("-ss %f", t_start)
                if t_end > 0 then trim_val = trim_val .. string.format(" -to %f", t_end) end
            end

            local fps_val = tonumber(data.fps) or 0
            local vf_chain = ""
            if fps_val > 0 then vf_chain = string.format("fps=fps=%d,", fps_val) end
            vf_chain = vf_chain .. string.format("scale=iw*%d:ih*%d:flags=neighbor", data.scale, data.scale)

            local cmd = data.ff_cmd
            if data.overwrite and not cmd:find("-y ") then cmd = cmd:gsub("^ffmpeg ", "ffmpeg -y ") end
            if audio_ok then
                cmd = cmd:gsub("%$input_audio", "'" .. current_audio_file .. "'")
                cmd = cmd:gsub("%$a_codec", data.a_codec)
                cmd = cmd:gsub("%$bitrate", data.bitrate)
            end
            cmd = cmd:gsub("$input_anim", "'" .. temp_anim .. "'")
            cmd = cmd:gsub("$trim", trim_val)
            cmd = cmd:gsub("$vf_chain", vf_chain)
            cmd = cmd:gsub("$scale", tostring(data.scale))
            cmd = cmd:gsub("$v_codec", data.v_codec)
            cmd = cmd:gsub("$crf", data.crf)
            cmd = cmd:gsub("$pix_fmt", data.pix_fmt)
            cmd = cmd:gsub("$preset", data.preset)
            cmd = cmd:gsub("$anim_duration", tostring(anim_duration))
            cmd = cmd .. " '" .. final_out .. "'"
            
            local log_path = app.fs.joinPath(app.fs.filePath(final_out), "ffmpeg-log.txt")
            last_log_path = log_path
            local final_cmd = (data.create_log) and cmd .. " > '" .. log_path .. "' 2>&1" or cmd
            app.alert("Aseprite will freeze for a second while FFmpeg works.")
            os.execute(final_cmd)
            os.execute("rm -f " .. temp_anim)
            app.alert("Export finished!")
        end
    }

    export_dlg:button{ id = "btn_preview", text = "Watch Video",
        onclick = function()
            sync_state()
            if last_video_path == "" or not app.fs.isFile(last_video_path) then app.alert("Export a video first!"); return end
            -- FIXED: Loop logic for video files (removed autoexit for loop)
            local preview_cmd = ""
            if current_preview_mode == "Loop" then
                preview_cmd = string.format("ffplay -loop 0 '%s'", last_video_path)
            else
                preview_cmd = string.format("ffplay -autoexit '%s'", last_video_path)
            end
            launch_in_terminal(preview_cmd)
        end
    }

    export_dlg:button{ id = "btn_log", text = "Show Log",
        onclick = function()
            if last_log_path == "" or not app.fs.isFile(last_log_path) then app.alert("Log not found."); return end
            launch_in_terminal(string.format("cat '%s'; echo ''; echo '--- End of Log ---'; read -n 1 -s -r -p 'Press a key to close...'", last_log_path))
        end
    }

    export_dlg:show{ wait = false }
end

-- First Window: Audio Sync
local function show_panel()
    local saved_bounds = nil
    if dlg then sync_state(); saved_bounds = dlg.bounds; is_rebuilding = true; dlg:close(); is_rebuilding = false end

    dlg = Dialog{
        title = "Audio Sync",
        onclose = function()
            if not is_rebuilding then
                sync_state()
                stop_audio()
                if _G.AudioSyncTimer then _G.AudioSyncTimer:stop(); _G.AudioSyncTimer = nil end
            end
            dlg = nil
        end
    }

    if not is_minimized then
        dlg:file{ id = "audio_file", label = "Pick audio:", title = "Select Audio File", open = true, filename = current_audio_file }
        dlg:entry{ id = "trim_start", label = "Start (sec):", text = current_trim_start }
        dlg:entry{ id = "trim_end", label = "End (sec):", text = current_trim_end }
        dlg:check{ id = "sync_time", label = "Sync:", text = "Start from current frame", selected = current_sync_time }
        dlg:slider{ id = "offset", label = "Delay (ms):", min = 0, max = 1000, value = current_offset }
        dlg:separator{ text = "Timeline" }
    end

    dlg:button{ text = "|<", onclick = function() stop_audio(); app.command.GoToFirstFrame() end }
    dlg:button{ text = " < ", onclick = function() stop_audio(); app.command.GoToPreviousFrame() end }
    dlg:button{ text = " > ", onclick = function() stop_audio(); app.command.GoToNextFrame() end }
    dlg:button{ text = ">|", onclick = function() stop_audio(); app.command.GoToLastFrame() end }
    
    dlg:newrow()
    
    dlg:button{ id = "btn_play", text = " [ PLAY ] ",
        onclick = function()
            sync_state()
            if not is_installed("ffplay") then app.alert("Install ffplay first!"); return end
            stop_audio()
            if app.activeFrame then app.command.GoToFrame{ frame = app.activeFrame.frameNumber } end
            local start_time = get_audio_start_time(app.activeFrame and app.activeFrame.frameNumber or 1)
            if current_audio_file ~= "" and app.fs.isFile(current_audio_file) then 
                play_audio(current_audio_file, start_time, tonumber(current_trim_end) or 0.0) 
            end
            
            if current_offset > 0 then
                is_waiting_for_anim = true
                _G.AudioDelayTimer = Timer{ interval = current_offset / 1000.0, ontick = function()
                    app.command.PlayAnimation()
                    is_waiting_for_anim = false
                    if app.activeFrame then last_frame_num = app.activeFrame.frameNumber end
                    ticks_since_last_frame = 0
                    if _G.AudioDelayTimer then _G.AudioDelayTimer:stop(); _G.AudioDelayTimer = nil end
                end }
                _G.AudioDelayTimer:start()
            else
                is_waiting_for_anim = false; app.command.PlayAnimation()
                if app.activeFrame then last_frame_num = app.activeFrame.frameNumber end
                ticks_since_last_frame = 0
            end
        end
    }
    
    dlg:button{ id = "btn_pause", text = " [ PAUSE ] ",
        onclick = function() stop_audio(); if app.activeFrame then app.command.GoToFrame{ frame = app.activeFrame.frameNumber } end end
    }

    dlg:button{ text = is_minimized and " MAX " or " MIN ", onclick = function() sync_state(); is_minimized = not is_minimized; show_panel() end }

    if not is_minimized then
        dlg:separator()
        dlg:button{ text = "Export Settings", onclick = function() show_export_panel() end }
    end

    if _G.AudioSyncTimer then _G.AudioSyncTimer:stop() end
    _G.AudioSyncTimer = Timer{ interval = 0.1, ontick = function()
        if not is_playing or is_waiting_for_anim then return end
        local frame = app.activeFrame
        if not frame then 
            ticks_since_last_frame = ticks_since_last_frame + 1
            if ticks_since_last_frame > 5 then stop_audio() end
            return 
        end
        if frame.frameNumber == last_frame_num then
            ticks_since_last_frame = ticks_since_last_frame + 1
            if ticks_since_last_frame > math.ceil(frame.duration / 0.1) + 4 then stop_audio() end
        else
            if last_frame_num ~= -1 and frame.frameNumber < last_frame_num then
                local start_time = get_audio_start_time(frame.frameNumber)
                if current_audio_file ~= "" and app.fs.isFile(current_audio_file) then 
                    play_audio(current_audio_file, start_time + (current_offset / 1000.0), tonumber(current_trim_end) or 0.0) 
                end
            end
            last_frame_num, ticks_since_last_frame = frame.frameNumber, 0
        end
    end }
    _G.AudioSyncTimer:start()
    
    dlg:show{ wait = false }
    if saved_bounds then dlg.bounds = Rectangle(saved_bounds.x, saved_bounds.y, dlg.bounds.width, dlg.bounds.height) end
end

function init(plugin)
    plugin:newCommand{
        id = "VideoAudioExport",
        title = "Audio & Video Export",
        group = "file_export",
        onclick = function() show_panel() end
    }
end

function exit(plugin)
    stop_audio()
    if _G.AudioSyncTimer then _G.AudioSyncTimer:stop(); _G.AudioSyncTimer = nil end
    if dlg then dlg:close() end
    if export_dlg then export_dlg:close() end
end