-- Project configuration
set_project("my_SFML_project")
set_description("SFML project with debug, release and dev modes")
add_rules("mode.debug", "mode.release")
add_rules("mode.dev")
set_policy("check.auto_ignore_flags", false)

-- Detect compiler
local is_msvc = is_plat("windows") 
local is_gcc = is_plat("gcc") 
local is_mingw = is_plat("mingw")

-- SFML requirements
if is_mode("debug") then
    add_requires("sfml", {debug = true})
else
    add_requires("sfml")
end

-- Define custom development mode
rule("mode.dev")
    on_load(function (target)
        target:set("symbols", "debug")
        target:set("optimize", "faster")
        target:set("warnings", "all")
        target:add("defines", "DEV")
    end)

-- Common compiler warnings and flags
local common_warnings = {}
if is_msvc then
    common_warnings = {
        "/W4", "/WX", "/permissive-", 
        "/w14640", -- Enable warning on thread un-safe static member initialization
        "/w14242", -- Conversion warnings
        "/w14254", 
        "/w14263",
        "/w14265",
        "/w14287",
        "/we4289",
        "/w14296",
        "/w14311",
        "/w14545",
        "/w14546",
        "/w14547",
        "/w14549",
        "/w14555",
        "/w14619",
        "/w14640",
        "/w14826",
        "/w14905",
        "/w14906",
        "/w14928"
    }
else
    common_warnings = {
        "-Wall", "-Wextra", "-Wshadow", 
        "-Wnon-virtual-dtor", "-pedantic-errors",
        "-Wconversion", "-Wfloat-equal", 
        "-Wdeprecated", "-Wno-unused-parameter",
        "-Wformat=2", "-Wcast-align",
        "-Wunused", "-Woverloaded-virtual",
        "-Wpedantic", "-Wconversion",
        "-Wsign-conversion", "-Wmisleading-indentation",
        "-Wduplicated-cond", "-Wduplicated-branches",
        "-Wlogical-op", "-Wnull-dereference",
        "-Wdouble-promotion", "-Wformat=2",
        --"-Wlifetime"
    }
end

-- Main target configuration
target("game")
    set_kind("binary")
    set_languages("c++17")
    add_files("src/*.cpp")
    add_packages("sfml")
    add_cxxflags(common_warnings)
    
    -- Platform specific settings
    if is_plat("windows") then
        add_defines("SFML_STATIC")
        add_syslinks("opengl32", "freetype", "winmm", "gdi32")
    end

    -- Debug mode configuration
    if is_mode("debug") then
        add_defines("DEBUG")
        set_targetdir("build/debug/bin")
        
        if is_msvc then
            add_cxxflags("/Od", "/Zi", "/FS")
            -- MSVC sanitizers
            add_cxxflags("/fsanitize=address")
        elseif is_gcc then
            add_cxxflags("-g", "-ggdb", "-O0")
            -- GCC sanitizers
            add_cxxflags("-fsanitize=address,undefined", "-fno-omit-frame-pointer")
            add_ldflags("-fsanitize=address,undefined")
        else -- MinGW
            add_cxxflags("-g", "-ggdb", "-O0")
        end
        
        add_links("sfml-graphics-s-d", "sfml-window-s-d", "sfml-system-s-d")
    end
    
    -- Release mode configuration
    if is_mode("release") then
        add_defines("NDEBUG")
        set_targetdir("build/release/bin")
        
        if is_msvc then
            add_cxxflags("/O2", "/GL", "/Gy")
            add_ldflags("/LTCG")
        else
            add_cxxflags("-O3", "-march=native", "-ffast-math")
            add_cxxflags("-fno-exceptions", "-fno-rtti")
        end
        add_ldflags("-mwindows")
        set_strip("all")
        add_links("sfml-graphics-s", "sfml-window-s", "sfml-system-s")
    end
    
    -- Development mode configuration
    if is_mode("dev") then
        add_defines("DEV")
        set_targetdir("build/dev/bin")
        
        if is_msvc then
            add_cxxflags("/O2", "/Zi", "/FS")
        else
            add_cxxflags("-g", "-O2", "-ggdb")
        end
        
        add_links("sfml-graphics-s", "sfml-window-s", "sfml-system-s")
    end
    
    -- After build hook to copy DLLs
    after_build(function (target)
        -- Only copy DLLs that actually exist
        if is_plat("windows") then
            local dll_paths = {}
            if is_msvc then
                dll_paths = {
                    "$(env VCINSTALLDIR)/Redist/MSVC/*/x64/Microsoft.VC*.CRT/*.dll",
                    "$(env WindowsSdkDir)/Redist/*/ucrt/DLLs/x64/*.dll"
                }
            elseif is_mingw then
                dll_paths = {
                    "$(env MINGW)/bin/libgcc_s_*.dll",
                    "$(env MINGW)/bin/libstdc++*.dll",
                    "$(env MINGW)/bin/libwinpthread*.dll"
                }
            end
            
            for _, path in ipairs(dll_paths) do
                os.cp(path, target:targetdir(), {filter = function(filepath)
                    return os.isfile(filepath)
                end})
            end
        end
    end)