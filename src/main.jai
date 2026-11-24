#load "graph.jai";

TEST_FILE_PATH :: "temp/test.pb";

AppSettings :: struct
{
    imgui_demo_open: bool; @serialize
}
app_settings: AppSettings;

// Application callbacks
init :: ()
{
    graph_load(*graph, TEST_FILE_PATH);
}

shutdown :: ()
{
    graph_shutdown(*graph);
    array_reset(*selection);
}

NODE_SIZE :: Vector2.{14,8};
NODE_ROUNDING :: 1;

graph: Graph;
context_position: Vector2;
graph_canvas: ImGuiCanvas = .{
    grid_step = 16.0
};

DragMode :: enum
{
    NONE;
    SELECTING;
    MOVING;
}

selection: [..]s32;
drag_start: Vector2;
drag_mode: DragMode;

update :: (dt: float)
{
    // Input
    if is_pressed(.ESCAPE) { yae_request_close(); }
    save_requested: = ImGui.IsKeyChordPressed(xx(ImGui.Key.ImGuiMod_Ctrl | ImGui.Key.ImGuiKey_S));
    load_requested: = ImGui.IsKeyChordPressed(xx(ImGui.Key.ImGuiMod_Ctrl | ImGui.Key.ImGuiKey_L));
    left_mouse_pressed: = ImGui.IsMouseClicked(.Left);
    left_mouse_down: = ImGui.IsMouseDown(.Left);
    left_mouse_released: = ImGui.IsMouseReleased(.Left);
    right_mouse_pressed: = ImGui.IsMouseClicked(.Right);
    right_mouse_down: = ImGui.IsMouseDown(.Right);
    right_mouse_released: = ImGui.IsMouseReleased(.Right);

    // Main menu
    if ImGui.BeginMainMenuBar()
    {
        if ImGui.BeginMenu("File")
        {
            if ImGui.MenuItem("Save", "Ctrl+S") { save_requested = true; }
            if ImGui.MenuItem("Load", "Ctrl+L") { load_requested = true; }

            ImGui.Separator();

            ImGui.MenuItem("ImGuiDemo", "", *app_settings.imgui_demo_open);

            ImGui.Separator();

            if ImGui.MenuItem("Exit", "Esc") { yae_request_close(); }

            ImGui.EndMenu();
        }
    }
    ImGui.EndMainMenuBar();

    // Demo window
    if app_settings.imgui_demo_open
    {
        ImGui.ShowDemoWindow(*app_settings.imgui_demo_open);
    }

    // Save / Load
    if save_requested { graph_save(*graph, TEST_FILE_PATH); }
    if load_requested { graph_load(*graph, TEST_FILE_PATH); }

    // Graph windows
    dockspace_id: = ImGui.GetID("pluebrint_dockspace");
    pluebrint_window_class: = ImGui.WindowClass.{ ClassId = dockspace_id };

    flags: ImGui.WindowFlags = .NoDecoration | .NoMove | .NoSavedSettings | .NoBringToFrontOnFocus;
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

    // Graph
    ImGui.SetNextWindowClass(*pluebrint_window_class);
    // ImGui.PushStyleVar(.WindowPadding, .{1,1});
    if ImGui.Begin("graph")
    {
        draw_list: = ImGui.GetWindowDrawList();
        graph_mouse_position: = screen_to_canvas(*graph_canvas, ImGui.GetMousePos());
        previous_graph_mouse_position: = screen_to_canvas(*graph_canvas, ImGui.GetIO().MousePosPrev);
        delta: = graph_mouse_position - previous_graph_mouse_position;

        // Selection
        selection_bounds: Bounds;
        under_mouse_node: s32 = -1;
        if drag_mode == .SELECTING
        {
            array_clear(*selection);
            selection_bounds = make_bounds(drag_start, graph_mouse_position);
        }

        for id: selection
        {
            node: = pool_get(*graph.nodes, id);
            if drag_mode == .MOVING
            {
                node.position += delta;
                
            }
        }

        // Graph
        imgui_canvas_begin(*graph_canvas);

        for node: graph.nodes
        {
            draw_node(*graph_canvas, node);

            node_bounds: = make_bounds(node.position, node.position + .{NODE_SIZE.x, -NODE_SIZE.y});
            if collision_bounds_bounds(selection_bounds, node_bounds)
            {
                array_add(*selection, node.id);
            }

            if collision_point_bounds(graph_mouse_position, node_bounds)
            {
                under_mouse_node = node.id;
            }
        }

        for id: selection
        {
            SELECTION_THICKNESS :: 0.3;
            SELECTION_MARGIN :: 0.2;
            node: = pool_get(*graph.nodes, id);

            additional_radius: = SELECTION_MARGIN + SELECTION_THICKNESS * 0.5;
            bounds: = node_bounds(node);
            bounds = dilate(bounds, additional_radius);

            imgui_canvas_draw_bounds(*graph_canvas, bounds, .{255,196,57,255}, SELECTION_THICKNESS, NODE_ROUNDING + additional_radius, .SCALE_THICKNESS|.SCALE_ROUNDING);
        }

        imgui_canvas_draw_bounds(*graph_canvas, selection_bounds, Color.{255, 255, 255, 127});

        imgui_canvas_end(*graph_canvas);
        graph_hovered: = ImGui.IsItemHovered(.AllowWhenBlockedByActiveItem);

        if left_mouse_released && graph_hovered
        {
            if drag_mode == .NONE
            {
                array_clear(*selection);
                if under_mouse_node >= 0
                {
                    array_add(*selection, under_mouse_node);
                }
            }

            drag_mode = .NONE;
            
        }

        if graph_hovered
        {
            // Context Menu Input
            if right_mouse_released
            {
                context_position = graph_mouse_position;
            }

            // Selection Input
            if left_mouse_pressed
            {
                drag_start = graph_mouse_position;
            }

            if drag_mode == .NONE && left_mouse_down && previous_graph_mouse_position == drag_start && graph_mouse_position != drag_start
            {
                if under_mouse_node >= 0
                {
                    drag_mode = .MOVING;
                    if !array_find(selection, under_mouse_node)
                    {
                        array_clear(*selection);
                        array_add(*selection, under_mouse_node);
                    }
                }
                else
                {
                    drag_mode = .SELECTING;
                }
            }
        }

        // Context Menu
        if ImGui.BeginPopupContextItem()
        {
            if ImGui.Selectable("Create Node") { add_node(*graph, "node", context_position); }
            ImGui.EndPopup();
        }
    }
    // ImGui.PopStyleVar();
    ImGui.End();

    // Properties
    ImGui.SetNextWindowClass(*pluebrint_window_class);
    if ImGui.Begin("properties")
    {
        ImGui.Text("props");
        ImGui.Value("clk", left_mouse_pressed);
        // ImGui.Value("hov", graph_hovered);
        // ImGui.Value("pgmp", previous_graph_mouse_position);
        // ImGui.Value("gmp", graph_mouse_positi1on);
        // ImGui.Value("min", selection_bounds.min);
        // ImGui.Value("max", selection_bounds.max);
        // ImGui.Value("is_selecting", drag_mode);
    }
    ImGui.End();

    // Output
    ImGui.SetNextWindowClass(*pluebrint_window_class);
    if ImGui.Begin("output")
    {
        ImGui.Text("output");
    }
    ImGui.End();

    if ImGui.IsKeyPressed(.ImGuiKey_Delete)
    {
        for id: selection
        {
            remove_node(*graph, id);
        }
        array_clear(*selection);
    }
}

