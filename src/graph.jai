Graph :: struct
{
    nodes: SimplePool(Node); @serialize
    pins: SimplePool(Pin); @serialize
}

Node :: struct
{
    graph: *Graph;

    id: s32; @serialize
    name: StringHash; @serialize
    position: Vector2; @serialize

    first_in_pin: s32 = -1; @serialize
    first_out_pin: s32 = -1; @serialize
}

Pin :: struct
{
    graph: *Graph;

    id: s32; @serialize
    node: s32 = -1; @serialize
    next_pin: s32 = -1; @serialize
    target_pin: s32 = -1; @serialize

    position: Vector2;
}

graph_shutdown :: (graph: *Graph)
{
    pool_reset(*graph.nodes);
    pool_reset(*graph.pins);
}

graph_save :: (graph: *Graph, path: string) -> bool
{
    serializer: JsonSerializer;

    serializer_begin(*serializer, .WRITE);
    if !serialize(*serializer, graph) return false;
    serializer_end(*serializer);

    if !json_serializer_write_json_file(*serializer, path) return false;
    return true;
}

graph_load :: (graph: *Graph, path: string) -> bool
{
    serializer: JsonSerializer;
    if !json_serializer_open_json_file(*serializer, path) return false;

    serializer_begin(*serializer, .READ);
    if !serialize(*serializer, graph) return false;
    serializer_end(*serializer);

    for node: graph.nodes
    {
        node.graph = graph;
    }

    for pin: graph.pins
    {
        pin.graph = graph;
    }

    return true;
}

add_node :: (graph: *Graph, name: string, position: Vector2) -> *Node
{
    node, id: = pool_add(*graph.nodes);
    node.graph = graph;
    node.id = id;
    node.name = string_hash(name);
    node.position = position;
    return node;
}

PinDirection :: enum
{
    IN;
    OUT;
}

add_pin :: (node: *Node, direction: PinDirection) -> *Pin
{
    pin, id: = pool_add(*node.graph.pins);
    pin.graph = node.graph;
    pin.id = id;
    pin.node = node.id;

    first_ptr: *s32;
    if direction ==
    {
        case .IN; first_ptr = *node.first_in_pin;
        case .OUT; first_ptr = *node.first_out_pin;
    }

    if first_ptr.* < 0
    {
        first_ptr.* = id;
    }
    else
    {
        pin_id: = first_ptr.*;
        pin: *Pin;
        while pin_id >= 0
        {
            pin = pool_get(*node.graph.pins, pin_id);
            pin_id = pin.next_pin;
        }
        pin.next_pin = id;
    }

    return pin;
}

remove_node :: (node: *Node)
{
    remove_pins :: (graph: *Graph, first_pin: s32)
    {
        pin_id: = first_pin;
        while pin_id >= 0
        {
            pin: = pool_get(*graph.pins, pin_id);
            pin_id = pin.next_pin;
            pool_remove(*graph.pins, pin.id);
        }
    }

    remove_pins(node.graph, node.first_in_pin);
    remove_pins(node.graph, node.first_out_pin);

    pool_remove(*node.graph.nodes, node.id);
}

remove_node :: (graph: *Graph, node_id: s32)
{
    remove_node(pool_get(*graph.nodes, node_id));
}