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
    // Input
    if is_pressed(.ESCAPE)
    {
        yae_request_close();
    }

    dockspace_id: = ImGui.GetID("pluebrint_dockspace");
    pluebrint_window_class: = ImGui.WindowClass.{ ClassId = dockspace_id };

    // Main menu
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

    // Demo window
    if app_settings.imgui_demo_open
    {
        ImGui.ShowDemoWindow(*app_settings.imgui_demo_open);
    }

    flags: ImGui.WindowFlags = .ImGuiWindowFlags_NoDecoration | .ImGuiWindowFlags_NoMove | .ImGuiWindowFlags_NoSavedSettings;
    viewport: = ImGui.GetMainViewport();
    ImGui.SetNextWindowPos(viewport.WorkPos);
    ImGui.SetNextWindowSize(viewport.WorkSize);
    if ImGui.Begin("main", null, flags)
    {
        // Dockspace
        dockspace_size: = max(ImGui.GetContentRegionAvail(), xy(16));

        // Build default dockspace
        if ImGui.DockBuilderGetNode(dockspace_id) == null
        {
            ImGui.DockBuilderRemoveNode(dockspace_id); // Clear out existing layout
            ImGui.DockBuilderAddNode(dockspace_id, cast(ImGui.DockNodeFlags) ImGui.DockNodeFlagsPrivate_.DockNodeFlags_DockSpace); // Add empty node
            ImGui.DockBuilderSetNodeSize(dockspace_id, dockspace_size);

            dock_main_id: = dockspace_id; // This variable will track the document node, however we are not using it here as we aren't docking anything into it.
            dock_id_right: = ImGui.DockBuilderSplitNode(dock_main_id, .ImGuiDir_Right, 0.30, null, *dock_main_id);
            dock_id_bottom: = ImGui.DockBuilderSplitNode(dock_main_id, .ImGuiDir_Down, 0.40, null, *dock_main_id);

            ImGui.DockBuilderDockWindow("properties", dock_id_right);
            ImGui.DockBuilderDockWindow("output", dock_id_bottom);
            ImGui.DockBuilderDockWindow("graph", dock_main_id);
            ImGui.DockBuilderFinish(dockspace_id);
        }
        else
        {
            ImGui.DockSpace(dockspace_id, *dockspace_size, flags = .ImGuiDockNodeFlags_AutoHideTabBar, window_class = *pluebrint_window_class);
        }
    }
    ImGui.End();

    // Properties
    ImGui.SetNextWindowClass(*pluebrint_window_class);
    if ImGui.Begin("properties")
    {
        ImGui.Text("props");
    }
    ImGui.End();

    // Output
    ImGui.SetNextWindowClass(*pluebrint_window_class);
    if ImGui.Begin("output")
    {
        ImGui.Text("output");
    }
    ImGui.End();

    // Graph
    ImGui.SetNextWindowClass(*pluebrint_window_class);
    if ImGui.Begin("graph")
    {
        ImGui.Text("graph");
    }
    ImGui.End();
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

#import "Math";