draw :: ()
{
    clear_background();
}

draw_node :: (canvas: *ImGuiCanvas, node: *Node)
{
    bounds: = canvas_to_screen(canvas, node_bounds(node));
    header_end: = canvas_to_screen(canvas, node.position + .{NODE_SIZE.x, -2.0});
    text_pos: = canvas_to_screen(canvas, node.position + .{0.8, -0.6});
    rounding: = NODE_ROUNDING * canvas.zoom.x * canvas.grid_step;
    font_size: = 13.0 * canvas.zoom.x;

    draw_list: = ImGui.GetWindowDrawList();
    ImGui.ImDrawList.AddRectFilled(draw_list, bounds.min, bounds.max, 0xFF121212, rounding);
    ImGui.ImDrawList.PushClipRect(draw_list, bounds.min, header_end, true);
    ImGui.ImDrawList.AddRectFilled(draw_list, bounds.min, bounds.max, 0xFF1212BB, rounding);
    ImGui.ImDrawList.PopClipRect(draw_list);

    // @NOTE(remi): We probably need to preload several font sizes. See ScaleAllSizes() function
    ImGui.ImDrawList.AddText(draw_list, null, font_size, text_pos, 0xFFFFFFFF, node.name.str);
}

node_bounds :: (node: *Node) -> Bounds
{
    return make_bounds(node.position, node.position + .{NODE_SIZE.x, -NODE_SIZE.y});
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