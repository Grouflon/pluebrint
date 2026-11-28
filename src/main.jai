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
    register_node_definition("start",
        .[
        ],
        .[
            exec_pin(),
        ]
    );
    register_node_definition("print",
        .[
            exec_pin("in"),
            value_pin(.FLOAT, "number"),
        ],
        .[
            exec_pin("out"),
        ]
    );
    register_node_definition("+",
        .[
            value_pin(.FLOAT),
            value_pin(.FLOAT),
        ],
        .[
            value_pin(.FLOAT),
        ]
    );

    graph_load(*graph, TEST_FILE_PATH);
    for node: graph.nodes
    {
        node_update_positions(node);
    }
}

shutdown :: ()
{
    graph_shutdown(*graph);
    array_reset(*selection);
}

NODE_ROUNDING :: 1;
NODE_HEADER_HEIGHT :: 2.0;
NODE_X_PADDING :: 0.8;
NODE_Y_PADDING :: 1.0;
NODE_MIN_WIDTH :: 4;
NODE_COLUMN_MARGIN :: 0.8;
PIN_RADIUS :: 0.4;
PIN_LINE_HEIGHT :: 1.5;
PIN_TEXT_MARGIN :: 0.4;

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
    PIN;
    DUMMY;
}

selection: [..]s32;
drag_start: Vector2;
dragged_pin: s32;
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
    alt_down: = ImGui.IsKeyDown(.Mod_Alt);

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

    hovered_node: s32 = -1;
    hovered_pin: s32 = -1;

    // Graph
    ImGui.SetNextWindowClass(*pluebrint_window_class);
    // ImGui.PushStyleVar(.WindowPadding, .{1,1});
    if ImGui.Begin("graph")
    {
        graph_mouse_position: = screen_to_canvas(*graph_canvas, ImGui.GetMousePos());
        previous_graph_mouse_position: = screen_to_canvas(*graph_canvas, ImGui.GetIO().MousePosPrev);
        delta: = graph_mouse_position - previous_graph_mouse_position;

        // Graph
        imgui_canvas_begin(*graph_canvas);
        draw_list: = ImGui.GetWindowDrawList();

        // Selection
        selection_bounds: Bounds;
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
                node_update_positions(node);
            }
        }

        // Pins
        squared_detection_distance: = pow(PIN_RADIUS * 1.1, 2);
        for pin: graph.pins
        {
            if distance_squared(pin.position, graph_mouse_position) <= squared_detection_distance
            {
                hovered_pin = pin.id;
            }

            if pin.direction == .OUT && pin.target_pin >= 0
            {
                target_pin: = pool_get(*graph.pins, pin.target_pin);
                draw_connection(*graph_canvas, pin.position, target_pin.position, pin_type_to_color(pin.definition));
            }
        }

        if drag_mode == .PIN
        {
            assert(dragged_pin >= 0);
            pin: = pool_get(*graph.pins, dragged_pin);

            a: Vector2;
            b: Vector2;

            if pin.direction == .OUT
            {
                a = pin.position;
                b = graph_mouse_position;
            }
            else
            {
                a = graph_mouse_position;
                b = pin.position;
            }

            draw_connection(*graph_canvas, a, b, pin_type_to_color(pin.definition));
        }

        for node: graph.nodes
        {
            draw_node(*graph_canvas, node);

            bounds: = node_bounds(node);
            if collision_bounds_bounds(selection_bounds, bounds)
            {
                array_add(*selection, node.id);
            }

            if hovered_pin < 0 && collision_point_bounds(graph_mouse_position, bounds)
            {
                hovered_node = node.id;
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

        if drag_mode == .SELECTING
        {
            imgui_canvas_draw_bounds(*graph_canvas, selection_bounds, Color.{255, 255, 255, 127});
        }

        imgui_canvas_end(*graph_canvas);
        graph_hovered: = ImGui.IsItemHovered(.AllowWhenBlockedByActiveItem);
        if !graph_hovered
        {
            hovered_node = -1;
            hovered_pin = -1;
        }

        if graph_hovered
        {
            if left_mouse_released
            {
                if drag_mode == .PIN
                {
                    if hovered_pin >= 0
                    {
                        source_pin: = pool_get(*graph.pins, dragged_pin);
                        target_pin: = pool_get(*graph.pins, hovered_pin);
                        if source_pin.direction != target_pin.direction
                        {
                            connect_pins(source_pin, target_pin);
                        }
                    }
                }
                else if drag_mode == .NONE
                {
                    array_clear(*selection);
                    if hovered_node >= 0
                    {
                        array_add(*selection, hovered_node);
                    }
                }
            }

            // Context Menu Input
            if right_mouse_released
            {
                context_position = graph_mouse_position;
            }

            if left_mouse_pressed
            {
                if alt_down && hovered_pin >= 0
                {
                    pin: = pool_get(*graph.pins, hovered_pin);
                    clear_pin(pin);
                    drag_mode = .DUMMY;
                }

                // Selection
                drag_start = graph_mouse_position;
                dragged_pin = hovered_pin;
            }

            if drag_mode == .NONE && left_mouse_down && previous_graph_mouse_position == drag_start && graph_mouse_position != drag_start
            {
                if dragged_pin >= 0
                {
                    drag_mode = .PIN;
                }
                else if hovered_node >= 0
                {
                    drag_mode = .MOVING;
                    if !array_find(selection, hovered_node)
                    {
                        array_clear(*selection);
                        array_add(*selection, hovered_node);
                    }
                }
                else
                {
                    drag_mode = .SELECTING;
                }
            }
        }

        if left_mouse_released
        {
            drag_mode = .NONE;
            dragged_pin = -1;
        }

        // Context Menu
        if ImGui.BeginPopupContextItem()
        {
            for definition: node_definitions
            {
                if ImGui.Selectable(temp_c_string(definition.name.str))
                {
                    node: = add_node(*graph, definition, context_position);
                    node_update_positions(node);
                }
            }
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
        ImGui.Value("hovered_node", hovered_node);
        ImGui.Value("hovered_pin", hovered_pin);
        ImGui.Value("dragged_pin", dragged_pin);
        ImGui.Value("drag_mode", drag_mode.(s32));

        if ImGui.Button("lol")
        {
            log("%", ImGui.CalcTextSize("a"));
        }
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

    ImGui.SetMouseCursor(.Arrow);
    if drag_mode == .NONE
    {
        if hovered_pin >= 0
        {
            ImGui.SetMouseCursor(.Cross);
        }
        else if hovered_node >= 0
        {
            ImGui.SetMouseCursor(.ResizeAll);
        }
    }
    else if drag_mode == .PIN && hovered_pin >= 0 && hovered_pin != dragged_pin
    {
        pin1: = pool_get(*graph.pins, dragged_pin);
        pin2: = pool_get(*graph.pins, hovered_pin);

        if !can_pins_connect(pin1, pin2)
        {
            ImGui.SetMouseCursor(.NotAllowed);
        }
        else
        {
            ImGui.SetMouseCursor(.Cross);
        }
    }

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
    header_end: = canvas_to_screen(canvas, node.position + .{node.size.x, -NODE_HEADER_HEIGHT});
    text_pos: = canvas_to_screen(canvas, node.position + .{NODE_X_PADDING, -0.6});
    zoom: = max(canvas.zoom.x, canvas.zoom.y);
    scale: = zoom * canvas.grid_step;
    rounding: = NODE_ROUNDING * scale;
    font_size: = 13.0 * zoom;


    draw_list: = ImGui.GetWindowDrawList();
    draw_list.AddRectFilled(draw_list, bounds.min, bounds.max, 0xAA121212, rounding);
    draw_list.PushClipRect(draw_list, bounds.min, header_end, true);
    draw_list.AddRectFilled(draw_list, bounds.min, bounds.max, 0xAA1212BB, rounding);
    draw_list.PopClipRect(draw_list);

    // @NOTE(remi): We probably need to preload several font sizes. See ScaleAllSizes() function
    draw_list.AddText(draw_list, null, font_size, text_pos, 0xFFFFFFFF, node.definition.name.str);

    PIN_THICKNESS :: 0.1;
    draw_pins :: (canvas: *ImGuiCanvas, graph: *Graph, first_pin: s32, font_size: float, direction: PinDirection)
    {
        draw_list: = ImGui.GetWindowDrawList();
        pin_id: = first_pin;
        direction_sign: = ifx direction == .IN then 1.0 else -1.0;
        while pin_id >= 0
        {
            pin: = pool_get(*graph.pins, pin_id);

            text_x_offset: = ifx direction == .IN then PIN_RADIUS + PIN_TEXT_MARGIN else -PIN_RADIUS - PIN_TEXT_MARGIN - pin.definition.name_width;
            text_position: = pin.position + .{text_x_offset, 0.4};

            pin_color: = color_to_u32(pin_type_to_color(pin.definition));
            fill_color: u32 = xx ifx pin.target_pin >= 0 then pin_color else 0xFF121212;
            draw_list.AddCircleFilled(draw_list, canvas_to_screen(canvas, pin.position), canvas_to_screen(canvas, PIN_RADIUS), fill_color);
            draw_list.AddCircle(draw_list, canvas_to_screen(canvas, pin.position), canvas_to_screen(canvas, PIN_RADIUS), pin_color, thickness = canvas_to_screen(canvas, PIN_THICKNESS));
            draw_list.AddText(draw_list, null, font_size, canvas_to_screen(canvas, text_position), 0xFFFFFFFF, pin.definition.name.str);

            pin_id = pin.next_pin;
        }
    }

    draw_pins(canvas, node.graph, node.first_in_pin, font_size, .IN);
    draw_pins(canvas, node.graph, node.first_out_pin, font_size, .OUT);
}

draw_connection :: (canvas: *ImGuiCanvas, a: Vector2, b: Vector2, color: Color)
{
    draw_list: = ImGui.GetWindowDrawList();

    MIN_HANDLE :: 4.0;
    bezier: [4]Vector2;
    bezier[0] = a;
    bezier[3] = b;
    handle_length: = MIN_HANDLE + abs((bezier[3].x - bezier[0].x) * 0.5 - MIN_HANDLE);
    bezier[1] = bezier[0] + .{handle_length, 0};
    bezier[2] = bezier[3] - .{handle_length, 0};

    bezier[0] = canvas_to_screen(canvas, bezier[0]);
    bezier[1] = canvas_to_screen(canvas, bezier[1]);
    bezier[2] = canvas_to_screen(canvas, bezier[2]);
    bezier[3] = canvas_to_screen(canvas, bezier[3]);

    draw_list.AddBezierCubic(
        draw_list, 
        bezier[0], 
        bezier[1], 
        bezier[2], 
        bezier[3], 
        color_to_u32(color), 
        canvas_to_screen(canvas, 0.2)
    );
}

node_bounds :: (node: *Node) -> Bounds
{
    return make_bounds(node.position, node.position + .{node.size.x, -node.size.y});
}

node_update_positions :: (node: *Node)
{
    pins_update_position :: (graph: *Graph, first_pin: s32, start_position: Vector2)
    {
        pin_id: = first_pin;
        i: = 0;
        while pin_id >= 0
        {
            pin: = pool_get(*graph.pins, pin_id);
            pin.position = start_position + .{0, -PIN_LINE_HEIGHT * i};
            pin_id = pin.next_pin;
            i += 1;
        }
    }

    compute_column_size :: (graph: *Graph, first_pin: s32) -> count: s32, max_width: float
    {
        i: s32 = 0;
        pin_id: = first_pin;
        max_width: = 0.0;
        while pin_id >= 0
        {
            pin: = pool_get(*graph.pins, pin_id);
            max_width = max(max_width, pin.definition.name_width);
            pin_id = pin.next_pin;
            i += 1;
        }
        return i, (max_width + PIN_RADIUS * 2.0 + PIN_TEXT_MARGIN);
    }

    node_width: float = NODE_MIN_WIDTH;
    node_width = max(node_width, node.definition.name_width + 2 * NODE_X_PADDING);

    base_y: = node.position.y - NODE_HEADER_HEIGHT - NODE_Y_PADDING;
    x_padding: = NODE_X_PADDING + PIN_RADIUS;

    left_column_count, left_column_width: = compute_column_size(node.graph, node.first_in_pin);
    right_column_count, right_column_width: = compute_column_size(node.graph, node.first_out_pin);

    node_width = max(node_width, left_column_width + NODE_COLUMN_MARGIN + right_column_width + 2 * NODE_X_PADDING);

    node.size = .{ node_width, NODE_HEADER_HEIGHT + NODE_Y_PADDING * 2.0 + PIN_LINE_HEIGHT * (max(left_column_count, right_column_count, 1)-1) };

    pins_update_position(node.graph, node.first_in_pin, .{ node.position.x + x_padding, base_y });
    pins_update_position(node.graph, node.first_out_pin, .{ node.position.x + node_width - x_padding, base_y });
}

pin_type_to_color :: (definition: PinDefinition) -> Color
{
    if definition.kind ==
    {
        case .EXEC; return WHITE;
        case;
        {
            if definition.type ==
            {
                case .BOOL; return .{149,0,0,255};
                case .INTEGER; return .{31,227,175,255};
                case .FLOAT; return .{56,213,0,255};
                case; return WHITE;
            }
        }
    }
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