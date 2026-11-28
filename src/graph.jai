Graph :: struct
{
    nodes: SimplePool(Node); @serialize
    pins: SimplePool(Pin); @serialize
    constants: SimplePool(Constant); @serialize
}

Node :: struct
{
    graph: *Graph;

    id: s32; @serialize
    definition_id: u32; @serialize
    position: Vector2; @serialize
    first_in_pin: s32 = -1; @serialize
    first_out_pin: s32 = -1; @serialize

    size: Vector2;
    definition: *NodeDefinition;
}

PinDirection :: enum u8
{
    IN;
    OUT;
}

PinKind :: enum u8
{
    EXEC;
    VALUE;
}

ValueType :: enum u8
{
    NONE;
    BOOL;
    INTEGER;
    FLOAT;
}

Pin :: struct
{
    graph: *Graph;

    id: s32; @serialize
    node: s32 = -1; @serialize
    next_pin: s32 = -1; @serialize
    target_pin: s32 = -1; @serialize
    constant: s32 = -1; @serialize

    definition: PinDefinition; @serialize // this is part of the cache, but we can use this to solve incoherent state later
    direction: PinDirection;
    position: Vector2;
    index: s32 = -1;
}

Constant :: struct /*@custom_serialize(serialize_constant)*/
{
    union type: ValueType
    {
        none: void;
        boolean: bool;
        integer: s32;
        _float: float;
    }
}

PinDefinition :: struct
{
    kind: PinKind; @serialize
    type: ValueType; @serialize
    name: StringHash; @serialize
    name_width: float;
}

NodeDefinition :: struct
{
    id: u32;
    name: StringHash;
    in_pins: [..]PinDefinition;
    out_pins: [..]PinDefinition;
    name_width: float;
}

default_definition : NodeDefinition;
node_definitions: [..]*NodeDefinition;
node_definition_by_id: Table(u32, *NodeDefinition);

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
        build_node_cache(graph, node);
    }

    for pin: graph.pins
    {
        assert(pin.graph != null, "orphan pins in the graph");
        assert(pin.node >= 0, "orphan pins in the graph");
    }

    return true;
}

add_node :: (graph: *Graph, definition: *NodeDefinition, position: Vector2) -> *Node
{
    assert(graph != null);
    assert(definition != null);

    node, id: = pool_add(*graph.nodes);
    node.graph = graph;
    node.id = id;
    node.definition_id = definition.id;
    node.position = position;

    for pin: definition.in_pins { add_pin(node, .IN); }
    for pin: definition.out_pins { add_pin(node, .OUT); }

    build_node_cache(graph, node);

    return node;
}

can_pins_connect :: (a: *Pin, b: *Pin) -> bool
{
    if a == null return false;
    if b == null return false;
    if a.node == b.node return false;
    if a.direction == b.direction return false;
    if a.definition.kind != b.definition.kind return false;
    if a.definition.type != b.definition.type return false;

    return true;
}

connect_pins :: (a: *Pin, b: *Pin) -> bool
{
    if !can_pins_connect(a, b) return false;
    if a.target_pin == b.id return true;

    clear_pin(a);
    clear_pin(b);

    if b.target_pin >= 0
    {
        pin: = pool_get(*b.graph.pins, b.target_pin);
        pin.target_pin = -1;
    }

    a.target_pin = b.id;
    b.target_pin = a.id;

    return true;
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

register_node_definition :: (name: string, in_pins: []PinDefinition, out_pins: []PinDefinition)
{
    definition: = New(NodeDefinition);
    definition.name = string_hash(name);
    definition.name_width = imgui_text_width(name);

    for pin: in_pins { array_add(*definition.in_pins, pin); }
    for pin: out_pins { array_add(*definition.out_pins, pin); }

    // Compute id (hash of name + all pin types)
    // hashed memory layout:
    // name_hash(32) | in_pins: [pin_kind(8)|pin_type(8)] | spacing(8) | out_pins: [pin_kind(8)|pin_type(8)]
    buffer_size: = 4 + 1 + (in_pins.count + out_pins.count) * 2;
    buffer: *u8 = talloc(buffer_size);
    memcpy(buffer, *definition.name.hash, 4);
    for pin, i: definition.in_pins {
        buffer[4 + (i*2)] = xx pin.kind;
        buffer[4 + (i*2)+1] = xx pin.type;
    }
    buffer[4 + in_pins.count*2] = 255;
    for pin, i: definition.out_pins {
        buffer[4 + 1 + ((in_pins.count+i)*2)] = xx pin.kind;
        buffer[4 + 1 + ((in_pins.count+i)*2)+1] = xx pin.type;
    }
    definition.id = sdbm_hash(buffer, buffer_size);

    array_add(*node_definitions, definition);
    table_add(*node_definition_by_id, definition.id, definition);
}

get_node_definition :: (id: u32) -> *NodeDefinition
{
    found, definition: = table_find(*node_definition_by_id, id);
    if !found definition = *default_definition;
    return definition;
}

exec_pin :: (name: string = "") -> PinDefinition
{
    return .{.EXEC, .NONE, string_hash(name), imgui_text_width(name)};
}

value_pin :: (type: ValueType, name: string = "") -> PinDefinition
{
    return .{.VALUE, type, string_hash(name), imgui_text_width(name)};
}

node_name :: (node: *Node) -> string
{
    assert(node != null);
    if node.definition == null return "";
    return node.definition.name.str;
}

#scope_file
build_node_cache :: (graph: *Graph, node: *Node)
{
    node.graph = graph;
    node.definition = get_node_definition(node.definition_id);

    traverse_pins :: (node: *Node, first_index: s32, direction: PinDirection)
    {
        pin_id: = first_index;
        i: s32 = 0;
        while pin_id >= 0
        {
            pin: = pool_get(*node.graph.pins, pin_id);
            build_pin_cache(node, pin, direction, i);

            pin_id = pin.next_pin;
            i += 1;
        }
    }
    traverse_pins(node, node.first_in_pin, .IN);
    traverse_pins(node, node.first_out_pin, .OUT);
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

build_pin_cache :: (parent: *Node, pin: *Pin, direction: PinDirection, index: s32)
{
    assert(parent != null);
    assert(pin != null);
    assert(pin.node == parent.id);

    pin.graph = parent.graph;
    pin.direction = direction;
    pin.index = index;
    pin.definition = .{};
    if parent.definition != null
    {
        definitions: []PinDefinition = ifx direction == .IN then parent.definition.in_pins else parent.definition.out_pins;
        if index >= 0 && index < definitions.count
        {
            pin.definition = definitions[index];
        }
    }
}

imgui_text_width :: inline (text: string) -> float { return ImGui.CalcTextSize(text).x / 16.0; }

#import "Hash_Table";
#import "Hash";