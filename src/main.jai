AppSettings :: struct
{
    imgui_demo_open: bool; @serialize
}
app_settings: AppSettings;

// Application callbacks
init :: ()
{

}

shutdown :: ()
{

}

update :: (dt: float)
{
    if ImGui.BeginMainMenuBar()
    {
        if ImGui.BeginMenu("File")
        {
            ImGui.MenuItem("ImGuiDemo", "", *app_settings.imgui_demo_open);
            ImGui.Separator();
            if ImGui.MenuItem("Exit", "Esc")
            {
                yae_request_close();
            }
            ImGui.EndMenu();
        }
    }
    ImGui.EndMainMenuBar();

    if app_settings.imgui_demo_open
    {
        ImGui.ShowDemoWindow(*app_settings.imgui_demo_open);
    }

    if is_pressed(.ESCAPE)
    {
        yae_request_close();
    }
}

draw :: ()
{
    clear_background();
}


// Boilerplate
main :: ()
{
    // Init
    register_settings_section("pb", *app_settings);
    yae_init(800, 600, "pluebrint");
    init();

    // Loop
    yae_loop(update, draw);
    if OS == .WASM return; // wasm needs to exit immediately. Everything will happen async later

    // Shutdown
    shutdown();
    yae_shutdown();
}

// === Loads ===
#if OS == .WASM
{
    // @NOTE(remi): We can remove this with functions that send callbacks as argument to wasm
    #load "../modules/yae/wasm_export.jai";
}

// === Imports ===
#scope_file
#import "Basic"()(MEMORY_DEBUGGER = YAE_DEBUG_MEMORY);
#import "yae";
