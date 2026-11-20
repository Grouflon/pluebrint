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

graph_canvas: ImGuiCanvas = .{
    grid_step = 16.0
};

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
    // ImGui.PushStyleVar(.WindowPadding, .{1,1});
    if ImGui.Begin("graph")
    {
        imgui_canvas_begin(*graph_canvas);
        defer imgui_canvas_end(*graph_canvas);

        draw_node(*graph_canvas, "node", .{1,20}, .{14,8});
    }
    // ImGui.PopStyleVar();
    ImGui.End();
}

draw :: ()
{
    clear_background();
}

draw_node :: (canvas: *ImGuiCanvas, name: string, position: Vector2, size: Vector2)
{
    begin: = canvas_to_screen(canvas, position);
    end: = canvas_to_screen(canvas, position + .{size.x, -size.y});
    header_end: = canvas_to_screen(canvas, position + .{size.x, -2.0});
    text_pos: = canvas_to_screen(canvas, position + .{0.8, -0.6});
    rounding: = 10.0 * canvas.zoom.x;
    font_size: = 13.0 * canvas.zoom.x;

    draw_list: = ImGui.GetWindowDrawList();
    ImGui.ImDrawList.AddRectFilled(draw_list, begin, end, 0xFF121212, rounding);
    ImGui.ImDrawList.PushClipRect(draw_list, begin, header_end, true);
    ImGui.ImDrawList.AddRectFilled(draw_list, begin, end, 0xFF1212BB, rounding);
    ImGui.ImDrawList.PopClipRect(draw_list);

    // @NOTE(remi): We probably need to preload several font sizes. See ScaleAllSizes() function
    ImGui.ImDrawList.AddText(draw_list, null, font_size, text_pos, 0xFFFFFFFF, name);
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