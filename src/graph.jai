Graph :: struct
{
    nodes: SimplePool(Node); @serialize
}

Node :: struct
{
    id: s32; @serialize
    name: StringHash; @serialize
    position: Vector2; @serialize
}

graph_shutdown :: (graph: *Graph)
{
    pool_reset(*graph.nodes);
}

add_node :: (graph: *Graph, name: string, position: Vector2) -> *Node
{
    node, id: = pool_add(*graph.nodes);
    node.id = id;
    node.name = string_hash(name);
    node.position = position;
    return node;
}

remove_node :: (graph: *Graph, node: *Node)
{
    remove_node(graph, node.id);
}

remove_node :: (graph: *Graph, node_id: s32)
{
    pool_remove(*graph.nodes, node_id);
}