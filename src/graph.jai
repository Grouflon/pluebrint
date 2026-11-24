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

PinDirection :: enum u8
{
    IN;
    OUT;
}

Pin :: struct
{
    graph: *Graph;

    id: s32; @serialize
    node: s32 = -1; @serialize
    next_pin: s32 = -1; @serialize
    target_pin: s32 = -1; @serialize

    direction: PinDirection;
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

    init_pins :: (graph: *Graph, first_id: s32, direction: PinDirection)
    {
        pin_id: = first_id;
        while pin_id >= 0
        {
            pin: = pool_get(*graph.pins, pin_id);
            pin.graph = graph;
            pin.direction = direction;

            pin_id = pin.next_pin;
        }
    }

    for node: graph.nodes
    {
        node.graph = graph;

        init_pins(graph, node.first_in_pin, .IN);
        init_pins(graph, node.first_out_pin, .OUT);
    }

    for pin: graph.pins
    {
        assert(pin.graph != null, "orphan pins in the graph");
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

add_pin :: (node: *Node, direction: PinDirection) -> *Pin
{
    pin, id: = pool_add(*node.graph.pins);
    pin.graph = node.graph;
    pin.id = id;
    pin.node = node.id;
    pin.direction = direction;

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

connect_pins :: (a: *Pin, b: *Pin)
{
    if a.target_pin == b.id return;
    if a.node == b.node return;

    clear_pin(a);
    clear_pin(b);

    if b.target_pin >= 0
    {
        pin: = pool_get(*b.graph.pins, b.target_pin);
        pin.target_pin = -1;
    }

    a.target_pin = b.id;
    b.target_pin = a.id;
}

clear_pin :: (pin: *Pin)
{
    if pin.target_pin >= 0
    {
        target_pin: = pool_get(*pin.graph.pins, pin.target_pin);
        target_pin.target_pin = -1;
        pin.target_pin = -1;
    }
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
            clear_pin(pin);
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